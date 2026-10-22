// dots-accounts against a local stub of the usage endpoint, with a scratch HOME, XDG dirs and Claude account homes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';

const bin = new URL('../../bin/dots-accounts', import.meta.url).pathname;
const usage = readFileSync(new URL('./fixtures/claude-usage.json', import.meta.url));
const TOKEN = { main: 'sk-ant-oat01-MAIN-test-token', work: 'sk-ant-oat01-WORK-test-token' };
const REFRESH = 'sk-ant-ort01-REFRESH-test-token';
const HOUR = 3600e3;

// The stub answers with whatever `mode` holds at the time and records every request.
async function stub(t) {
  const s = { seen: [], mode: 'ok' };
  const server = createServer((req, res) => {
    s.seen.push({ url: req.url, method: req.method, headers: req.headers });
    const send = (status, body) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(body);
    };
    if (s.mode === 'ok') send(200, usage);
    else if (s.mode === 'slow') setTimeout(() => send(200, usage), 300);
    else if (s.mode === 'nolimits') send(200, JSON.stringify({ five_hour: { utilization: 34 } }));
    else send(s.mode, '{"error":{"message":"sk-ant-oat01-ECHO forged\\n reason"}}');
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  s.url = `http://127.0.0.1:${server.address().port}`;
  return s;
}

function creds(home, token, expiresAt) {
  mkdirSync(home, { recursive: true });
  const file = join(home, '.credentials.json');
  writeFileSync(file, JSON.stringify({ claudeAiOauth: { accessToken: token, refreshToken: REFRESH, expiresAt, scopes: ['user:inference'], subscriptionType: 'max' } }));
  return file;
}

// Registry accounts: main in HOME/.claude, the others under the state dir; `homeless` ids get no home at all.
function scratch(t, url, ids = ['main', 'work'], homeless = []) {
  const root = mkdtempSync(join(tmpdir(), 'accounts-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, 'home');
  const state = join(root, 'state');
  const cache = join(root, 'cache', 'dots', 'accounts');
  const homes = {};
  for (const id of ids) homes[id] = id === 'main' ? join(home, '.claude') : join(state, 'dots', 'claude-accounts', id);
  for (const id of ids) if (!homeless.includes(id)) creds(homes[id], TOKEN[id] || `sk-ant-oat01-${id}`, Date.now() + HOUR);
  mkdirSync(join(state, 'dots'), { recursive: true });
  const accounts = ids.map((id) => ({ id, label: id, home: homes[id], email: `${id}@example.com`, plan: 'max' }));
  writeFileSync(join(state, 'dots', 'claude-accounts.json'), JSON.stringify({ active: 'main', accounts }));
  const env = {
    PATH: process.env.PATH,
    HOME: home,
    XDG_CONFIG_HOME: join(root, 'config'),
    XDG_STATE_HOME: state,
    XDG_CACHE_HOME: join(root, 'cache'),
    XDG_DATA_HOME: join(root, 'data'),
    XDG_RUNTIME_DIR: join(root, 'run'),
    TZ: 'Asia/Dhaka',
    DOTS_ACCOUNTS_ANTHROPIC_URL: url,
  };
  return { root, env, homes, cache };
}

function run(ctx, ...args) {
  return new Promise((resolve) => {
    const p = spawn(bin, args, { env: ctx.env });
    let stdout = '';
    let stderr = '';
    p.stdout.on('data', (d) => (stdout += d));
    p.stderr.on('data', (d) => (stderr += d));
    p.on('error', (e) => resolve({ status: null, stdout, stderr: String(e) }));
    p.on('close', (status) => resolve({ status, stdout, stderr }));
  });
}

async function rows(ctx, ...args) {
  const r = await run(ctx, ...args);
  assert.equal(r.status, 0, r.stderr);
  const out = JSON.parse(r.stdout);
  assert.ok(Array.isArray(out), r.stdout);
  return { out, r };
}

const cacheFiles = (ctx) => readdirSync(ctx.cache).map((f) => [f, readFileSync(join(ctx.cache, f), 'utf8')]);
const of = (out, account) => out.filter((row) => row.account === account);
const strip = (list) => list.map(({ as_of, ...rest }) => rest);
const sha = (file) => createHash('sha256').update(readFileSync(file)).digest('hex');

const limits = (account, state = 'ok', reason = null) =>
  [
    ['5-hour', 34, '2026-10-22T11:00:00Z'],
    ['weekly', 61, '2026-10-29T03:00:00Z'],
    ['weekly Fable', 22, '2026-10-29T03:00:00Z'],
  ].map(([metric, value, resets_at]) => ({ provider: 'claude', label: account, account, metric, kind: 'percent', value, limit: 100, unit: '%', resets_at, state, reason }));

test('prints each registry account limits from the usage response', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const before = Date.now();
  const { out } = await rows(ctx);
  const after = Date.now();
  assert.deepEqual(strip(out), [...limits('main'), ...limits('work')]);
  for (const row of out) {
    assert.equal(typeof row.value, 'number');
    assert.equal(typeof row.as_of, 'string');
    const at = Date.parse(row.as_of);
    assert.ok(at >= before - 1000 && at <= after, row.as_of);
  }
  assert.equal(s.seen.length, 2);
  for (const req of s.seen) {
    assert.equal(req.method, 'GET');
    assert.equal(req.url, '/api/oauth/usage');
    assert.equal(req.headers['anthropic-beta'], 'oauth-2025-04-20');
  }
  assert.deepEqual(s.seen.map((q) => q.headers.authorization).sort(), [`Bearer ${TOKEN.main}`, `Bearer ${TOKEN.work}`]);
  assert.ok(!JSON.stringify(s.seen).includes(REFRESH), 'the refresh token is never sent');
  assert.deepEqual(cacheFiles(ctx).map(([f]) => f).sort(), ['claude-main.json', 'claude-work.json']);
});

test('a failing fetch serves the cached rows as stale with their old time', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const testStart = Date.now();
  await rows(ctx);
  s.mode = 500;
  const start = Date.now();
  const { out } = await rows(ctx);
  assert.deepEqual(strip(out), [...limits('main', 'stale', 'network'), ...limits('work', 'stale', 'network')]);
  for (const row of out) {
    const at = Date.parse(row.as_of);
    assert.ok(at < start && at >= testStart - 1000, row.as_of);
  }
});

test('an expired token sends nothing and leaves the credentials file as it was', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  await rows(ctx);
  const file = creds(ctx.homes.main, TOKEN.main, Date.now() - 1000);
  const hash = sha(file);
  s.seen.length = 0;
  const { out } = await rows(ctx);
  assert.equal(s.seen.length, 0);
  assert.deepEqual(strip(out), limits('main', 'stale', 'expired'));
  assert.equal(sha(file), hash);
});

test('an expired token with no cache gives one auth placeholder', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  creds(ctx.homes.main, TOKEN.main, Date.now() - 1000);
  const { out } = await rows(ctx);
  assert.equal(s.seen.length, 0);
  assert.deepEqual(strip(out), [{ provider: 'claude', label: 'main', account: 'main', metric: null, kind: null, value: null, limit: null, unit: null, resets_at: null, state: 'auth', reason: 'expired' }]);
});

test('a 429 is asked once and serves stale rows', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  await rows(ctx);
  s.mode = 429;
  s.seen.length = 0;
  const { out } = await rows(ctx);
  assert.equal(s.seen.length, 1);
  assert.deepEqual(strip(out), limits('main', 'stale', 'rate-limited'));
});

test('an account whose home is missing gets a no-home row and main still draws', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main', 'ghost'], ['ghost']);
  const { out } = await rows(ctx);
  assert.deepEqual(strip(of(out, 'main')), limits('main'));
  assert.deepEqual(strip(of(out, 'ghost')), [{ provider: 'claude', label: 'ghost', account: 'ghost', metric: null, kind: null, value: null, limit: null, unit: null, resets_at: null, state: 'error', reason: 'no-home' }]);
  assert.equal(s.seen.length, 1);
});

test('a body without limits reads as shape', async (t) => {
  const s = await stub(t);
  s.mode = 'nolimits';
  const ctx = scratch(t, s.url, ['main']);
  const { out } = await rows(ctx);
  assert.deepEqual(
    out.map((r) => [r.account, r.state, r.reason, r.value]),
    [['main', 'error', 'shape', null]],
  );
});

test('two collectors at once both print whole JSON and leave whole cache files', async (t) => {
  const s = await stub(t);
  s.mode = 'slow';
  const ctx = scratch(t, s.url);
  const [a, b] = await Promise.all([run(ctx), run(ctx)]);
  for (const r of [a, b]) {
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(strip(JSON.parse(r.stdout)), [...limits('main'), ...limits('work')]);
  }
  const files = cacheFiles(ctx);
  assert.deepEqual(files.map(([f]) => f).sort(), ['claude-main.json', 'claude-work.json']);
  for (const [f, text] of files) assert.equal(JSON.parse(text).length, 3, f);
});

test('--cached prints the cached rows of registry accounts with no request', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const first = (await rows(ctx)).out;
  writeFileSync(join(ctx.cache, 'claude-gone.json'), JSON.stringify(limits('gone')));
  s.seen.length = 0;
  const { out } = await rows(ctx, '--cached');
  assert.equal(s.seen.length, 0);
  assert.deepEqual(out, first);
});

test('no token reaches the output or the cache', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const ok = await rows(ctx);
  s.mode = 401;
  const failed = await rows(ctx);
  assert.deepEqual(
    failed.out.map((r) => [r.state, r.reason]),
    Array(6).fill(['stale', 'expired']),
  );
  const cached = await rows(ctx, '--cached');
  const files = cacheFiles(ctx);
  assert.equal(files.length, 2);
  for (const text of [ok.r.stdout, failed.r.stdout, cached.r.stdout, ...files.map(([, x]) => x)]) {
    assert.ok(text.length > 100, text);
    assert.ok(!text.includes('sk-ant-'), text);
    assert.ok(!text.includes('forged'), text);
  }
});

// dots-accounts against a local stub of the usage endpoint, with a scratch HOME, XDG dirs and Claude account homes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { appendFileSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

const bin = new URL('../../bin/dots-accounts', import.meta.url).pathname;
const usage = readFileSync(new URL('./fixtures/claude-usage.json', import.meta.url));
const TOKEN = { main: 'sk-ant-oat01-MAIN-test-token', work: 'sk-ant-oat01-WORK-test-token' };
const REFRESH = 'sk-ant-ort01-REFRESH-test-token';
const HOUR = 3600e3;
const fixture = (name) => new URL('./fixtures/' + name, import.meta.url).pathname;
const FORGED = ['Fa\nke', 'Fake\u202Eevil', 'Fake\u001b[31m', '', 'x'.repeat(200), '\n'];

// What pxy prints with the store open, one body per parser: DeepSeek (string amounts), OpenRouter, ZenMux, Vercel, and a provider no row is made for.
const PXY_OK = {
  remote: {
    'deepseek-ai': { summary: 'x', data: { is_available: true, balance_infos: [{ currency: 'USD', total_balance: '12.34', granted_balance: '0.00' }] } },
    openrouter: { summary: 'x', data: { data: { total_credits: 25, total_usage: 7.5 } } },
    zenmux: { summary: 'x', data: { success: true, data: { currency: 'usd', total_credits: 482.74, top_up_credits: 35, bonus_credits: 447.74 } } },
    vercel: { summary: 'x', data: { balance: '8.50', total_used: '1.50' } },
    'tokenharbor#pass': { summary: 'x', data: { usedPct: 0 } },
  },
};

// Executables on the collector's PATH, each a node script that records its argv and env in the ctl dir and answers from files there.
const STUBS = {
  pass: `
const fs = require('fs');
const ctl = process.env.STUB_CTL;
fs.appendFileSync(ctl + '/pass.log', JSON.stringify({ argv: process.argv.slice(2), opts: process.env.PASSWORD_STORE_GPG_OPTS }) + '\\n');
if (fs.existsSync(ctl + '/pass-locked')) {
  process.stderr.write('gpg: decryption failed: No pinentry\\n');
  process.exit(2);
}
if (fs.existsSync(ctl + '/missing-' + process.argv[3].replace(/\\//g, '-'))) {
  process.stderr.write('Error: ' + process.argv[3] + ' is not in the password store.\\n');
  process.exit(1);
}
console.log('FAKEKEY-' + process.argv[3].replace(/\\//g, '-') + '\\nsecond line');
`,
  pxy: `
const fs = require('fs');
const ctl = process.env.STUB_CTL;
fs.appendFileSync(ctl + '/pxy.log', JSON.stringify({ argv: process.argv.slice(2), opts: process.env.PASSWORD_STORE_GPG_OPTS }) + '\\n');
const delay = fs.existsSync(ctl + '/pxy-delay') ? Number(fs.readFileSync(ctl + '/pxy-delay', 'utf8')) : 0;
setTimeout(() => process.stdout.write(fs.readFileSync(ctl + '/pxy.json')), delay);
`,
  codex: `
const fs = require('fs');
const ctl = process.env.STUB_CTL;
fs.appendFileSync(ctl + '/codex.log', JSON.stringify({ argv: process.argv.slice(2), pid: process.pid }) + '\\n');
const mode = fs.existsSync(ctl + '/codex-mode') ? fs.readFileSync(ctl + '/codex-mode', 'utf8').trim() : 'ok';
const answers = {};
for (const line of fs.readFileSync(ctl + '/codex.jsonl', 'utf8').split('\\n')) if (line) answers[JSON.parse(line).id] = JSON.parse(line);
setInterval(() => {}, 1000);
let buf = '';
process.stdin.on('data', (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\\n')) >= 0) {
    const msg = JSON.parse(buf.slice(0, i));
    buf = buf.slice(i + 1);
    if (mode === 'hang' || msg.id === undefined) continue;
    const answer = mode === 'rpcerror' && msg.id === 2 ? { id: 2, error: { code: -1, message: 'forged' } } : mode === 'noaccount' && msg.id === 2 ? { id: 2, result: { account: null, requiresOpenaiAuth: true } } : answers[msg.id];
    process.stdout.write(JSON.stringify(answer) + '\\n');
  }
});
`,
};

const ELEVEN = { tier: 'creator', character_count: 11500, character_limit: 32000, next_character_count_reset_unix: 1793000000, currency: 'usd' };
// A dollar bucket as the usage endpoint gave it on 2026-10-28, under a codename that may change.
const CREDIT = { utilization: 1.52, resets_at: '2026-11-05T07:59:00+00:00', limit_dollars: 250, used_dollars: 3.799662, remaining_dollars: 246.200338, locked_reason: null };
const FAL = { username: 'my-team', credits: { current_balance: 24.5, currency: 'USD' } };

// The stub answers with whatever `mode` holds at the time and records every request. `claude` is the usage endpoint's mode, `eleven` and `fal` the others' status.
async function stub(t) {
  const s = { seen: [], other: [], mode: 'ok', eleven: 200, fal: 200 };
  const server = createServer((req, res) => {
    const send = (status, body) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(body);
    };
    if (req.url === '/v1/user/subscription' || req.url === '/v1/account/billing?expand=credits') {
      s.other.push({ url: req.url, method: req.method, headers: req.headers });
      const eleven = req.url.startsWith('/v1/user');
      const status = eleven ? s.eleven : s.fal;
      return send(status, status === 200 ? JSON.stringify(eleven ? ELEVEN : FAL) : '{"error":{"type":"x","message":"forged"}}');
    }
    s.seen.push({ url: req.url, method: req.method, headers: req.headers });
    if (s.mode === 'ok') send(200, usage);
    else if (s.mode === 'slow') setTimeout(() => send(200, usage), 300);
    else if (s.mode === 'forged') send(200, JSON.stringify({ limits: FORGED.map((display_name, i) => ({ kind: 'weekly_scoped', percent: i + 1, resets_at: null, scope: { model: { display_name } } })) }));
    else if (s.mode === 'credit' || s.mode === 'renamed') send(200, JSON.stringify({ ...JSON.parse(usage), [s.mode === 'credit' ? 'iguana_necktie' : 'new_codename']: CREDIT }));
    else if (s.mode === 'nolimits') send(200, JSON.stringify({ five_hour: { utilization: 34 } }));
    else if (s.mode === 'newkinds') send(200, JSON.stringify({ limits: [{ kind: 'five_hour_v2', utilization: 34 }] }));
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
  const stubBin = join(root, 'bin');
  const ctl = join(root, 'ctl');
  mkdirSync(stubBin);
  mkdirSync(ctl);
  symlinkSync(process.execPath, join(stubBin, 'node'));
  for (const [name, code] of Object.entries(STUBS)) writeFileSync(join(stubBin, name), `#!${process.execPath}\n${code}`, { mode: 0o755 });
  copyFileSync(fixture('codex-app-server.jsonl'), join(ctl, 'codex.jsonl'));
  writeFileSync(join(ctl, 'pxy.json'), JSON.stringify(PXY_OK));
  const env = {
    HOME: home,
    XDG_CONFIG_HOME: join(root, 'config'),
    XDG_STATE_HOME: state,
    XDG_CACHE_HOME: join(root, 'cache'),
    XDG_DATA_HOME: join(root, 'data'),
    XDG_RUNTIME_DIR: join(root, 'run'),
    TZ: 'Asia/Dhaka',
    DOTS_ACCOUNTS_ANTHROPIC_URL: url,
    DOTS_ACCOUNTS_ELEVENLABS_URL: url,
    DOTS_ACCOUNTS_FAL_URL: url,
    PATH: stubBin,
    STUB_CTL: ctl,
  };
  return { root, env, homes, cache, ctl, stubBin };
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

async function everything(ctx, ...args) {
  const r = await run(ctx, ...args);
  assert.equal(r.status, 0, r.stderr);
  const out = JSON.parse(r.stdout);
  assert.ok(Array.isArray(out), r.stdout);
  return { out, r };
}

// The Claude tests look at Claude's rows only; the stubs of the other sources answer beside them.
async function rows(ctx, ...args) {
  const { out, r } = await everything(ctx, ...args);
  return { out: out.filter((row) => row.provider === 'claude'), r };
}

const cacheFiles = (ctx) => readdirSync(ctx.cache).filter((f) => f.startsWith('claude-')).map((f) => [f, readFileSync(join(ctx.cache, f), 'utf8')]);
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

test('a dollar bucket under any name is a credit row after the limits: what is left of the grant', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  const credit = { provider: 'claude', label: 'main', account: 'main', metric: 'credit', kind: 'money', value: 246.200338, limit: 250, unit: 'USD', resets_at: '2026-11-05T07:59:00Z', state: 'ok', reason: null };
  for (const mode of ['credit', 'renamed']) {
    s.mode = mode;
    const { out } = await rows(ctx);
    assert.deepEqual(strip(out), [...limits('main'), credit], mode);
  }
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

// The endpoint is unofficial and has changed shape before: a body whose limits name nothing known is a failure, never an empty success that wipes the cache.
test('a usage body whose limits are all of unknown kinds serves the cached rows as stale shape', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  await rows(ctx);
  s.mode = 'newkinds';
  const { out } = await rows(ctx);
  assert.deepEqual(strip(out), limits('main', 'stale', 'shape'));
  assert.deepEqual(JSON.parse(readFileSync(join(ctx.cache, 'claude-main.json'), 'utf8')).map((r) => [r.metric, r.value]), [['5-hour', 34], ['weekly', 61], ['weekly Fable', 22]]);
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
  assert.deepEqual(strip(out), [{ provider: 'claude', label: 'main', account: 'main', metric: null, kind: 'percent', value: null, limit: null, unit: null, resets_at: null, state: 'auth', reason: 'expired' }]);
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
  assert.deepEqual(strip(of(out, 'ghost')), [{ provider: 'claude', label: 'ghost', account: 'ghost', metric: null, kind: 'percent', value: null, limit: null, unit: null, resets_at: null, state: 'error', reason: 'no-home' }]);
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
    assert.deepEqual(strip(JSON.parse(r.stdout).filter((row) => row.provider === 'claude')), [...limits('main'), ...limits('work')]);
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

const R = (provider, label, metric, kind, value, limit, unit, resets_at, state = 'ok', reason = null) => ({ provider, label, account: null, metric, kind, value, limit, unit, resets_at, state, reason });
const MONEY = [
  R('deepseek-ai', 'DeepSeek', 'balance', 'money', 12.34, null, 'USD', null),
  R('openrouter', 'OpenRouter', 'balance', 'money', 17.5, 25, 'USD', null),
  R('zenmux', 'ZenMux', 'balance', 'money', 482.74, null, 'USD', null),
  R('vercel', 'Vercel AI', 'balance', 'money', 8.5, null, 'USD', null),
];
const ELEVEN_ROW = R('elevenlabs', 'ElevenLabs', 'characters', 'count', 11500, 32000, 'characters', '2026-10-26T07:33:20Z');
const FAL_ROW = R('fal', 'fal', 'balance', 'money', 24.5, null, 'USD', null);
const CODEX_ROW = R('codex', 'Codex', 'monthly', 'percent', 0, 100, '%', '2026-11-21T09:41:22Z');
const PXY_KEYS = new Set(['deepseek-ai', 'openrouter', 'zenmux', 'vercel', 'aihubmix']);
const pxyRows = (out) => out.filter((row) => PXY_KEYS.has(row.provider));
// A placeholder keeps its source's kind, so the card knows which group it draws in.
const KIND = { codex: 'percent', elevenlabs: 'count' };
const placeholder = (provider, label, state, reason) => R(provider, label, null, KIND[provider] || 'money', null, null, null, null, state, reason);
const ctlLog = (ctx, name) => (existsSync(join(ctx.ctl, name)) ? readFileSync(join(ctx.ctl, name), 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : []);
const OPTS = '--pinentry-mode error';

// A killed child can linger as a zombie for a moment, so the check waits for it to vanish.
async function gone(pid) {
  for (let i = 0; i < 50; i++) {
    try {
      process.kill(pid, 0);
    } catch {
      return true;
    }
    await new Promise((r) => setTimeout(r, 20));
  }
  return false;
}

test('every stub answering gives five money rows and two usage rows, in parallel, with no key in any argv', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  const start = Date.now();
  const { out, r } = await everything(ctx);
  const wall = Date.now() - start;
  assert.deepEqual(strip(out), [...limits('main'), ...MONEY, ELEVEN_ROW, FAL_ROW, CODEX_ROW]);
  assert.ok(wall < 2000, `took ${wall} ms`);
  for (const row of out) assert.equal(typeof row.as_of, 'string');
  const eleven = s.other.find((q) => q.url === '/v1/user/subscription');
  const fal = s.other.find((q) => q.url === '/v1/account/billing?expand=credits');
  assert.equal(eleven.headers['xi-api-key'], 'FAKEKEY-AI-elevenlabs-main');
  assert.equal(fal.headers.authorization, 'Key FAKEKEY-AI-fal-billing');
  const pass = ctlLog(ctx, 'pass.log');
  assert.deepEqual(pass.map((l) => l.argv).sort(), [['show', 'AI/elevenlabs/main'], ['show', 'AI/fal/billing']]);
  for (const l of pass) assert.equal(l.opts, OPTS);
  assert.deepEqual(ctlLog(ctx, 'pxy.log'), [{ argv: ['status', '--remote', '--json'], opts: OPTS }]);
  assert.deepEqual(ctlLog(ctx, 'codex.log').map((l) => l.argv), [['-s', 'read-only', 'app-server']]);
  for (const text of [...['pass.log', 'pxy.log', 'codex.log'].map((f) => readFileSync(join(ctx.ctl, f), 'utf8')), r.stdout, ...readdirSync(ctx.cache).map((f) => readFileSync(join(ctx.cache, f), 'utf8'))]) {
    assert.ok(!text.includes('FAKEKEY'), text);
  }
  for (const pid of ctlLog(ctx, 'codex.log').map((l) => l.pid)) assert.ok(await gone(pid), 'codex is gone after an ok run');
  assert.deepEqual(readdirSync(ctx.cache).sort(), ['claude-main.json', 'codex.json', 'elevenlabs.json', 'fal.json', 'pxy.json']);
});

test('pxy with the store locked: every pxy row is locked, and pxy ran without a pinentry', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  copyFileSync(fixture('pxy-locked.json'), join(ctx.ctl, 'pxy.json'));
  const { out } = await everything(ctx);
  assert.deepEqual(
    strip(pxyRows(out)),
    [['deepseek-ai', 'DeepSeek'], ['openrouter', 'OpenRouter'], ['zenmux', 'ZenMux'], ['vercel', 'Vercel AI'], ['aihubmix', 'AIHubMix']].map(([p, l]) => placeholder(p, l, 'auth', 'locked')),
  );
  assert.deepEqual(ctlLog(ctx, 'pxy.log').map((l) => l.opts), [OPTS]);
  assert.ok(!JSON.stringify(out).includes('pinentry'), 'no text from the summary reaches a row');
});

test('pxy timing out after a good run keeps OpenRouter at its cached value, as of before the run', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  await everything(ctx);
  ctx.env.DOTS_ACCOUNTS_LIMIT_MS = '800';
  writeFileSync(join(ctx.ctl, 'pxy-delay'), '5000');
  const start = Date.now();
  const { out } = await everything(ctx);
  const openrouter = out.find((row) => row.provider === 'openrouter');
  assert.deepEqual([openrouter.value, openrouter.limit, openrouter.state, openrouter.reason], [17.5, 25, 'stale', 'timeout']);
  assert.ok(Date.parse(openrouter.as_of) < start, openrouter.as_of);
  assert.equal(pxyRows(out).filter((row) => row.state !== 'stale').length, 0);
});

test('pxy locked after a good run serves the cached rows as stale', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  await everything(ctx);
  copyFileSync(fixture('pxy-locked.json'), join(ctx.ctl, 'pxy.json'));
  const { out } = await everything(ctx);
  assert.deepEqual(strip(pxyRows(out)), [...MONEY.map((row) => ({ ...row, state: 'stale', reason: 'locked' })), placeholder('aihubmix', 'AIHubMix', 'auth', 'locked')]);
  const cached = JSON.parse(readFileSync(join(ctx.cache, 'pxy.json'), 'utf8'));
  assert.deepEqual(cached.map((row) => [row.provider, row.state]), MONEY.map((row) => [row.provider, 'ok']));
});

test('a pxy provider with an unknown body shape is one shape row and the others stay', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  writeFileSync(join(ctx.ctl, 'pxy.json'), JSON.stringify({ remote: { ...PXY_OK.remote, openrouter: { summary: 'x', data: { surprise: 'sk-ant-forged' } } } }));
  const { out } = await everything(ctx);
  assert.deepEqual(strip(pxyRows(out)), [MONEY[0], placeholder('openrouter', 'OpenRouter', 'error', 'shape'), MONEY[2], MONEY[3]]);
});

test('a locked pass store makes elevenlabs and fal auth rows and sends no request', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  writeFileSync(join(ctx.ctl, 'pass-locked'), '');
  const { out } = await everything(ctx);
  assert.deepEqual(strip(out.filter((row) => row.provider === 'elevenlabs' || row.provider === 'fal')), [placeholder('elevenlabs', 'ElevenLabs', 'auth', 'locked'), placeholder('fal', 'fal', 'auth', 'locked')]);
  assert.equal(s.other.length, 0);
});

test('fal answering 403 is a forbidden auth row', async (t) => {
  const s = await stub(t);
  s.fal = 403;
  const ctx = scratch(t, s.url, ['main']);
  const { out } = await everything(ctx);
  assert.deepEqual(strip(out.filter((row) => row.provider === 'fal')), [placeholder('fal', 'fal', 'auth', 'forbidden')]);
  assert.ok(!JSON.stringify(out).includes('forged'));
});

test('a 401 from a pass-key source reads as no-key, not expired', async (t) => {
  const s = await stub(t);
  s.eleven = 401;
  const ctx = scratch(t, s.url, ['main']);
  const { out } = await everything(ctx);
  assert.deepEqual(strip(out.filter((row) => row.provider === 'elevenlabs')), [placeholder('elevenlabs', 'ElevenLabs', 'auth', 'no-key')]);
});

test('fal falls back to the main key when there is no billing key', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  writeFileSync(join(ctx.ctl, 'missing-AI-fal-billing'), '');
  const { out } = await everything(ctx);
  assert.deepEqual(strip(out.filter((row) => row.provider === 'fal')), [FAL_ROW]);
  assert.equal(s.other.find((q) => q.url.startsWith('/v1/account')).headers.authorization, 'Key FAKEKEY-AI-fal-main');
});

test('codex errors and a missing login are rows, and the child is gone each time', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  const codexOnly = (out) => strip(out.filter((row) => row.provider === 'codex'));
  writeFileSync(join(ctx.ctl, 'codex-mode'), 'rpcerror');
  assert.deepEqual(codexOnly((await everything(ctx)).out), [placeholder('codex', 'Codex', 'error', 'shape')]);
  writeFileSync(join(ctx.ctl, 'codex-mode'), 'noaccount');
  assert.deepEqual(codexOnly((await everything(ctx)).out), [placeholder('codex', 'Codex', 'auth', 'no-key')]);
  const pids = ctlLog(ctx, 'codex.log').map((l) => l.pid);
  assert.equal(pids.length, 2);
  for (const pid of pids) assert.ok(await gone(pid), 'codex is gone after a failed run');
});

test('a codex that never answers is a timeout row at the limit and leaves no process', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, ['main']);
  ctx.env.DOTS_ACCOUNTS_LIMIT_MS = '800';
  writeFileSync(join(ctx.ctl, 'codex-mode'), 'hang');
  const start = Date.now();
  const { out } = await everything(ctx);
  const wall = Date.now() - start;
  assert.ok(wall >= 700 && wall < 3000, `took ${wall} ms`);
  assert.deepEqual(strip(out.filter((row) => row.provider === 'codex')), [placeholder('codex', 'Codex', 'error', 'timeout')]);
  assert.deepEqual(strip(out.filter((row) => row.provider === 'fal')), [FAL_ROW]);
  for (const pid of ctlLog(ctx, 'codex.log').map((l) => l.pid)) assert.ok(await gone(pid), 'codex is gone after the limit');
  assert.equal(spawnSync('pgrep', ['-f', join(ctx.stubBin, 'codex')]).status, 1);
});

test('a forged model name never reaches a metric as more than one clean short line', async (t) => {
  const s = await stub(t);
  s.mode = 'forged';
  const ctx = scratch(t, s.url, ['main']);
  const { out } = await rows(ctx);
  assert.ok(out.length >= 1 && out.length < FORGED.length, JSON.stringify(out));
  for (const row of out) assert.match(row.metric, /^weekly [\p{L}\p{N} .-]{1,32}$/u, JSON.stringify(row.metric));
  assert.deepEqual(out.map((row) => row.metric), ['weekly Fake', 'weekly Fakeevil', 'weekly Fake31m', 'weekly ' + 'x'.repeat(32)]);
});

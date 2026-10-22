// dots-dns against a local stub of the uBlockDNS API, with a scratch HOME and XDG dirs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

const bin = new URL('../../bin/dots-dns', import.meta.url).pathname;
const fixture = (name) => new URL('./fixtures/' + name, import.meta.url).pathname;
const DEVICES = JSON.parse(readFileSync(fixture('dns-devices.json'), 'utf8'));
const PROFILE = readFileSync(fixture('dns-apple-profile.mobileconfig'));
const TOKEN = 'apple-banana-cherry-delta';
const T0 = 1792670000;
const FORGED = ['Fa\nke', 'Fake\u202Eevil', 'Fake\u001b[31m', '', 'x'.repeat(200)];

// 25 blocked answers and 5 allowed ones, out of time order, the way the server mixes them.
const QUERIES = {
  entries: [...Array.from({ length: 25 }, (_, i) => ({ domain: `blocked${i}.example`, action: 'blocked', timestamp: T0 + i * 10, query_type: 'A', response_code: 'NXDOMAIN' })), ...Array.from({ length: 5 }, (_, i) => ({ domain: `allowed${i}.example`, action: 'allowed', timestamp: T0 + 1000 + i, query_type: 'A', response_code: 'NOERROR' }))].sort((a, b) => (a.domain.length % 3) - (b.domain.length % 3) || a.domain.localeCompare(b.domain)),
  next_cursor: null,
};

// The stub keeps its own copy of the devices, answers under /api, and records every request. `session` is the cookie it accepts; `down` answers 503 to everything.
async function stub(t) {
  const s = { seen: [], devices: structuredClone(DEVICES), session: 'GOODSESSION', auth: 200, down: false, hold: 0, queries: QUERIES };
  const server = createServer((req, res) => {
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', () => {
      const send = (status, data, type = 'application/json', headers = {}) => {
        res.writeHead(status, { 'content-type': type, ...headers });
        res.end(typeof data === 'string' || Buffer.isBuffer(data) ? data : JSON.stringify(data));
      };
      const url = new URL(req.url, 'http://x');
      s.seen.push({ method: req.method, path: url.pathname, query: url.search, cookie: req.headers.cookie || '', body });
      if (s.down) return send(503, { error: 'down acct0001 dev00ipad ' + TOKEN });
      if (req.method === 'POST' && url.pathname === '/api/auth') {
        if (s.auth !== 200 || JSON.parse(body).token !== TOKEN) return send(s.auth === 200 ? 401 : s.auth, { error: 'bad token ' + TOKEN });
        s.session = 'FRESHSESSION';
        return send(200, { ok: true }, 'application/json', { 'set-cookie': 'ubd_session=FRESHSESSION; Path=/api; HttpOnly; Max-Age=31536000' });
      }
      if (!(req.headers.cookie || '').split(/; */).includes('ubd_session=' + s.session)) return send(401, { error: 'unauthorized' });
      let m;
      if (req.method === 'GET' && url.pathname === '/api/profile/prof0001') return send(200, { id: 'prof0001', account_id: 'acct0001' });
      if (req.method === 'GET' && url.pathname === '/api/account/acct0001/devices') return send(200, s.devices);
      if ((m = url.pathname.match(/^\/api\/account\/acct0001\/device\/([^/]+)(\/queries|\/apple-profile)?$/))) {
        const dev = s.devices.find((d) => d.id === m[1]);
        if (!dev) return send(404, { error: 'not found' });
        if (m[2] === '/queries') return send(200, s.queries);
        if (m[2] === '/apple-profile') return send(200, PROFILE, 'application/x-apple-aspen-config');
        if (req.method === 'GET') return setTimeout(() => send(200, structuredClone(dev)), s.hold);
        if (req.method === 'PUT') {
          Object.assign(dev, JSON.parse(body));
          return send(200, dev);
        }
      }
      send(404, { error: 'no route' });
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  s.url = `http://127.0.0.1:${server.address().port}/api`;
  return s;
}

const jar = (value) => `# Netscape HTTP Cookie File\n\n#HttpOnly_127.0.0.1\tFALSE\t/api\tFALSE\t1820303639\tubd_session\t${value}\n127.0.0.1\tFALSE\t/\tFALSE\t1792873281\tAWSALB\tlbvalue\n`;

// HOME and every XDG dir in a scratch root; PATH holds only node and flock.
function scratch(t, url, { session = 'GOODSESSION', account = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'dns-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, 'home');
  const config = join(home, '.config', 'dns-helper');
  const state = join(home, '.local', 'state', 'dns-helper');
  mkdirSync(config, { recursive: true });
  mkdirSync(state, { recursive: true });
  writeFileSync(join(config, 'token'), TOKEN + '\n');
  writeFileSync(join(config, 'profile'), 'prof0001\n');
  if (account) writeFileSync(join(config, 'account'), 'acct0001\n');
  if (session) writeFileSync(join(state, 'session'), jar(session));
  const stubBin = join(root, 'bin');
  mkdirSync(stubBin);
  symlinkSync(process.execPath, join(stubBin, 'node'));
  symlinkSync('/usr/bin/flock', join(stubBin, 'flock'));
  const env = {
    HOME: home,
    XDG_CONFIG_HOME: join(root, 'config'),
    XDG_STATE_HOME: join(root, 'state'),
    XDG_CACHE_HOME: join(root, 'cache'),
    XDG_DATA_HOME: join(root, 'data'),
    XDG_RUNTIME_DIR: join(root, 'run'),
    DOTS_DNS_API: url,
    PATH: stubBin,
  };
  return { root, home, config, state, env, stubBin };
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

async function state(ctx) {
  const r = await run(ctx, 'state');
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}

const carried = (out) => out.devices.filter((d) => d.path === 'carried');
const BLOCKS = Array.from({ length: 20 }, (_, i) => ({ domain: `blocked${24 - i}.example`, at: T0 + (24 - i) * 10 }));
const row = (key, name, kid, categories, allow) => ({ key, name, path: 'carried', kid, categories, open_until: null, allow, last_block: T0 + 240, blocks: BLOCKS, ip: null, mac: null });

test('state lists each carried device with its categories, Kid, allow list and blocks', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, { account: false });
  const before = Math.floor(Date.now() / 1000);
  const out = await state(ctx);
  assert.ok(out.as_of >= before && out.as_of <= before + 5, String(out.as_of));
  assert.deepEqual(out.carried, { ok: true, error: null });
  assert.deepEqual(carried(out), [
    row('carried:dev00phone', "Saiful's iPhone", true, { youtube: true, social: true, adult: true, gambling: false }, ['wikipedia.org']),
    row('carried:dev00ipad', 'iPad', true, { youtube: false, social: false, adult: true, gambling: true }, ['khanacademy.org', 'wikipedia.org']),
    row('carried:dev00wife', "Wife's iPhone", false, { youtube: false, social: false, adult: false, gambling: false }, []),
  ]);
  assert.equal(readFileSync(join(ctx.config, 'account'), 'utf8').trim(), 'acct0001');
  assert.deepEqual(
    s.seen.filter((r) => r.path.endsWith('/queries')).map((r) => r.query),
    ['?limit=100&action=blocked', '?limit=100&action=blocked', '?limit=100&action=blocked'],
  );
});

test('state one-lines and strips controls and bidi marks from server text', async (t) => {
  const s = await stub(t);
  s.devices = FORGED.map((name, i) => ({ ...structuredClone(DEVICES[2]), id: `dev0forged${i}`, name }));
  s.queries = { entries: [{ domain: 'evil\u202E.example\n', action: 'blocked', timestamp: T0 }], next_cursor: null };
  const ctx = scratch(t, s.url);
  const out = await state(ctx);
  assert.deepEqual(
    carried(out).map((d) => d.name),
    ['Fa ke', 'Fakeevil', 'Fake[31m', '', 'x'.repeat(200)],
  );
  assert.deepEqual(carried(out)[0].blocks, [{ domain: 'evil.example', at: T0 }]);
});

test('profiles prints one line per carried device and profile writes its apple-profile to Downloads', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const list = await run(ctx, 'profiles');
  assert.equal(list.status, 0, list.stderr);
  assert.equal(list.stdout, "Saiful's iPhone\tdev00phone\niPad\tdev00ipad\nWife's iPhone\tdev00wife\n");
  const r = await run(ctx, 'profile', 'carried:dev00ipad');
  assert.equal(r.status, 0, r.stderr);
  const path = join(ctx.home, 'Downloads', 'iPad.mobileconfig');
  assert.equal(r.stdout, path + '\n');
  assert.deepEqual(readFileSync(path), PROFILE);
});

test('a valid cookie means no login', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await state(ctx);
  assert.equal(s.seen.filter((r) => r.path === '/api/auth').length, 0);
  assert.ok(s.seen.every((r) => r.cookie === 'ubd_session=GOODSESSION'), JSON.stringify(s.seen.map((r) => r.cookie)));
});

test('a 401 logs in once, retries once and keeps the new cookie in the shared jar', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, { session: 'OLDSESSION' });
  await run(ctx, 'profiles');
  assert.deepEqual(
    s.seen.map((r) => `${r.method} ${r.path} ${r.cookie}`),
    ['GET /api/account/acct0001/devices ubd_session=OLDSESSION', 'POST /api/auth ', 'GET /api/account/acct0001/devices ubd_session=FRESHSESSION'],
  );
  assert.deepEqual(JSON.parse(s.seen[1].body), { token: TOKEN });
  const lines = readFileSync(join(ctx.state, 'session'), 'utf8').split('\n');
  assert.ok(lines.includes('127.0.0.1\tFALSE\t/\tFALSE\t1792873281\tAWSALB\tlbvalue'), lines.join('\n'));
  assert.equal(lines.filter((l) => l.includes('ubd_session')).length, 1);
  assert.match(lines.find((l) => l.includes('ubd_session')), /^#HttpOnly_127\.0\.0\.1\tFALSE\t\/api\tFALSE\t\d+\tubd_session\tFRESHSESSION$/);
});

test('a failed login exits non-zero and names neither the token nor an id', async (t) => {
  const s = await stub(t);
  s.auth = 403;
  const ctx = scratch(t, s.url, { session: 'OLDSESSION' });
  const r = await run(ctx, 'profiles');
  assert.equal(r.status, 1);
  assert.equal(r.stderr, 'dots-dns: login failed (HTTP 403)\n');
  const st = await state(ctx);
  assert.deepEqual(st.carried, { ok: false, error: 'login failed (HTTP 403)' });
  for (const secret of [TOKEN, 'apple', 'acct0001', 'dev00', 'GOODSESSION']) assert.ok(!r.stderr.includes(secret), secret);
});

test('uBlockDNS down still prints state, with carried not ok and an error line', async (t) => {
  const s = await stub(t);
  s.down = true;
  const ctx = scratch(t, s.url);
  const r = await run(ctx, 'state');
  assert.equal(r.status, 0, r.stderr);
  const out = JSON.parse(r.stdout);
  assert.deepEqual(out.carried, { ok: false, error: 'list devices failed (HTTP 503)' });
  assert.deepEqual(carried(out), []);
  assert.equal(r.stderr, 'dots-dns: list devices failed (HTTP 503)\n');
});

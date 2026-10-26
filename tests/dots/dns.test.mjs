// dots-dns against a local stub of the uBlockDNS API, with a scratch HOME and XDG dirs.
import { test } from 'node:test';
import { createHash } from 'node:crypto';
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
const TAILNET_PROFILE = readFileSync(fixture('dns-apple-profile-tailnet.mobileconfig'));
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
  const s = { seen: [], devices: structuredClone(DEVICES), session: 'GOODSESSION', auth: 200, down: false, hold: 0, queries: QUERIES, profile: PROFILE };
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
        if (m[2] === '/apple-profile') return send(200, s.profile, 'application/x-apple-aspen-config');
        if (req.method === 'GET') {
          const read = structuredClone(dev);
          return setTimeout(() => send(200, read), s.hold);
        }
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

// The fake router: ssh runs the collector's script with sh against fake uci, nft, date and dns-shield commands that keep their state in the ctl dir, and its file paths sit under DOTS_DNS_ROUTER_ROOT.
const STUBS = {
  ssh: String.raw`
const fs = require('fs');
const ctl = process.env.STUB_CTL;
fs.appendFileSync(ctl + '/ssh.log', JSON.stringify(process.argv.slice(2)) + '\n');
if (fs.existsSync(ctl + '/ssh-down')) {
  setTimeout(() => {
    process.stderr.write('ssh: connect to host 192.168.0.1 port 22: Connection timed out\n');
    process.exit(255);
  }, 300);
} else {
  const r = require('child_process').spawnSync('/bin/sh', ['-s'], { input: fs.readFileSync(0), stdio: ['pipe', 'inherit', 'inherit'], env: { PATH: ctl + '/router/bin:/usr/bin:/bin', STUB_CTL: ctl, DOTS_DNS_ROUTER_ROOT: ctl + '/router' } });
  process.exit(r.status === null ? 1 : r.status);
}
`,
  'systemd-run': String.raw`
require('fs').appendFileSync(process.env.STUB_CTL + '/systemd.log', JSON.stringify(['systemd-run', ...process.argv.slice(2)]) + '\n');
`,
  systemctl: String.raw`
require('fs').appendFileSync(process.env.STUB_CTL + '/systemd.log', JSON.stringify(['systemctl', ...process.argv.slice(2)]) + '\n');
`,
};
const ROUTER = {
  uci: String.raw`
const fs = require('fs');
const ctl = process.env.STUB_CTL;
const file = ctl + '/router/uci.json';
fs.appendFileSync(ctl + '/router.log', JSON.stringify(['uci', ...process.argv.slice(2)]) + '\n');
const a = process.argv.slice(2).filter((x) => x !== '-q');
const db = JSON.parse(fs.readFileSync(file, 'utf8'));
const q = (v) => "'" + v.replace(/'/g, "'\\''") + "'";
if (a[0] === 'show') {
  const n = {};
  let out = '';
  for (const s of db[a[1]]) {
    n[s['.type']] = (n[s['.type']] ?? -1) + 1;
    const id = a[1] + '.@' + s['.type'] + '[' + n[s['.type']] + ']';
    out += id + '=' + s['.type'] + '\n';
    for (const [k, v] of Object.entries(s)) if (k !== '.type') out += id + '.' + k + '=' + (Array.isArray(v) ? v.map(q).join(' ') : q(v)) + '\n';
  }
  process.stdout.write(out);
  process.exit(0);
}
if (a[0] === 'commit') process.exit(0);
if (a[0] === 'add') {
  db[a[1]].push({ '.type': a[2] });
  fs.writeFileSync(file, JSON.stringify(db));
  console.log('cfg0' + db[a[1]].length);
  process.exit(0);
}
const m = a[1].match(/^(\w+)\.@(\w+)\[(-?\d+)\]\.(\w+)(?:=(.*))?$/s);
const all = m ? db[m[1]].filter((x) => x['.type'] === m[2]) : [];
const s = m && all[Number(m[3]) < 0 ? all.length + Number(m[3]) : Number(m[3])];
if (!s) process.exit(1);
if (a[0] === 'get') {
  if (s[m[4]] === undefined) process.exit(1);
  console.log([].concat(s[m[4]]).join(' '));
} else if (a[0] === 'add_list') s[m[4]] = [].concat(s[m[4]] || [], m[5]);
else if (a[0] === 'del_list') s[m[4]] = [].concat(s[m[4]] || []).filter((x) => x !== m[5]);
else if (a[0] === 'set') s[m[4]] = m[5];
fs.writeFileSync(file, JSON.stringify(db));
`,
  nft: String.raw`
// Like the real nft, deleting an element the set does not hold fails.
const fs = require('fs');
const ctl = process.env.STUB_CTL;
fs.appendFileSync(ctl + '/router.log', JSON.stringify(['nft', ...process.argv.slice(2)]) + '\n');
const [verb, what, , , set, el] = process.argv.slice(2);
if (what !== 'element') process.exit(0);
const file = ctl + '/router/nft.json';
const sets = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
const e = el.replace(/[{} ]/g, '');
const have = sets[set] || [];
if (verb === 'delete' && !have.includes(e)) process.exit(1);
sets[set] = verb === 'add' ? [...new Set([...have, e])] : have.filter((x) => x !== e);
fs.writeFileSync(file, JSON.stringify(sets));
`,
  date: String.raw`
process.stdout.write(require('fs').readFileSync(process.env.STUB_CTL + '/router/now', 'utf8'));
`,
};
const ROUTER_NOW = 1792677600;
// One lease is a listed reservation (the nuc); the forged hostname and the * stand for what any device can send in DHCP.
const LEASES = [
  '1792720263 02:00:00:00:00:01 192.168.0.102 nuc 01:02:00:00:00:00:01',
  '1792720138 02:00:00:00:00:41 192.168.0.143 Galaxy-A54 01:02:00:00:00:00:41',
  '1792710997 02:00:00:00:00:42 192.168.0.151 * 01:02:00:00:00:00:42',
  '1792696551 02:00:00:00:00:43 192.168.0.160 Chrome\u202Ecast *',
].join('\n') + '\n';
const host = (name, mac, ip) => ({ '.type': 'host', name, mac, ip, dns: '1' });
const ipset = (name, match, entry) => ({ '.type': 'ipset', name, family: 'ipv4', match, entry });
const UCI = {
  dhcp: [{ '.type': 'dnsmasq', domainneeded: '1' }, host('nuc', '02:00:00:00:00:01', '192.168.0.102'), host('Kids-Tablet', '02:00:00:00:00:21', '192.168.0.143'), host('macbook', '02:00:00:00:00:02', '192.168.0.105'), host("Living-room 'TV'", '02:00:00:00:00:18', '192.168.0.238'), host('printer', '02:00:00:00:00:1B', '192.168.0.164')],
  firewall: [ipset('dns_exempt', 'src_net', ['192.168.0.105', '192.168.0.102']), ipset('kid', 'src_ip', ['192.168.0.143', '192.168.0.238']), ipset('kid_mac', 'src_mac', ['02:00:00:00:00:21', '02:00:00:00:00:18']), { '.type': 'redirect', ipset: '!dns_exempt' }],
};

function fakeRouter(ctl, uci = UCI) {
  const r = join(ctl, 'router');
  mkdirSync(join(r, 'bin'), { recursive: true });
  mkdirSync(join(r, 'tmp', 'dns-shield'), { recursive: true });
  mkdirSync(join(r, 'etc', 'dns-shield'), { recursive: true });
  mkdirSync(join(r, 'etc', 'init.d'), { recursive: true });
  for (const [name, code] of Object.entries(ROUTER)) writeFileSync(join(r, 'bin', name), `#!${process.execPath}\n${code}`, { mode: 0o755 });
  writeFileSync(join(r, 'etc', 'init.d', 'dns-shield'), `#!${process.execPath}\nrequire('fs').appendFileSync(process.env.STUB_CTL + '/router.log', JSON.stringify(['dns-shield', ...process.argv.slice(2)]) + '\\n');\n`, { mode: 0o755 });
  writeFileSync(join(r, 'etc', 'init.d', 'dnsmasq'), `#!${process.execPath}\nrequire('fs').appendFileSync(process.env.STUB_CTL + '/router.log', JSON.stringify(['dnsmasq', ...process.argv.slice(2)]) + '\\n');\n`, { mode: 0o755 });
  writeFileSync(join(r, 'tmp', 'dhcp.leases'), LEASES);
  writeFileSync(join(r, 'uci.json'), JSON.stringify(uci));
  const live = (name) => (uci.firewall.find((x) => x.name === name) || {}).entry || [];
  writeFileSync(join(r, 'nft.json'), JSON.stringify({ kid: live('kid'), kid_mac: live('kid_mac').map((m) => m.toLowerCase()) }));
  writeFileSync(join(r, 'now'), ROUTER_NOW + '\n');
  writeFileSync(join(r, 'tmp', 'dns-shield', 'kid.log'), readFileSync(fixture('dns-kid.log')));
  writeFileSync(join(r, 'etc', 'dns-shield', 'allow'), 'khanacademy.org\n');
}

const jar = (value) => `# Netscape HTTP Cookie File\n\n#HttpOnly_127.0.0.1\tFALSE\t/api\tFALSE\t1820303639\tubd_session\t${value}\n127.0.0.1\tFALSE\t/\tFALSE\t1792873281\tAWSALB\tlbvalue\n`;

// HOME and every XDG dir in a scratch root; PATH holds only node, flock and the stub ssh.
function scratch(t, url, { session = 'GOODSESSION', account = true, uci } = {}) {
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
  for (const [name, code] of Object.entries(STUBS)) writeFileSync(join(stubBin, name), `#!${process.execPath}\n${code}`, { mode: 0o755 });
  const ctl = join(root, 'ctl');
  fakeRouter(ctl, uci);
  writeFileSync(join(config, 'router.env'), "# router identity\nWIFI_PSK='wifisecret'\nSSH_KEY=$HOME/.ssh/router\n");
  const env = {
    HOME: home,
    XDG_CONFIG_HOME: join(root, 'config'),
    XDG_STATE_HOME: join(root, 'state'),
    XDG_CACHE_HOME: join(root, 'cache'),
    XDG_DATA_HOME: join(root, 'data'),
    XDG_RUNTIME_DIR: join(root, 'run'),
    DOTS_DNS_API: url,
    PATH: stubBin,
    STUB_CTL: ctl,
  };
  return { root, home, config, state, env, stubBin, ctl, cache: join(root, 'cache', 'dots', 'dns') };
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
    row('carried:dev00phone', "Saiful's iPhone", true, { youtube: true, youtube_kids: true, social: true, adult: true, gambling: false }, ['wikipedia.org']),
    row('carried:dev00ipad', 'iPad', true, { youtube: false, youtube_kids: false, social: false, adult: true, gambling: true }, ['scratch.mit.edu', 'wikipedia.org']),
    row('carried:dev00wife', "Wife's iPhone", false, { youtube: false, youtube_kids: false, social: false, adult: false, gambling: false }, []),
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

test('profiles prints one line per carried device and profile writes its apple-profile to Downloads, with ts.net left to the phone', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const list = await run(ctx, 'profiles');
  assert.equal(list.status, 0, list.stderr);
  assert.equal(list.stdout, "Saiful's iPhone\tdev00phone\niPad\tdev00ipad\nWife's iPhone\tdev00wife\n");
  const r = await run(ctx, 'profile', 'carried:dev00ipad');
  assert.equal(r.status, 0, r.stderr);
  const path = join(ctx.home, 'Downloads', 'iPad.mobileconfig');
  assert.equal(r.stdout, path + '\n');
  assert.equal(readFileSync(path, 'utf8'), TAILNET_PROFILE.toString());
});

test('profile refuses an apple-profile with no on-demand rules to add ts.net to, and writes nothing', async (t) => {
  const s = await stub(t);
  s.profile = readFileSync(fixture('dns-apple-profile.mobileconfig'), 'utf8').replace(/\t*<key>OnDemandRules<\/key>[\s\S]*?\n\t{3}<\/array>\n/, '');
  assert.doesNotMatch(s.profile, /OnDemandRules/);
  const ctx = scratch(t, s.url);
  const r = await run(ctx, 'profile', 'carried:dev00ipad');
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /no on-demand rules/);
  assert.equal(existsSync(join(ctx.home, 'Downloads', 'iPad.mobileconfig')), false);
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
  assert.equal(out.router.ok, true);
  assert.deepEqual(routerRows(out).map((d) => d.key), ROUTER_KEYS);
});

const routerRows = (out) => out.devices.filter((d) => d.path === 'router');
const ROUTER_KEYS = ['router:02:00:00:00:00:01', 'router:02:00:00:00:00:21', 'router:02:00:00:00:00:02', 'router:02:00:00:00:00:18', 'router:02:00:00:00:00:1b'];
const ALL = (on) => ({ youtube: on, youtube_kids: on, social: on, adult: on, gambling: on });
const routerRow = (name, mac, ip, kid, blocks = []) => ({ key: 'router:' + mac, name, path: 'router', kid, categories: ALL(kid), open_until: null, allow: kid ? ['khanacademy.org'] : [], last_block: blocks.length ? blocks[0].at : null, blocks, ip, mac });
const ROUTER_ROWS = [
  routerRow('nuc', '02:00:00:00:00:01', '192.168.0.102', false),
  routerRow('Kids-Tablet', '02:00:00:00:00:21', '192.168.0.143', true, [
    { domain: 'tiktok.com', at: 1792676402 },
    { domain: 'youtube.com', at: 1792676266 },
    { domain: 'old.example', at: 1767225540 },
  ]),
  routerRow('macbook', '02:00:00:00:00:02', '192.168.0.105', false),
  routerRow("Living-room 'TV'", '02:00:00:00:00:18', '192.168.0.238', true),
  routerRow('printer', '02:00:00:00:00:1b', '192.168.0.164', false),
];
const sshLog = (ctx) => (existsSync(join(ctx.ctl, 'ssh.log')) ? readFileSync(join(ctx.ctl, 'ssh.log'), 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);

test('the collector finds the stub ssh, never the real one', () => {
  const ctx = scratch({ after() {} }, 'http://127.0.0.1:9/api');
  const r = spawnSync('/bin/sh', ['-c', 'command -v ssh'], { env: ctx.env, encoding: 'utf8' });
  assert.equal(r.stdout.trim(), join(ctx.stubBin, 'ssh'));
  rmSync(ctx.root, { recursive: true, force: true });
});

test('state lists the router reservations after the carried devices, with one ssh', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const out = await state(ctx);
  assert.deepEqual(out.router, { ok: true, as_of: out.as_of, error: null, youtube_kids_allowed: false });
  assert.deepEqual(out.devices.map((d) => d.key), ['carried:dev00phone', 'carried:dev00ipad', 'carried:dev00wife', ...ROUTER_KEYS]);
  assert.deepEqual(routerRows(out), ROUTER_ROWS);
  // The router's host key is kept in the file dots-dns-router uses, since BatchMode cannot ask about an unknown key.
  const known = join(ctx.home, '.local', 'state', 'dns-helper', 'router_known_hosts');
  assert.deepEqual(sshLog(ctx), [['-i', join(ctx.home, '.ssh', 'router'), '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=accept-new', '-o', `UserKnownHostsFile=${known}`, 'root@192.168.0.1', 'sh', '-s']]);
  assert.deepEqual(JSON.parse(readFileSync(join(ctx.cache, 'router.json'), 'utf8')), { as_of: out.as_of, youtube_kids_allowed: false, devices: ROUTER_ROWS });
});

test('router names are one-lined and stripped of controls and bidi marks', async (t) => {
  const s = await stub(t);
  const uci = { dhcp: FORGED.map((name, i) => host(name, `02:00:00:00:00:3${i}`, `192.168.0.3${i}`)), firewall: [] };
  const ctx = scratch(t, s.url, { uci });
  const out = await state(ctx);
  assert.deepEqual(routerRows(out).map((d) => d.name), ['Fa ke', 'Fakeevil', 'Fake[31m', '', 'x'.repeat(200)]);
  assert.deepEqual(routerRows(out).map((d) => d.ip), ['192.168.0.30', '192.168.0.31', '192.168.0.32', '192.168.0.33', '192.168.0.34']);
});

test('an unreachable router serves the last good read with its own as_of', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  mkdirSync(ctx.cache, { recursive: true });
  writeFileSync(join(ctx.cache, 'router.json'), JSON.stringify({ as_of: 1792600000, devices: ROUTER_ROWS.slice(0, 2) }));
  writeFileSync(join(ctx.ctl, 'ssh-down'), '');
  const out = await state(ctx);
  assert.deepEqual(out.router, { ok: false, as_of: 1792600000, error: 'router unreachable (ssh exit 255)', youtube_kids_allowed: false });
  assert.deepEqual(routerRows(out), ROUTER_ROWS.slice(0, 2));
  assert.deepEqual(out.carried, { ok: true, error: null });
  assert.equal(carried(out).length, 3);
  assert.equal(sshLog(ctx).length, 1);
});

test('an unreachable router with nothing cached gives no router rows', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  writeFileSync(join(ctx.ctl, 'ssh-down'), '');
  const out = await state(ctx);
  assert.deepEqual(out.router, { ok: false, as_of: null, error: 'router unreachable (ssh exit 255)', youtube_kids_allowed: false });
  assert.deepEqual(routerRows(out), []);
  assert.equal(carried(out).length, 3);
});

const IPAD = DEVICES[1];
const puts = (s) => s.seen.filter((r) => r.method === 'PUT');
const ipad = (s) => s.devices.find((d) => d.id === 'dev00ipad');
const ok = async (ctx, ...args) => {
  const r = await run(ctx, ...args);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, '');
  return r;
};

test('kid on puts the whole Kid set on the one device and keeps every other rule', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'kid', 'carried:dev00ipad', 'on');
  assert.deepEqual(
    puts(s).map((r) => r.path),
    ['/api/account/acct0001/device/dev00ipad'],
  );
  const body = JSON.parse(puts(s)[0].body);
  assert.deepEqual(Object.keys(body).sort(), ['custom_rules', 'dns_provider', 'lists', 'policy_modules', 'preset_id']);
  assert.deepEqual(body.lists, ['hagezi-pro']);
  assert.equal(body.dns_provider, 'quad9');
  assert.equal(body.preset_id, 'family');
  assert.deepEqual(body.custom_rules, ['||mask.icloud.com^', '@@||scratch.mit.edu^', '||mask-h2.icloud.com^', '||ads.example.net^', '@@||wikipedia.org^', '||youtube.com^', '||youtu.be^', '||youtube-nocookie.com^', '||youtubekids.com^', '||googlevideo.com^', '||ytimg.com^', '||youtubei.googleapis.com^']);
  assert.deepEqual(body.policy_modules, { 'social-apps': true, 'adult-content': true, gambling: true, dating: true });
  assert.deepEqual(s.devices[0], DEVICES[0]);
  assert.deepEqual(s.devices[2], DEVICES[2]);
});

test('kid off remembers the categories it turns off and kid on brings back exactly those', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'kid', 'carried:dev00ipad', 'off');
  assert.deepEqual(JSON.parse(readFileSync(join(ctx.state, 'kid-dev00ipad.json'), 'utf8')), { youtube: false, youtube_kids: false, social: false, adult: true, gambling: true });
  assert.deepEqual(ipad(s).custom_rules, ['||mask.icloud.com^', '@@||scratch.mit.edu^', '||mask-h2.icloud.com^', '||ads.example.net^', '@@||wikipedia.org^']);
  assert.deepEqual(ipad(s).policy_modules, { 'social-apps': false, 'adult-content': false, gambling: false, dating: true });
  await ok(ctx, 'kid', 'carried:dev00ipad', 'on');
  assert.deepEqual(ipad(s).custom_rules, ['||mask.icloud.com^', '@@||scratch.mit.edu^', '||mask-h2.icloud.com^', '||ads.example.net^', '@@||wikipedia.org^']);
  assert.deepEqual(ipad(s).policy_modules, { 'social-apps': false, 'adult-content': true, gambling: true, dating: true });
});

test('category flips one category on one device', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'category', 'carried:dev00ipad', 'gambling', 'off');
  assert.deepEqual(ipad(s), { ...IPAD, policy_modules: { ...IPAD.policy_modules, gambling: false } });
  assert.equal(puts(s).length, 1);
});

test('two category writes started together both land, one after the other', async (t) => {
  const s = await stub(t);
  s.hold = 300;
  const ctx = scratch(t, s.url);
  const first = run(ctx, 'category', 'carried:dev00ipad', 'gambling', 'off');
  await new Promise((r) => setTimeout(r, 100));
  const second = run(ctx, 'category', 'carried:dev00ipad', 'social', 'on');
  for (const r of await Promise.all([first, second])) assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(ipad(s).policy_modules, { 'social-apps': true, 'adult-content': true, gambling: false, dating: true });
});

test('allow adds one exception rule for the normalised domain and unallow takes it out', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'allow', 'carried:dev00ipad', 'https://KhanAcademy.org/x');
  await ok(ctx, 'allow', 'carried:dev00ipad', 'khanacademy.org');
  assert.deepEqual(ipad(s).custom_rules, [...IPAD.custom_rules, '@@||khanacademy.org^']);
  await ok(ctx, 'unallow', 'carried:dev00ipad', 'KHANACADEMY.org');
  assert.deepEqual(ipad(s).custom_rules, IPAD.custom_rules);
  const r = await run(ctx, 'allow', 'carried:dev00ipad', 'not a domain');
  assert.equal(r.status, 2);
});

const routerLog = (ctx) => (existsSync(join(ctx.ctl, 'router.log')) ? readFileSync(join(ctx.ctl, 'router.log'), 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : []);
const kidSets = (ctx) => {
  const fw = JSON.parse(readFileSync(join(ctx.ctl, 'router', 'uci.json'), 'utf8')).firewall;
  return { kid: fw.find((s) => s.name === 'kid').entry, kid_mac: fw.find((s) => s.name === 'kid_mac').entry };
};
const writes = (ctx) => routerLog(ctx).filter((c) => !(c[0] === 'uci' && ['get', 'show', '-q'].includes(c[1])));

test('kid on a router device adds it to both Kid sets, saved and live', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'kid', 'router:02:00:00:00:00:02', 'on');
  assert.deepEqual(kidSets(ctx), { kid: ['192.168.0.143', '192.168.0.238', '192.168.0.105'], kid_mac: ['02:00:00:00:00:21', '02:00:00:00:00:18', '02:00:00:00:00:02'] });
  assert.deepEqual(writes(ctx), [
    ['uci', 'del_list', 'firewall.@ipset[1].entry=192.168.0.105'],
    ['uci', 'add_list', 'firewall.@ipset[1].entry=192.168.0.105'],
    ['uci', 'del_list', 'firewall.@ipset[2].entry=02:00:00:00:00:02'],
    ['uci', 'add_list', 'firewall.@ipset[2].entry=02:00:00:00:00:02'],
    ['uci', 'commit', 'firewall'],
    ['nft', 'add', 'element', 'inet', 'fw4', 'kid', '{ 192.168.0.105 }'],
    ['nft', 'add', 'element', 'inet', 'fw4', 'kid_mac', '{ 02:00:00:00:00:02 }'],
  ]);
  assert.equal(sshLog(ctx).length, 1);
  rmSync(join(ctx.ctl, 'router.log'));
  await ok(ctx, 'kid', 'router:02:00:00:00:00:02', 'off');
  assert.deepEqual(kidSets(ctx), { kid: ['192.168.0.143', '192.168.0.238'], kid_mac: ['02:00:00:00:00:21', '02:00:00:00:00:18'] });
  assert.deepEqual(writes(ctx), [
    ['uci', 'del_list', 'firewall.@ipset[1].entry=192.168.0.105'],
    ['uci', 'del_list', 'firewall.@ipset[2].entry=02:00:00:00:00:02'],
    ['uci', 'commit', 'firewall'],
    ['nft', 'delete', 'element', 'inet', 'fw4', 'kid', '{ 192.168.0.105 }'],
    ['nft', 'delete', 'element', 'inet', 'fw4', 'kid_mac', '{ 02:00:00:00:00:02 }'],
  ]);
});

test('a router device has no categories of its own', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const r = await run(ctx, 'category', 'router:02:00:00:00:00:21', 'youtube', 'off');
  assert.equal(r.status, 2);
  assert.equal(r.stderr, 'dots-dns: router devices carry one Kid policy\n');
  assert.deepEqual(sshLog(ctx), []);
});

test('a router allow goes into the shared allow file and reloads the Kid resolver', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const allowFile = join(ctx.ctl, 'router', 'etc', 'dns-shield', 'allow');
  await ok(ctx, 'allow', 'router:02:00:00:00:00:21', 'https://Wikipedia.org/wiki/Cat');
  await ok(ctx, 'allow', 'router:02:00:00:00:00:21', 'wikipedia.org');
  assert.equal(readFileSync(allowFile, 'utf8'), 'khanacademy.org\nwikipedia.org\n');
  assert.deepEqual(routerLog(ctx), [['dns-shield', 'reload'], ['dns-shield', 'reload']]);
  const out = await state(ctx);
  assert.deepEqual(routerRows(out).map((d) => d.allow), [[], ['khanacademy.org', 'wikipedia.org'], [], ['khanacademy.org', 'wikipedia.org'], []]);
  await ok(ctx, 'unallow', 'router:02:00:00:00:00:21', 'wikipedia.org');
  assert.equal(readFileSync(allowFile, 'utf8'), 'khanacademy.org\n');
});

// A timed open is Kid off with a deadline file and a transient timer; reconcile, run by the timer, by state and at the shell's start, ends it.
const systemd = (ctx) => (existsSync(join(ctx.ctl, 'systemd.log')) ? readFileSync(join(ctx.ctl, 'systemd.log'), 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : []);
const openFile = (ctx, key) => join(ctx.state, 'open-' + key.replace(/[^A-Za-z0-9_-]/g, '_'));
const deadline = (ctx, key) => Number(readFileSync(openFile(ctx, key), 'utf8').split(' ')[0]);
// The unit name reaches the journal, so it carries a hash of the key, never the device id or MAC.
const unitFor = (key) => 'dots-dns-open-' + createHash('sha256').update(key).digest('hex').slice(0, 12);
// A wall-clock time, so the timer counts the hours the laptop slept and fires on resume if they passed.
const calendar = (epoch) => new Date(epoch * 1000).toISOString().replace('T', ' ').replace(/\.\d+Z$/, ' UTC');

test('open turns Kid off, keeps a deadline and starts a timer that reconciles, and state reads the device open with its categories paused', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const t0 = Math.floor(Date.now() / 1000);
  await ok(ctx, 'open', 'carried:dev00ipad', '30m');
  assert.deepEqual(ipad(s).policy_modules, { 'social-apps': false, 'adult-content': false, gambling: false, dating: true });
  const until = deadline(ctx, 'carried:dev00ipad');
  assert.ok(until >= t0 + 1800 && until <= t0 + 1802, String(until));
  assert.equal(readFileSync(openFile(ctx, 'carried:dev00ipad'), 'utf8').trim().split(' ')[1], 'carried:dev00ipad');
  const run1 = systemd(ctx).find((c) => c[0] === 'systemd-run');
  assert.ok(run1.includes('--user') && run1.includes(`--on-calendar=${calendar(until)}`) && run1.includes('--unit') && run1.at(-1) === 'reconcile', JSON.stringify(run1));
  assert.equal(run1[run1.indexOf('--unit') + 1], unitFor('carried:dev00ipad'));
  assert.ok(!JSON.stringify(systemd(ctx)).includes('dev00ipad'), 'no device id in a unit name');
  const row = (await state(ctx)).devices.find((d) => d.key === 'carried:dev00ipad');
  assert.equal(row.open_until, until);
  assert.equal(row.kid, false);
  assert.deepEqual(row.categories, { youtube: false, youtube_kids: false, social: false, adult: true, gambling: true });
});

test('open again restarts the deadline and the timer with the new length', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'open', 'carried:dev00ipad', '30m');
  await ok(ctx, 'open', 'carried:dev00ipad', '2h');
  assert.ok(deadline(ctx, 'carried:dev00ipad') >= Math.floor(Date.now() / 1000) + 7190);
  const log = systemd(ctx);
  assert.ok(log.some((c) => c[0] === 'systemctl' && c.includes('stop') && c.includes(unitFor('carried:dev00ipad') + '.timer')));
  assert.ok(log.filter((c) => c[0] === 'systemd-run').at(-1).includes(`--on-calendar=${calendar(deadline(ctx, 'carried:dev00ipad'))}`));
  assert.deepEqual(JSON.parse(readFileSync(join(ctx.state, 'kid-dev00ipad.json'), 'utf8')), { youtube: false, youtube_kids: false, social: false, adult: true, gambling: true });
});

test('reconcile brings Kid back for a passed deadline and leaves a running one', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'open', 'carried:dev00ipad', '30m');
  await ok(ctx, 'open', 'router:02:00:00:00:00:21', '2h');
  writeFileSync(openFile(ctx, 'carried:dev00ipad'), `${Math.floor(Date.now() / 1000) - 5} carried:dev00ipad\n`);
  await ok(ctx, 'reconcile');
  assert.deepEqual(ipad(s).policy_modules, { 'social-apps': false, 'adult-content': true, gambling: true, dating: true });
  assert.ok(!existsSync(openFile(ctx, 'carried:dev00ipad')));
  assert.ok(existsSync(openFile(ctx, 'router:02:00:00:00:00:21')));
  assert.deepEqual(kidSets(ctx), { kid: ['192.168.0.238'], kid_mac: ['02:00:00:00:00:18'] });
});

test('a router open takes the device out of the Kid sets until reconcile puts it back', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'open', 'router:02:00:00:00:00:21', '30m');
  assert.deepEqual(kidSets(ctx), { kid: ['192.168.0.238'], kid_mac: ['02:00:00:00:00:18'] });
  const row = (await state(ctx)).devices.find((d) => d.key === 'router:02:00:00:00:00:21');
  assert.equal(row.kid, false);
  assert.ok(row.open_until > Date.now() / 1000);
  assert.deepEqual(row.categories, ALL(true));
  writeFileSync(openFile(ctx, 'router:02:00:00:00:00:21'), `${Math.floor(Date.now() / 1000) - 1} router:02:00:00:00:00:21\n`);
  const after = (await state(ctx)).devices.find((d) => d.key === 'router:02:00:00:00:00:21');
  assert.equal(after.kid, true);
  assert.equal(after.open_until, null);
  assert.deepEqual(kidSets(ctx), { kid: ['192.168.0.238', '192.168.0.143'], kid_mac: ['02:00:00:00:00:18', '02:00:00:00:00:21'] });
});

test('kid on ends a timed open at once and stops its timer', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'open', 'carried:dev00ipad', '30m');
  await ok(ctx, 'kid', 'carried:dev00ipad', 'on');
  assert.ok(!existsSync(openFile(ctx, 'carried:dev00ipad')));
  assert.ok(systemd(ctx).filter((c) => c[0] === 'systemctl').length >= 2);
  assert.equal((await state(ctx)).devices.find((d) => d.key === 'carried:dev00ipad').open_until, null);
});

test('a reconcile that cannot reach the router keeps the deadline for the next try and fails', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'open', 'router:02:00:00:00:00:21', '30m');
  writeFileSync(openFile(ctx, 'router:02:00:00:00:00:21'), `${Math.floor(Date.now() / 1000) - 1} router:02:00:00:00:00:21\n`);
  writeFileSync(join(ctx.ctl, 'ssh-down'), '');
  const r = await run(ctx, 'reconcile');
  assert.equal(r.status, 1);
  assert.match(r.stderr, /router unreachable/);
  assert.doesNotMatch(r.stderr, /02:00:00:00:00:21/);
  assert.ok(existsSync(openFile(ctx, 'router:02:00:00:00:00:21')));
  // Nothing else would end it while the router is down, so a failed reconcile tries again in two minutes.
  const retry = systemd(ctx).filter((c) => c[0] === 'systemd-run').at(-1);
  assert.ok(retry.includes('--on-active=120s') && retry[retry.indexOf('--unit') + 1] === 'dots-dns-retry' && retry.at(-1) === 'reconcile', JSON.stringify(retry));
});

// The add list is the router's leases less the listed devices, and an add is a reservation in Kid mode.
test('leases lists the leases of devices not yet listed, with hostnames made safe', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const r = await run(ctx, 'leases');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), [
    { mac: '02:00:00:00:00:41', ip: '192.168.0.143', hostname: 'Galaxy-A54' },
    { mac: '02:00:00:00:00:42', ip: '192.168.0.151', hostname: '' },
    { mac: '02:00:00:00:00:43', ip: '192.168.0.160', hostname: 'Chromecast' },
  ]);
});

test('add reserves the lease address under a DNS-safe host name, keeps the name to show, and puts the device in Kid mode', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'add', '02:00:00:00:00:42', "Sister's phone");
  const host = JSON.parse(readFileSync(join(ctx.ctl, 'router', 'uci.json'), 'utf8')).dhcp.at(-1);
  assert.deepEqual(host, { '.type': 'host', name: 'sister-s-phone', dns_shield_name: "Sister's phone", mac: '02:00:00:00:00:42', ip: '192.168.0.151' });
  const log = routerLog(ctx);
  assert.ok(log.some((c) => c[0] === 'uci' && c[1] === 'commit' && c[2] === 'dhcp'));
  assert.ok(log.some((c) => c[0] === 'dnsmasq' && c[1] === 'reload'));
  assert.ok(kidSets(ctx).kid.includes('192.168.0.151'));
  assert.ok(kidSets(ctx).kid_mac.includes('02:00:00:00:00:42'));
  const row = (await state(ctx)).devices.find((d) => d.key === 'router:02:00:00:00:00:42');
  assert.equal(row.name, "Sister's phone");
  assert.equal(row.kid, true);
});

test('add refuses a MAC with no lease and one already listed, writing nothing', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const none = await run(ctx, 'add', '02:00:00:00:00:99', 'Ghost');
  assert.equal(none.status, 1);
  assert.match(none.stderr, /no lease/);
  const listed = await run(ctx, 'add', '02:00:00:00:00:01', 'nuc again');
  assert.equal(listed.status, 1);
  assert.match(listed.stderr, /already listed/);
  assert.deepEqual(writes(ctx).filter((c) => c[0] !== 'date'), []);
  for (const bad of [['add', 'not-a-mac', 'x'], ['add', '02:00:00:00:00:42', '\n']]) assert.equal((await run(ctx, ...bad)).status, 2, bad.join(' '));
});

// The surface draws the last state at once on a cold open, so `state --cached` answers from disk without the network or the router.
test('state --cached prints the last full state without a request or an ssh', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const empty = await run(ctx, 'state', '--cached');
  assert.equal(empty.status, 0, empty.stderr);
  assert.deepEqual(JSON.parse(empty.stdout).devices, []);
  const full = await state(ctx);
  const seen = s.seen.length;
  const sshCalls = readFileSync(join(ctx.ctl, 'ssh.log'), 'utf8');
  s.down = true;
  writeFileSync(join(ctx.ctl, 'ssh-down'), '');
  const r = await run(ctx, 'state', '--cached');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), full);
  assert.equal(s.seen.length, seen);
  assert.equal(readFileSync(join(ctx.ctl, 'ssh.log'), 'utf8'), sshCalls);
});

// YouTube Kids streams from YouTube's servers, so those are blocked only while both YouTube and YouTube Kids are (ruling VADJ4635).
const OWN = ['||youtube.com^', '||youtu.be^', '||youtube-nocookie.com^'];
const KIDS = ['||youtubekids.com^'];
const SHARED = ['||googlevideo.com^', '||ytimg.com^', '||youtubei.googleapis.com^'];
const others = (rules) => rules.filter((r) => ![...OWN, ...KIDS, ...SHARED].includes(r));

test('YouTube and YouTube Kids block on their own, and the shared servers only with both', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  const before = others(ipad(s).custom_rules);
  await ok(ctx, 'category', 'carried:dev00ipad', 'youtube', 'on');
  assert.deepEqual(ipad(s).custom_rules, [...before, ...OWN]);
  await ok(ctx, 'category', 'carried:dev00ipad', 'youtube_kids', 'on');
  assert.deepEqual(ipad(s).custom_rules, [...before, ...OWN, ...KIDS, ...SHARED]);
  await ok(ctx, 'category', 'carried:dev00ipad', 'youtube', 'off');
  assert.deepEqual(ipad(s).custom_rules, [...before, ...KIDS]);
  const row = (await state(ctx)).devices.find((d) => d.key === 'carried:dev00ipad');
  assert.equal(row.categories.youtube, false);
  assert.equal(row.categories.youtube_kids, true);
});

test('a device with v1 whole YouTube group reads both YouTube and YouTube Kids on', async (t) => {
  const s = await stub(t);
  ipad(s).custom_rules = [...ipad(s).custom_rules.filter((r) => r !== '||youtube.com^'), '||youtube.com^', '||youtu.be^', '||googlevideo.com^', '||ytimg.com^', '||youtubekids.com^', '||youtube-nocookie.com^', '||youtubei.googleapis.com^'];
  const ctx = scratch(t, s.url);
  const row = (await state(ctx)).devices.find((d) => d.key === 'carried:dev00ipad');
  assert.equal(row.categories.youtube, true);
  assert.equal(row.categories.youtube_kids, true);
  const r = await run(ctx, 'category', 'router:02:00:00:00:00:21', 'social', 'off');
  assert.equal(r.status, 2);
});

// On the router YouTube Kids is one shared setting (ruling 58KWPAQA): a flag file for the Kid resolver, and googlevideo.com in or out of the drop set.
const withDropSet = () => ({ ...structuredClone(UCI), dhcp: [...structuredClone(UCI.dhcp), { '.type': 'ipset', name: ['kid_block'], domain: ['facebook.com', 'googlevideo.com'] }] });
const dropDomains = (ctx) => JSON.parse(readFileSync(join(ctx.ctl, 'router', 'uci.json'), 'utf8')).dhcp.find((x) => x['.type'] === 'ipset').domain;

test('YouTube Kids on a router row flips the shared router setting and every Kid router row reads it', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url, { uci: withDropSet() });
  const flag = join(ctx.ctl, 'router', 'etc', 'dns-shield', 'youtube-kids-allowed');
  let rows = (await state(ctx)).devices.filter((d) => d.path === 'router' && d.kid);
  assert.ok(rows.length >= 2 && rows.every((d) => d.categories.youtube_kids === true));
  await ok(ctx, 'category', 'router:02:00:00:00:00:21', 'youtube_kids', 'off');
  assert.ok(existsSync(flag));
  assert.deepEqual(dropDomains(ctx), ['facebook.com']);
  const log = routerLog(ctx);
  for (const c of [['uci', 'commit', 'dhcp'], ['nft', 'flush', 'set', 'inet', 'fw4', 'kid_block'], ['dnsmasq', 'reload'], ['dns-shield', 'reload']]) assert.ok(log.some((l) => JSON.stringify(l) === JSON.stringify(c)), JSON.stringify(c));
  const out = await state(ctx);
  assert.equal(out.router.youtube_kids_allowed, true);
  rows = out.devices.filter((d) => d.path === 'router' && d.kid);
  assert.ok(rows.every((d) => d.categories.youtube_kids === false && d.categories.youtube === true));
  await ok(ctx, 'category', 'router:02:00:00:00:00:18', 'youtube_kids', 'on');
  assert.ok(!existsSync(flag));
  assert.deepEqual(dropDomains(ctx), ['facebook.com', 'googlevideo.com']);
  assert.equal((await state(ctx)).router.youtube_kids_allowed, false);
  assert.equal((await run(ctx, 'category', 'router:02:00:00:00:00:21', 'social', 'off')).status, 2);
});

// A passed deadline that reconcile could not end must not read as a running open, or the card would count down from below zero and re-read every second.
test('a passed deadline that could not be ended reads as no open', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'open', 'router:02:00:00:00:00:21', '30m');
  await state(ctx);
  writeFileSync(openFile(ctx, 'router:02:00:00:00:00:21'), `${Math.floor(Date.now() / 1000) - 1} router:02:00:00:00:00:21\n`);
  s.down = true;
  writeFileSync(join(ctx.ctl, 'ssh-down'), '');
  const row = (await state(ctx)).devices.find((d) => d.key === 'router:02:00:00:00:00:21');
  assert.equal(row.open_until, null);
  assert.ok(existsSync(openFile(ctx, 'router:02:00:00:00:00:21')), 'the deadline stays for the next reconcile');
});

test('kid off on a router device that is not in the Kid sets succeeds and changes nothing', async (t) => {
  const s = await stub(t);
  const ctx = scratch(t, s.url);
  await ok(ctx, 'kid', 'router:02:00:00:00:00:02', 'off');
  assert.deepEqual(kidSets(ctx), { kid: ['192.168.0.143', '192.168.0.238'], kid_mac: ['02:00:00:00:00:21', '02:00:00:00:00:18'] });
  await ok(ctx, 'open', 'router:02:00:00:00:00:02', '30m');
});

// dufs: the unit's sandbox and flags, run for real in a transient user unit against a scratch home, and the static parts of the unit and mise config.
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { request } from 'node:http';
import { createServer, connect } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { dufsConfig } from '../dots/secrets-lib.mjs';

const repo = new URL('../../', import.meta.url).pathname;
const units = join(repo, 'home/dot_config/systemd/user');
const unit = readFileSync(join(units, 'dufs.service'), 'utf8');
const PASSWORD = 'dufs-test-password';
const name = `dufs-test-${process.pid}`;

// Every Key=value line of the unit, in order.
const lines = (key) => [...unit.matchAll(new RegExp(`^${key}=(.*)$`, 'gm'))].map((m) => m[1]);

const sh = (cmd, args, input) => {
  const r = spawnSync(cmd, args, { encoding: 'utf8', input });
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(' ')} exited ${r.status}: ${r.stdout}${r.stderr}${r.error ?? ''}`);
  return r.stdout;
};

// The pinned dufs from mise's github backend; a missing install fails the test rather than skipping it.
const dufsBin = () => join(sh('mise', ['where', 'github:sigoden/dufs@0.47.0']).trim(), 'dufs');

const freePort = () =>
  new Promise((done) => {
    const s = createServer().listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => done(port));
    });
  });

const listening = (port) =>
  new Promise((done) => {
    const c = connect(port, '127.0.0.1', () => (c.end(), done(true)));
    c.on('error', () => done(false));
  });

let home;
let run;
let port;

before(async () => {
  home = realpathSync(mkdtempSync(join(tmpdir(), 'dufs-home-')));
  for (const d of ['Codes', 'Documents', 'Downloads', 'Pictures', 'Music', '.ssh', '.config/dufs']) mkdirSync(join(home, d), { recursive: true });
  writeFileSync(join(home, 'Codes/a.txt'), 'a\n');
  writeFileSync(join(home, 'Codes/.env'), 'SECRET=1\n');
  writeFileSync(join(home, '.ssh/config'), 'Host nuc\n');
  writeFileSync(join(home, 'top.txt'), 'top\n');
  symlinkSync('../.ssh', join(home, 'Codes/out'));
  symlinkSync(join(home, '.ssh'), join(home, 'Codes/abs'));
  // No Downloads/inbox: the unit makes it before binding it.
  const hash = sh('openssl', ['passwd', '-6', '-stdin'], PASSWORD + '\n').trim();
  writeFileSync(join(home, '.config/dufs/config.yaml'), dufsConfig(hash), { mode: 0o600 });

  run = mkdtempSync(join(`/run/user/${process.getuid()}`, 'dufs-test-'));
  port = await freePort();
  const fill = (v) => v.replaceAll('%h', home).replaceAll('%t', run);
  const props = ['TemporaryFileSystem', 'BindReadOnlyPaths', 'BindPaths', 'ExecStartPre'].flatMap((k) => lines(k).map((v) => ['-p', `${k}=${fill(v)}`]));
  const argv = fill(lines('ExecStart')[0]).split(/\s+/);
  assert.equal(argv[0], `${home}/.local/share/mise/shims/dufs`);
  argv[0] = dufsBin();
  argv[argv.indexOf('--port') + 1] = String(port);
  sh('systemd-run', ['--user', '--unit', name, ...props.flat(), '--', ...argv]);
  for (let i = 0; i < 100 && !(await listening(port)); i++) await new Promise((r) => setTimeout(r, 50));
  if (!(await listening(port))) throw new Error(`dufs never listened: ${spawnSync('systemctl', ['--user', 'status', name], { encoding: 'utf8' }).stdout}`);
});

after(() => {
  spawnSync('systemctl', ['--user', 'stop', name]);
  spawnSync('systemctl', ['--user', 'reset-failed', name]);
  if (run) rmSync(run, { recursive: true, force: true });
  if (home) rmSync(home, { recursive: true, force: true });
});

// One request with the path sent as-is, so .. and %2e%2e reach dufs unnormalized.
const req = (method, path, { auth = true, body } = {}) =>
  new Promise((done, reject) => {
    const r = request({ host: '127.0.0.1', port, method, path, auth: auth ? `saiful:${PASSWORD}` : undefined }, (res) => {
      let text = '';
      res.on('data', (d) => (text += d));
      res.on('end', () => done({ status: res.statusCode, text }));
    });
    r.on('error', reject);
    r.end(body);
  });

const names = async (path) => JSON.parse((await req('GET', path + '?json')).text).paths.map((p) => p.name).sort();

test('the root lists the four folders and nothing else', async () => {
  assert.equal((await req('GET', '/')).status, 200);
  assert.deepEqual(await names('/'), ['Codes', 'Documents', 'Downloads', 'Pictures']);
});

test('a served folder lists its files and no dot entry', async () => {
  assert.equal((await req('GET', '/Codes/')).status, 200);
  assert.deepEqual((await names('/Codes/')).filter((n) => n === 'a.txt' || n.startsWith('.')), ['a.txt']);
});

for (const path of ['/.ssh/config', '/top.txt', '/Music/', '/Codes/out/config', '/Codes/abs/config']) {
  test(`${path} is closed`, async () => {
    assert.ok([403, 404].includes((await req('GET', path)).status));
  });
}

for (const path of ['/Codes/../.ssh/config', '/Codes/%2e%2e/.ssh/config']) {
  test(`${path} sent raw is refused`, async () => {
    assert.ok([400, 403, 404].includes((await req('GET', path)).status));
  });
}

test('uploads land in the inbox only, and nothing deletes', async () => {
  assert.equal((await req('PUT', '/Downloads/inbox/a.txt', { body: 'up\n' })).status, 201);
  assert.equal(readFileSync(join(home, 'Downloads/inbox/a.txt'), 'utf8'), 'up\n');
  assert.equal((await req('PUT', '/Documents/a.txt', { body: 'up\n' })).status, 403);
  assert.equal(existsSync(join(home, 'Documents/a.txt')), false);
  assert.equal((await req('DELETE', '/Downloads/inbox/a.txt')).status, 403);
  assert.equal(existsSync(join(home, 'Downloads/inbox/a.txt')), true);
});

test('without the password every path answers 401', async () => {
  assert.equal((await req('GET', '/', { auth: false })).status, 401);
  assert.equal((await req('GET', '/Codes/', { auth: false })).status, 401);
});

test('a folder does not download as an archive', async () => {
  assert.ok([403, 404].includes((await req('GET', '/Codes/?zip')).status));
});

test('the unit runs mise shim dufs on 127.0.0.1 only, once the config exists', () => {
  assert.match(lines('ExecStart')[0], /^%h\/\.local\/share\/mise\/shims\/dufs --config %h\/\.config\/dufs\/config\.yaml .*--bind 127\.0\.0\.1 --port 5000 /);
  assert.doesNotMatch(unit, /0\.0\.0\.0/);
  assert.deepEqual(lines('ConditionPathExists'), ['%h/.config/dufs/config.yaml']);
  assert.deepEqual(lines('ExecStartPost'), ['-/usr/bin/timeout 30 /usr/bin/tailscale serve --bg --yes --https=8443 http://127.0.0.1:5000']);
  // A stopped dufs takes its tailnet mapping with it, so :8443 never forwards to another server on port 5000.
  assert.deepEqual(lines('ExecStopPost'), ['-/usr/bin/timeout 30 /usr/bin/tailscale serve --https=8443 off']);
  assert.deepEqual(lines('WantedBy'), ['default.target']);
  assert.equal(readFileSync(join(units, 'default.target.wants/symlink_dufs.service'), 'utf8').trim(), '../dufs.service');
});

test('mise pins dufs 0.47.0 from its github backend', () => {
  assert.match(readFileSync(join(repo, 'home/dot_config/mise/config.toml'), 'utf8'), /^"github:sigoden\/dufs" = "0\.47\.0"$/m);
  // A manager still holding v1's dufs.service, which served all of $HOME on 0.0.0.0, reloads before the restart.
  assert.match(readFileSync(join(repo, 'bin/dots-secrets'), 'utf8'), /systemctl --user daemon-reload 2>\/dev\/null && systemctl --user restart dufs\.service/);
});

test('the repo holds no sha-512 crypt hash', () => {
  const r = spawnSync('git', ['-C', repo, 'grep', '-nE', String.raw`\$6\$[./A-Za-z0-9]{1,16}\$[./A-Za-z0-9]{40,}`], { encoding: 'utf8' });
  assert.equal(r.stdout, '');
});

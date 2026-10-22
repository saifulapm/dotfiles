// dots-portal on a private bus, driven with gdbus as xdg-desktop-portal drives it, with the shell's picker socket played by a node server.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { execFile, execFileSync, spawn } from 'node:child_process';
import { createServer } from 'node:net';

const bin = new URL('../../bin/dots-portal', import.meta.url).pathname;
const fakeGtk = new URL('./fixtures/fake-gtk-portal', import.meta.url).pathname;
const DEST = 'org.freedesktop.impl.portal.desktop.dots';
const PATH_ = '/org/freedesktop/portal/desktop';
const IFACE = 'org.freedesktop.impl.portal.FileChooser';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The real niri answers focused-window with the window's JSON; a niri that cannot reach its compositor exits 1.
const NIRI = `#!/bin/sh
[ "$*" = "msg -j focused-window" ] || exit 2
echo '{"id":7,"title":"New Tab","app_id":"chromium-browser"}'
`;
const NIRI_DOWN = `#!/bin/sh
echo 'Error: error connecting to the niri socket' >&2
exit 1
`;

// A private bus, the portal on it and a stub niri; every process started here is killed by PID after the test.
async function scratch(t, { niri = NIRI, idle = '30', gtk = false, gtkDelay = 0 } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'dots-portal-'));
  const stubs = join(root, 'stubs');
  mkdirSync(stubs);
  mkdirSync(join(root, 'run'));
  writeFileSync(join(stubs, 'niri'), niri);
  chmodSync(join(stubs, 'niri'), 0o755);
  const procs = [];
  t.after(() => {
    for (const p of procs) if (p.exitCode === null && p.signalCode === null) p.kill();
    rmSync(root, { recursive: true, force: true });
  });
  const bus = spawn('dbus-daemon', ['--session', '--nofork', '--print-address=1', `--address=unix:path=${join(root, 'bus')}`], { stdio: ['ignore', 'pipe', 'inherit'] });
  procs.push(bus);
  const address = await new Promise((resolve) => {
    let buf = '';
    bus.stdout.on('data', (d) => {
      buf += d;
      if (buf.includes('\n')) resolve(buf.split('\n')[0]);
    });
  });
  const env = {
    ...process.env,
    DBUS_SESSION_BUS_ADDRESS: address,
    XDG_RUNTIME_DIR: join(root, 'run'),
    WAYLAND_DISPLAY: 'wayland-test',
    PATH: stubs + delimiter + process.env.PATH,
    DOTS_PORTAL_IDLE_S: idle,
    FAKE_GTK_REC: join(root, 'gtk.rec'),
    FAKE_GTK_DELAY_MS: String(gtkDelay),
  };
  const gdbus = (...args) =>
    new Promise((resolve) => execFile('gdbus', ['call', '--session', '--timeout', '20', ...args], { env }, (err, stdout, stderr) => resolve({ code: err ? err.code : 0, stdout, stderr })));
  const owned = async (name) => {
    for (let i = 0; i < 100; i++) {
      const r = await gdbus('--dest', 'org.freedesktop.DBus', '--object-path', '/org/freedesktop/DBus', '--method', 'org.freedesktop.DBus.NameHasOwner', name);
      if (r.stdout.trim() === '(true,)') return;
      await sleep(50);
    }
    throw new Error(`${name} never appeared`);
  };
  if (gtk) {
    procs.push(spawn(fakeGtk, [], { env, stdio: 'inherit' }));
    await owned('org.freedesktop.impl.portal.desktop.gtk');
  }
  const portal = spawn(bin, [], { env, stdio: ['ignore', 'inherit', 'inherit'] });
  procs.push(portal);
  await owned(DEST);
  const call = (method, handle, app, parent, title, options) =>
    gdbus('--dest', DEST, '--object-path', PATH_, '--method', `${IFACE}.${method}`, handle, app, parent, title, options);
  const close = (handle) => gdbus('--dest', DEST, '--object-path', handle, '--method', 'org.freedesktop.impl.portal.Request.Close');
  const gtkCalls = () => (existsSync(env.FAKE_GTK_REC) ? readFileSync(env.FAKE_GTK_REC, 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : []);
  return { root, env, portal, gdbus, call, close, gtkCalls, sock: join(root, 'run', 'dots-picker-wayland-test.sock') };
}

// The shell's side: each request line goes to answer(), whose line goes back before the close; null holds the connection unanswered.
async function shell(t, sock, answer = () => null) {
  const requests = [];
  const conns = [];
  const closed = [];
  const server = createServer((s) => {
    const conn = { s, closed: false };
    conns.push(conn);
    let buf = '';
    s.on('data', (d) => {
      buf += d;
      const i = buf.indexOf('\n');
      if (i < 0) return;
      requests.push(JSON.parse(buf.slice(0, i)));
      const reply = answer(requests.at(-1), requests.length);
      if (reply !== null) s.end(reply === '' ? '' : JSON.stringify(reply) + '\n');
    });
    s.on('error', () => {});
    s.on('close', () => {
      conn.closed = true;
      closed.push(conn);
    });
  });
  await new Promise((r) => server.listen(sock, r));
  const until = async (cond) => {
    for (let i = 0; i < 200 && !cond(); i++) await sleep(25);
  };
  const stop = () => new Promise((r) => { conns.forEach((c) => c.s.destroy()); server.close(() => r()); });
  // A failed assertion skips the test's own stop, and a listening server would keep node running.
  t.after(stop);
  return { requests, conns, closed, until, stop };
}

const H = '/org/freedesktop/portal/desktop/request/1_9/t';
// A NUL-terminated ay written out byte by byte: gdbus call sends garbage for a b'...' literal inside a variant.
const ay = (text) => `@ay [${[...Buffer.from(text + '\0')].map((b) => '0x' + b.toString(16)).join(', ')}]`;
const CHROMIUM = `{'modal': <true>, 'current_folder': <${ay('/home/saiful')}>}`;
const NONE = '(uint32 1, @a{sv} {})\n';
const OTHER = '(uint32 2, @a{sv} {})\n';

test('OpenFile from unsandboxed Chromium asks the shell to open, naming the focused window\'s app and the current folder', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock, () => ({ response: 1, paths: [] }));
  await p.call('OpenFile', H, '', 'wayland:abc', 'Open File', CHROMIUM);
  await p.call('OpenFile', H + '2', 'org.gimp.GIMP', '', 'Open Image', '{}');
  await sh.stop();
  assert.deepEqual(sh.requests, [
    { mode: 'open', multiple: false, title: 'Open File', app: 'chromium-browser', folder: '/home/saiful', name: '', filters: [], filter: 0, accept: '' },
    { mode: 'open', multiple: false, title: 'Open Image', app: 'org.gimp.GIMP', folder: '', name: '', filters: [], filter: 0, accept: '' },
  ]);
});

test('with niri unreachable the request names no app', async (t) => {
  const p = await scratch(t, { niri: NIRI_DOWN });
  const sh = await shell(t, p.sock, () => ({ response: 1, paths: [] }));
  await p.call('OpenFile', H, '', 'wayland:abc', 'Open File', CHROMIUM);
  await sh.stop();
  assert.equal(sh.requests[0].app, '');
});

test('a chosen path comes back as an encoded file URI', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock, () => ({ response: 0, paths: ['/tmp/x/a b #1 %41 ü.txt'] }));
  const r = await p.call('OpenFile', H, '', 'wayland:abc', 'Open File', CHROMIUM);
  await sh.stop();
  assert.equal(r.stdout, "(uint32 0, {'uris': <['file:///tmp/x/a%20b%20%231%20%2541%20%C3%BC.txt']>})\n", r.stderr);
});

test('Esc in the picker cancels with no uris', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock, () => ({ response: 1, paths: [] }));
  const r = await p.call('OpenFile', H, '', 'wayland:abc', 'Open File', CHROMIUM);
  await sh.stop();
  assert.equal(r.stdout, NONE, r.stderr);
});

test('Request.Close hangs up on the shell and cancels the call', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock);
  const pending = p.call('OpenFile', H, '', 'wayland:abc', 'Open File', CHROMIUM);
  await sh.until(() => sh.requests.length === 1);
  const c = await p.close(H);
  assert.equal(c.code, 0, c.stderr);
  await sh.until(() => sh.closed.length === 1);
  const r = await pending;
  await sh.stop();
  assert.equal(sh.closed.length, 1, 'the shell saw its connection end');
  assert.equal(r.stdout, NONE, r.stderr);
});

test('a shell that closes without an answer line fails the call with response 2', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock, () => '');
  const r = await p.call('OpenFile', H, '', 'wayland:abc', 'Open File', CHROMIUM);
  await sh.stop();
  assert.equal(r.stdout, OTHER, r.stderr);
});

test('with no shell socket the same call goes to gtk and gtk\'s answer comes back', async (t) => {
  const p = await scratch(t, { gtk: true });
  const r = await p.call('OpenFile', H, '', 'wayland:abc', 'Open File', CHROMIUM);
  assert.equal(r.stdout, "(uint32 0, {'uris': <['file:///gtk/picked.txt']>})\n", r.stderr);
  assert.deepEqual(p.gtkCalls(), [['OpenFile', H, '', 'wayland:abc', 'Open File', "{'modal': <true>, 'current_folder': <b'/home/saiful'>}"]]);
});

test('a socket a killed shell left behind sends the call to gtk too', async (t) => {
  const p = await scratch(t, { gtk: true });
  // A bound socket nobody listens on, as a SIGKILLed shell leaves it.
  execFileSync('python3', ['-c', `import socket; socket.socket(socket.AF_UNIX).bind(${JSON.stringify(p.sock)})`]);
  const r = await p.call('OpenFile', H, '', 'wayland:abc', 'Open File', CHROMIUM);
  assert.equal(r.stdout, "(uint32 0, {'uris': <['file:///gtk/picked.txt']>})\n", r.stderr);
  assert.equal(p.gtkCalls().length, 1);
});

test('SaveFile asks for a save with the suggested name and folder', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock, (_, n) => (n === 1 ? { response: 0, paths: ['/tmp/x/report.pdf'] } : { response: 1, paths: [] }));
  const r = await p.call('SaveFile', H, 'org.gnome.Evince', '', 'Save As', `{'current_name': <'report.pdf'>, 'current_folder': <${ay('/tmp/x')}>}`);
  await p.call('SaveFile', H + '2', 'org.gnome.Evince', '', 'Save As', `{'current_file': <${ay('/tmp/y/old.txt')}>}`);
  await sh.stop();
  assert.equal(r.stdout, "(uint32 0, {'uris': <['file:///tmp/x/report.pdf']>})\n", r.stderr);
  assert.deepEqual(sh.requests.map((q) => [q.mode, q.folder, q.name]), [['save', '/tmp/x', 'report.pdf'], ['save', '/tmp/y', 'old.txt']]);
});

test('SaveFiles asks for a folder and joins each of the app\'s names onto it', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock, () => ({ response: 0, paths: ['/tmp/z'] }));
  const r = await p.call('SaveFiles', H, 'org.gnome.Evince', '', 'Save Files', `{'files': <[${ay('a.txt')}, ${ay('b.txt')}]>}`);
  await sh.stop();
  assert.equal(sh.requests[0].mode, 'folder');
  assert.equal(r.stdout, "(uint32 0, {'uris': <['file:///tmp/z/a.txt', 'file:///tmp/z/b.txt']>})\n", r.stderr);
});

test('OpenFile for several folders carries multiple, the folder mode, the filters and the current filter', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock, () => ({ response: 1, paths: [] }));
  const filters = "[('Images', [(uint32 0, '*.png'), (uint32 1, 'image/jpeg')]), ('Text', [(uint32 0, '*.txt')])]";
  await p.call('OpenFile', H, 'a.b', '', 'Pick', `{'multiple': <true>, 'directory': <true>, 'filters': <${filters}>, 'current_filter': <('Text', [(uint32 0, '*.txt')])>, 'accept_label': <'_Use'>}`);
  await sh.stop();
  assert.deepEqual(sh.requests[0], {
    mode: 'folder',
    multiple: true,
    title: 'Pick',
    app: 'a.b',
    folder: '',
    name: '',
    filters: [{ name: 'Images', globs: ['*.png'], mimes: ['image/jpeg'] }, { name: 'Text', globs: ['*.txt'], mimes: [] }],
    filter: 1,
    accept: '_Use',
  });
});

test('two calls at once each get a connection and each its own answer', async (t) => {
  const p = await scratch(t);
  const sh = await shell(t, p.sock);
  const first = p.call('OpenFile', H, 'one', '', 'One', '{}');
  await sh.until(() => sh.requests.length === 1);
  const second = p.call('OpenFile', H + '2', 'two', '', 'Two', '{}');
  await sh.until(() => sh.requests.length === 2);
  sh.conns[1].s.end(JSON.stringify({ response: 0, paths: ['/tmp/two'] }) + '\n');
  const r2 = await second;
  sh.conns[0].s.end(JSON.stringify({ response: 0, paths: ['/tmp/one'] }) + '\n');
  const r1 = await first;
  await sh.stop();
  assert.equal(sh.conns.length, 2);
  assert.equal(r2.stdout, "(uint32 0, {'uris': <['file:///tmp/two']>})\n");
  assert.equal(r1.stdout, "(uint32 0, {'uris': <['file:///tmp/one']>})\n");
});

const exited = (proc, ms) => new Promise((r) => {
  if (proc.exitCode !== null) return r(true);
  const timer = setTimeout(() => r(false), ms);
  proc.once('exit', () => { clearTimeout(timer); r(true); });
});

test('with nothing pending the portal exits once idle', async (t) => {
  const p = await scratch(t, { idle: '1' });
  assert.equal(await exited(p.portal, 3000), true);
});

test('a call waiting on the shell holds the portal past the idle time', async (t) => {
  const p = await scratch(t, { idle: '1' });
  const sh = await shell(t, p.sock);
  const pending = p.call('OpenFile', H, 'a.b', '', 'T', '{}');
  await sh.until(() => sh.requests.length === 1);
  assert.equal(await exited(p.portal, 2500), false);
  sh.conns[0].s.end(JSON.stringify({ response: 1, paths: [] }) + '\n');
  assert.equal((await pending).stdout, NONE);
  await sh.stop();
  assert.equal(await exited(p.portal, 3000), true);
});

test('a call handed to gtk holds the portal past the idle time', async (t) => {
  const p = await scratch(t, { idle: '1', gtk: true, gtkDelay: 2500 });
  const r = await p.call('OpenFile', H, 'a.b', '', 'T', '{}');
  assert.equal(r.stdout, "(uint32 0, {'uris': <['file:///gtk/picked.txt']>})\n", r.stderr);
});

test('the FileChooser version property is 4, the version xdg-desktop-portal serves', async (t) => {
  const p = await scratch(t);
  const r = await p.gdbus('--dest', DEST, '--object-path', PATH_, '--method', 'org.freedesktop.DBus.Properties.Get', IFACE, 'version');
  assert.equal(r.stdout, '(<uint32 4>,)\n', r.stderr);
});

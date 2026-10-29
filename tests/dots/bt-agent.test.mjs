// dots-bt-agent against bin/dev-fake-bluez on a private bus, with the shell's pairing socket played by a node server.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { createServer } from 'node:net';

const agentBin = new URL('../../bin/dots-bt-agent', import.meta.url).pathname;
const fakeBin = new URL('../../bin/dev-fake-bluez', import.meta.url).pathname;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const HCI0 = '/org/bluez/hci0';
const dev = (n) => `${HCI0}/dev_00_00_00_00_00_0${n}`;
const KEYBOARD = dev(5);
const PHONE = dev(6);
const NAMELESS = dev(7);

// A private bus standing in for the system bus, the fake BlueZ and the agent on it; every process started here is killed after the test.
async function scratch(t, { timeout = '60', agentFirst = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'dots-bt-agent-'));
  mkdirSync(join(root, 'run'));
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
    DBUS_SYSTEM_BUS_ADDRESS: address,
    XDG_RUNTIME_DIR: join(root, 'run'),
    WAYLAND_DISPLAY: 'wayland-test',
    DOTS_BT_AGENT_TIMEOUT_S: timeout,
  };
  const gdbus = (path, method, ...args) =>
    new Promise((resolve) =>
      execFile('gdbus', ['call', '--session', '--timeout', '20', '--dest', 'org.bluez', '--object-path', path, '--method', method, ...args], { env }, (err, stdout, stderr) =>
        resolve({ code: err ? err.code : 0, stdout: stdout.trim(), stderr }),
      ),
    );
  const until = async (cond) => {
    for (let i = 0; i < 100 && !(await cond()); i++) await sleep(50);
  };
  const knob = (method, ...args) => gdbus('/org/bluez', `org.dots.FakeBluez.${method}`, ...args);
  const calls = async () => (await knob('Calls')).stdout;
  const startAgent = () => procs.push(spawn(agentBin, [], { env, stdio: ['ignore', 'inherit', 'inherit'] }));
  const startFake = async () => {
    procs.push(spawn(fakeBin, [], { env, stdio: 'inherit' }));
    await until(async () => (await gdbus('/', 'org.freedesktop.DBus.ObjectManager.GetManagedObjects')).code === 0);
  };
  if (agentFirst) {
    startAgent();
    await sleep(300);
    await startFake();
  } else {
    await startFake();
    startAgent();
  }
  await until(async () => (await calls()).includes('RequestDefaultAgent'));
  const prop = async (path, name) => (await gdbus(path, 'org.freedesktop.DBus.Properties.Get', 'org.bluez.Device1', name)).stdout;
  await gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  return { gdbus, knob, calls, prop, sock: join(root, 'run', 'dots-bt-wayland-test.sock') };
}

// The shell's side: each request line goes to answer(), whose line goes back; null holds the connection open, '' hangs up.
async function shell(t, sock, answer = () => null) {
  const requests = [];
  const conns = [];
  const server = createServer((s) => {
    const conn = { s, closed: false };
    conns.push(conn);
    let buf = '';
    s.on('data', (d) => {
      buf += d;
      const i = buf.indexOf('\n');
      if (i < 0) return;
      requests.push(JSON.parse(buf.slice(0, i)));
      const reply = answer(requests.at(-1));
      if (reply === '') s.end();
      else if (reply !== null) s.write(JSON.stringify(reply) + '\n');
    });
    s.on('error', () => {});
    s.on('close', () => {
      conn.closed = true;
    });
  });
  await new Promise((r) => server.listen(sock, r));
  const until = async (cond) => {
    for (let i = 0; i < 200 && !cond(); i++) await sleep(25);
  };
  // A failed assertion skips the test's own end, and a listening server would keep node running.
  t.after(() => new Promise((r) => { conns.forEach((c) => c.s.destroy()); server.close(() => r()); }));
  return { requests, conns, until };
}

const pair = (b, path) => b.gdbus(path, 'org.bluez.Device1.Pair');

test('the agent registers as the default KeyboardDisplay agent', async (t) => {
  const b = await scratch(t);
  assert.equal(await b.calls(), "(['RegisterAgent /org/dots/btagent KeyboardDisplay', 'RequestDefaultAgent /org/dots/btagent'],)");
});

test('an agent started before BlueZ registers once BlueZ appears', async (t) => {
  const b = await scratch(t, { agentFirst: true });
  assert.equal(await b.calls(), "(['RegisterAgent /org/dots/btagent KeyboardDisplay', 'RequestDefaultAgent /org/dots/btagent'],)");
});

test('a code to confirm reaches the shell, and its yes pairs the device', async (t) => {
  const b = await scratch(t);
  const s = await shell(t, b.sock, () => ({ ok: true }));
  assert.equal((await pair(b, KEYBOARD)).code, 0);
  assert.deepEqual(s.requests, [{ kind: 'confirm', device: 'Test Keyboard', address: '00:00:00:00:00:05', code: '123456', service: '' }]);
  assert.equal(await b.prop(KEYBOARD, 'Paired'), '(<true>,)');
});

test('a no or a hang-up from the shell leaves the device unpaired', async (t) => {
  const b = await scratch(t);
  let reply = { ok: false };
  const s = await shell(t, b.sock, () => reply);
  assert.match((await pair(b, KEYBOARD)).stderr, /org\.bluez\.Error\.AuthenticationRejected/);
  assert.equal(await b.prop(KEYBOARD, 'Paired'), '(<false>,)');
  reply = '';
  assert.match((await pair(b, KEYBOARD)).stderr, /org\.bluez\.Error\.AuthenticationRejected/);
  assert.equal(s.requests.length, 2);
  assert.equal(await b.prop(KEYBOARD, 'Paired'), '(<false>,)');
});

test('a passkey shown on the device stays with the shell until it is typed there', async (t) => {
  const b = await scratch(t);
  const s = await shell(t, b.sock);
  await b.knob('SetPairing', KEYBOARD, 'display', '654321');
  const pairing = pair(b, KEYBOARD);
  await s.until(() => s.requests.length === 1);
  assert.deepEqual(s.requests, [{ kind: 'display', device: 'Test Keyboard', address: '00:00:00:00:00:05', code: '654321', service: '' }]);
  await sleep(200);
  assert.equal(s.conns[0].closed, false);
  await b.knob('Typed', KEYBOARD);
  assert.equal((await pairing).code, 0);
  assert.equal(await b.prop(KEYBOARD, 'Paired'), '(<true>,)');
  await s.until(() => s.conns[0].closed);
  assert.equal(s.conns[0].closed, true);
});

test('a no on a shown passkey cancels the pairing', async (t) => {
  const b = await scratch(t);
  const s = await shell(t, b.sock, () => ({ ok: false }));
  await b.knob('SetPairing', KEYBOARD, 'display', '654321');
  assert.match((await pair(b, KEYBOARD)).stderr, /org\.bluez\.Error\.AuthenticationCanceled/);
  assert.equal(s.requests[0].code, '654321');
  assert.equal(await b.prop(KEYBOARD, 'Paired'), '(<false>,)');
});

test('a PIN or passkey typed in the shell goes to BlueZ', async (t) => {
  const b = await scratch(t);
  const s = await shell(t, b.sock, (r) => ({ ok: true, pin: r.kind === 'pin' ? '0000' : '1234' }));
  await b.knob('SetPairing', KEYBOARD, 'pin', '0');
  assert.equal((await pair(b, KEYBOARD)).code, 0);
  await b.knob('SetPairing', PHONE, 'passkey', '0');
  assert.equal((await pair(b, PHONE)).code, 0);
  assert.deepEqual(s.requests.map((r) => [r.kind, r.device, r.code]), [['pin', 'Test Keyboard', ''], ['passkey', 'Test Phone', '']]);
  const calls = await b.calls();
  assert.match(calls, new RegExp(`'RequestPinCode ${KEYBOARD} 0000'`));
  assert.match(calls, new RegExp(`'RequestPasskey ${PHONE} 1234'`));
});

test('a service an untrusted device asks for is allowed or refused by the shell', async (t) => {
  const b = await scratch(t);
  const A2DP = '0000110d-0000-1000-8000-00805f9b34fb';
  let reply = { ok: true };
  const s = await shell(t, b.sock, () => reply);
  assert.equal((await b.knob('Authorize', PHONE, A2DP)).stdout, "('allowed',)");
  assert.deepEqual(s.requests, [{ kind: 'authorize', device: 'Test Phone', address: '00:00:00:00:00:06', code: '', service: A2DP }]);
  reply = { ok: false };
  assert.equal((await b.knob('Authorize', PHONE, A2DP)).stdout, "('org.bluez.Error.Rejected',)");
});

test('a request the shell never answers is rejected after the timeout and its connection closed', async (t) => {
  const b = await scratch(t, { timeout: '1' });
  const s = await shell(t, b.sock);
  const started = Date.now();
  assert.match((await pair(b, KEYBOARD)).stderr, /org\.bluez\.Error\.AuthenticationRejected/);
  const took = Date.now() - started;
  assert.ok(took >= 900 && took < 5000, `took ${took} ms`);
  await s.until(() => s.conns[0]?.closed);
  assert.equal(s.conns[0].closed, true);
});

test('with no shell listening a request is rejected at once', async (t) => {
  const b = await scratch(t);
  const started = Date.now();
  assert.match((await pair(b, KEYBOARD)).stderr, /org\.bluez\.Error\.AuthenticationRejected/);
  assert.ok(Date.now() - started < 2000, `took ${Date.now() - started} ms`);
  assert.equal(await b.prop(KEYBOARD, 'Paired'), '(<false>,)');
});

test('a device with no name is named by its address', async (t) => {
  const b = await scratch(t);
  const s = await shell(t, b.sock, () => ({ ok: true }));
  await b.knob('SetPairing', NAMELESS, 'confirm', '1');
  assert.equal((await pair(b, NAMELESS)).code, 0);
  assert.deepEqual(s.requests, [{ kind: 'confirm', device: '00:00:00:00:00:07', address: '00:00:00:00:00:07', code: '000001', service: '' }]);
});

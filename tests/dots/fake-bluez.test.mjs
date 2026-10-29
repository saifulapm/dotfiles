// bin/dev-fake-bluez on a private bus, driven with gdbus as Quickshell and an agent drive BlueZ: discovery, power, and the Agent1 requests a Pair plays.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile, spawn } from 'node:child_process';

const bin = new URL('../../bin/dev-fake-bluez', import.meta.url).pathname;
const fakeAgent = new URL('./fixtures/fake-bt-agent', import.meta.url).pathname;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const HCI0 = '/org/bluez/hci0';
const dev = (n) => `${HCI0}/dev_00_00_00_00_00_0${n}`;
const MOUSE = dev(4);
const KEYBOARD = dev(5);
const PHONE = dev(6);
const NAMELESS = dev(7);
const HEADPHONES = dev(2);

// A private bus with the fake on it, standing in for the system bus; every process started here is killed after the test.
async function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'fake-bluez-'));
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
  const env = { ...process.env, DBUS_SESSION_BUS_ADDRESS: address, DBUS_SYSTEM_BUS_ADDRESS: address, FAKE_AGENT_REC: join(root, 'agent.rec') };
  const gdbus = (path, method, ...args) =>
    new Promise((resolve) =>
      execFile('gdbus', ['call', '--session', '--timeout', '20', '--dest', 'org.bluez', '--object-path', path, '--method', method, ...args], { env }, (err, stdout, stderr) =>
        resolve({ code: err ? err.code : 0, stdout: stdout.trim(), stderr }),
      ),
    );
  const fake = spawn(bin, [], { env, stdio: 'inherit' });
  procs.push(fake);
  for (let i = 0; i < 100 && (await gdbus('/', 'org.freedesktop.DBus.ObjectManager.GetManagedObjects')).code !== 0; i++) await sleep(50);
  const prop = async (path, iface, name) => (await gdbus(path, 'org.freedesktop.DBus.Properties.Get', iface, name)).stdout;
  const set = (path, iface, name, value) => gdbus(path, 'org.freedesktop.DBus.Properties.Set', iface, name, value);
  const objects = async () => (await gdbus('/', 'org.freedesktop.DBus.ObjectManager.GetManagedObjects')).stdout;
  const knob = (method, ...args) => gdbus('/org/bluez', `org.dots.FakeBluez.${method}`, ...args);
  const agentCalls = () => (existsSync(env.FAKE_AGENT_REC) ? readFileSync(env.FAKE_AGENT_REC, 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : []);
  const agent = async (answer = 'ok') => {
    procs.push(spawn(fakeAgent, [], { env: { ...env, FAKE_AGENT_ANSWER: answer }, stdio: 'inherit' }));
    for (let i = 0; i < 100 && !agentCalls().some((c) => c[0] === 'registered'); i++) await sleep(50);
  };
  const until = async (cond) => {
    for (let i = 0; i < 100 && !(await cond()); i++) await sleep(50);
  };
  return { address, gdbus, prop, set, objects, knob, agent, agentCalls, until };
}

test('a scan finds Test Mouse, Test Keyboard, Test Phone and a nameless device, which BlueZ keeps after the scan stops', async (t) => {
  const b = await scratch(t);
  assert.doesNotMatch(await b.objects(), /Test Mouse/);
  assert.equal((await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery')).code, 0);
  assert.equal(await b.prop(HCI0, 'org.bluez.Adapter1', 'Discovering'), '(<true>,)');
  const found = await b.objects();
  for (const name of ['Test Mouse', 'Test Keyboard', 'Test Phone']) assert.match(found, new RegExp(name));
  assert.equal(await b.prop(MOUSE, 'org.bluez.Device1', 'Paired'), '(<false>,)');
  // BlueZ gives a device that sent no name no Name, and an Alias of its address in dashes.
  assert.notEqual((await b.gdbus(NAMELESS, 'org.freedesktop.DBus.Properties.Get', 'org.bluez.Device1', 'Name')).code, 0);
  assert.equal(await b.prop(NAMELESS, 'org.bluez.Device1', 'Alias'), "(<'00-00-00-00-00-07'>,)");
  assert.equal((await b.gdbus(HCI0, 'org.bluez.Adapter1.StopDiscovery')).code, 0);
  assert.equal(await b.prop(HCI0, 'org.bluez.Adapter1', 'Discovering'), '(<false>,)');
  assert.match(await b.objects(), /Test Mouse/);
});

test('powering the adapter off stops the scan and drops connections, and it then refuses a scan or a pair', async (t) => {
  const b = await scratch(t);
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  await b.gdbus(HEADPHONES, 'org.bluez.Device1.Connect');
  assert.equal((await b.set(HCI0, 'org.bluez.Adapter1', 'Powered', '<false>')).code, 0);
  assert.equal(await b.prop(HCI0, 'org.bluez.Adapter1', 'Powered'), '(<false>,)');
  assert.equal(await b.prop(HCI0, 'org.bluez.Adapter1', 'Discovering'), '(<false>,)');
  assert.equal(await b.prop(HEADPHONES, 'org.bluez.Device1', 'Connected'), '(<false>,)');
  assert.match((await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery')).stderr, /org\.bluez\.Error\.NotReady/);
  assert.match((await b.gdbus(MOUSE, 'org.bluez.Device1.Pair')).stderr, /org\.bluez\.Error\.NotReady/);
  await b.set(HCI0, 'org.bluez.Adapter1', 'Powered', '<true>');
  assert.equal((await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery')).code, 0);
});

test('an agent registering as KeyboardDisplay and asking to be the default is recorded', async (t) => {
  const b = await scratch(t);
  await b.agent();
  assert.equal((await b.knob('Calls')).stdout, "(['RegisterAgent /test/agent KeyboardDisplay', 'RequestDefaultAgent /test/agent'],)");
});

test('Pair on Test Keyboard asks the agent to confirm 123456, and pairs without trusting once it agrees', async (t) => {
  const b = await scratch(t);
  await b.agent();
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  assert.equal((await b.gdbus(KEYBOARD, 'org.bluez.Device1.Pair')).code, 0);
  assert.deepEqual(b.agentCalls().at(-1), ['RequestConfirmation', KEYBOARD, 123456]);
  assert.equal(await b.prop(KEYBOARD, 'org.bluez.Device1', 'Paired'), '(<true>,)');
  assert.equal(await b.prop(KEYBOARD, 'org.bluez.Device1', 'Trusted'), '(<false>,)');
  assert.match((await b.gdbus(KEYBOARD, 'org.bluez.Device1.Pair')).stderr, /org\.bluez\.Error\.AlreadyExists/);
});

test('an agent that rejects leaves the device unpaired and the Pair failed', async (t) => {
  const b = await scratch(t);
  await b.agent('reject');
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  assert.match((await b.gdbus(KEYBOARD, 'org.bluez.Device1.Pair')).stderr, /org\.bluez\.Error\.AuthenticationRejected/);
  assert.equal(await b.prop(KEYBOARD, 'org.bluez.Device1', 'Paired'), '(<false>,)');
});

test('with no agent registered a pair that needs one fails', async (t) => {
  const b = await scratch(t);
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  assert.match((await b.gdbus(KEYBOARD, 'org.bluez.Device1.Pair')).stderr, /org\.bluez\.Error\.AuthenticationFailed/);
});

test('a passkey shown on the device pairs once it is typed there, and CancelPairing cancels it and the agent', async (t) => {
  const b = await scratch(t);
  await b.agent();
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  assert.equal((await b.knob('SetPairing', KEYBOARD, 'display', '654321')).code, 0);
  let pair = b.gdbus(KEYBOARD, 'org.bluez.Device1.Pair');
  await b.until(() => b.agentCalls().some((c) => c[0] === 'DisplayPasskey'));
  assert.deepEqual(b.agentCalls().at(-1), ['DisplayPasskey', KEYBOARD, 654321, 0]);
  assert.equal(await b.prop(KEYBOARD, 'org.bluez.Device1', 'Paired'), '(<false>,)');
  await b.knob('Typed', KEYBOARD);
  assert.equal((await pair).code, 0);
  assert.equal(await b.prop(KEYBOARD, 'org.bluez.Device1', 'Paired'), '(<true>,)');

  await b.knob('SetPairing', MOUSE, 'display', '111111');
  pair = b.gdbus(MOUSE, 'org.bluez.Device1.Pair');
  await b.until(() => b.agentCalls().filter((c) => c[0] === 'DisplayPasskey').length === 2);
  assert.equal((await b.gdbus(MOUSE, 'org.bluez.Device1.CancelPairing')).code, 0);
  assert.match((await pair).stderr, /org\.bluez\.Error\.AuthenticationCanceled/);
  assert.deepEqual(b.agentCalls().at(-1), ['Cancel']);
  assert.equal(await b.prop(MOUSE, 'org.bluez.Device1', 'Paired'), '(<false>,)');
});

test('a PIN or passkey the agent gives is recorded, and a fail kind fails without asking it', async (t) => {
  const b = await scratch(t);
  await b.agent();
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  await b.knob('SetPairing', KEYBOARD, 'pin', '0');
  assert.equal((await b.gdbus(KEYBOARD, 'org.bluez.Device1.Pair')).code, 0);
  await b.knob('SetPairing', MOUSE, 'passkey', '0');
  assert.equal((await b.gdbus(MOUSE, 'org.bluez.Device1.Pair')).code, 0);
  const calls = (await b.knob('Calls')).stdout;
  assert.match(calls, new RegExp(`'RequestPinCode ${KEYBOARD} 0000'`));
  assert.match(calls, new RegExp(`'RequestPasskey ${MOUSE} 1234'`));
  const asked = b.agentCalls().length;
  await b.knob('SetPairing', PHONE, 'fail', '0');
  assert.match((await b.gdbus(PHONE, 'org.bluez.Device1.Pair')).stderr, /org\.bluez\.Error\.ConnectionAttemptFailed/);
  assert.equal(b.agentCalls().length, asked);
});

test('Authorize asks the agent for a service and answers what it said', async (t) => {
  const b = await scratch(t);
  await b.agent();
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  const A2DP = '0000110d-0000-1000-8000-00805f9b34fb';
  assert.equal((await b.knob('Authorize', PHONE, A2DP)).stdout, "('allowed',)");
  assert.deepEqual(b.agentCalls().at(-1), ['AuthorizeService', PHONE, A2DP]);
});

test('Authorize answers the error an agent that refuses gives', async (t) => {
  const b = await scratch(t);
  await b.agent('reject');
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  assert.equal((await b.knob('Authorize', PHONE, '0000110d-0000-1000-8000-00805f9b34fb')).stdout, "('org.bluez.Error.Rejected',)");
});

test('Methods lists each scan, pair, connect and property set asked of it, refused ones too', async (t) => {
  const b = await scratch(t);
  await b.set(HCI0, 'org.bluez.Adapter1', 'Powered', '<false>');
  await b.gdbus(HCI0, 'org.bluez.Adapter1.StartDiscovery');
  await b.gdbus(HEADPHONES, 'org.bluez.Device1.Pair');
  await b.gdbus(HEADPHONES, 'org.bluez.Device1.Connect');
  await b.set(HEADPHONES, 'org.bluez.Device1', 'Trusted', '<false>');
  assert.equal(
    (await b.knob('Methods')).stdout,
    `(['Set ${HCI0} Powered', 'StartDiscovery ${HCI0}', 'Pair ${HEADPHONES}', 'Connect ${HEADPHONES}', 'Set ${HEADPHONES} Trusted'],)`,
  );
});

test('RegisterAgent with its path sent as a string finds no method, as BlueZ answers', async (t) => {
  const b = await scratch(t);
  const r = await new Promise((resolve) =>
    execFile('busctl', [`--address=${b.address}`, 'call', 'org.bluez', '/org/bluez', 'org.bluez.AgentManager1', 'RegisterAgent', 'ss', '/x', 'KeyboardDisplay'], (err, stdout, stderr) => resolve({ err, stderr })),
  );
  assert.ok(r.err);
  assert.match(r.stderr, /signature "ss"/);
  assert.equal((await b.knob('Calls')).stdout, '(@as [],)');
});

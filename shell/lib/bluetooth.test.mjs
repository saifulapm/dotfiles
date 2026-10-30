import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectText, lowBatteries, newlyConnected } from './bluetooth.mjs';

const dev = (address, connected, paired = true) => ({ address, connected, paired });

test('a paired device going from off to on is newly connected', () => {
  const first = newlyConnected({}, [dev('A', false)]);
  assert.deepEqual(first.connected, []);
  const next = newlyConnected(first.seen, [dev('A', true)]);
  assert.deepEqual(next.connected, ['A']);
  assert.deepEqual(newlyConnected(next.seen, [dev('A', true)]).connected, []);
});

test('a device first seen connected, as when the shell or bluetoothd starts, is not', () => {
  assert.deepEqual(newlyConnected({}, [dev('A', true)]).connected, []);
  // bluetoothd restarting drops every device, so each comes back as first seen.
  const gone = newlyConnected({ A: false }, []);
  assert.deepEqual(newlyConnected(gone.seen, [dev('A', true)]).connected, []);
});

test('an unpaired device connecting is not', () => {
  const { seen } = newlyConnected({}, [dev('B', false, false)]);
  assert.deepEqual(newlyConnected(seen, [dev('B', true, false)]).connected, []);
});

test('the connect state names the device and its battery, or the name alone', () => {
  assert.equal(connectText({ name: 'AirPods', battery: 0.8 }), 'AirPods connected · 80%');
  assert.equal(connectText({ name: 'Test Headphones', battery: null }), 'Test Headphones connected');
  assert.equal(connectText({ name: 'Two\nlines‮', battery: 0.155 }), 'Two lines connected · 16%');
});

const bat = (address, battery, name = 'Test Headphones') => ({ address, name, connected: true, battery });
// Feeds each reading in turn and returns the warnings, as text.
function run(readings) {
  let armed = {};
  const out = [];
  for (const devices of readings) {
    const r = lowBatteries(armed, devices);
    armed = r.armed;
    out.push(...r.warn);
  }
  return out;
}

test('a battery falling below 20 % warns once, until it reads above 30 %', () => {
  assert.deepEqual(run([[bat('A', 0.25)], [bat('A', 0.15)]]), ['Test Headphones battery 15%']);
  assert.deepEqual(run([[bat('A', 0.25)], [bat('A', 0.15)], [bat('A', 0.18)], [bat('A', 0.12)]]).length, 1);
  assert.deepEqual(run([[bat('A', 0.15)], [bat('A', 0.35)], [bat('A', 0.15)]]).length, 2);
  // Hovering at 19 to 21 % is never above 30 %, so it warns once.
  assert.deepEqual(run([0.21, 0.19, 0.21, 0.19, 0.2, 0.19].map((b) => [bat('A', b)])).length, 1);
  assert.deepEqual(run([[bat('A', 0.2)], [bat('A', 0.3)]]), []);
});

test('each device warns for itself, keyed by address', () => {
  assert.deepEqual(run([[bat('A', 0.5), bat('B', 0.5, 'Test Speaker')], [bat('A', 0.1), bat('B', 0.12, 'Test Speaker')]]), ['Test Headphones battery 10%', 'Test Speaker battery 12%']);
  assert.deepEqual(run([[bat('A', 0.1)], [bat('A', 0.1), bat('B', 0.1, 'Test Speaker')]]), ['Test Headphones battery 10%', 'Test Speaker battery 10%']);
});

test('a device with no battery, or not connected, never warns', () => {
  assert.deepEqual(run([[bat('A', null)], [{ ...bat('A', 0.1), connected: false }]]), []);
});

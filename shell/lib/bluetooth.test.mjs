import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectText, newlyConnected } from './bluetooth.mjs';

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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { btOrder, btRow, wifiOrder, wifiRow } from './control-net.mjs';

test('Bluetooth lists connected devices, then paired, then new ones, by name in each', () => {
  const devs = [
    { name: 'Speaker', connected: false, paired: false },
    { name: 'Mouse', connected: false, paired: true },
    { name: 'Keyboard', connected: true, paired: true },
    { name: 'Headphones', connected: false, paired: true },
  ];
  assert.deepEqual(btOrder(devs), [2, 3, 1, 0]);
});

test('a Bluetooth row names the device and reads connected, paired or new', () => {
  assert.deepEqual(btRow({ name: 'Test Headphones', connected: true, paired: true }), { title: 'Test Headphones', detail: 'connected' });
  assert.deepEqual(btRow({ name: 'Test Headphones', connected: false, paired: true }), { title: 'Test Headphones', detail: 'paired' });
  assert.deepEqual(btRow({ name: 'Test Speaker', connected: false, paired: false }), { title: 'Test Speaker', detail: 'new' });
});

test('a connected Bluetooth device with a battery reads its percentage', () => {
  assert.equal(btRow({ name: 'H', connected: true, paired: true, batteryAvailable: true, battery: 0.8 }).detail, 'connected · 80%');
  assert.equal(btRow({ name: 'H', connected: true, paired: true, batteryAvailable: false, battery: 0 }).detail, 'connected');
  assert.equal(btRow({ name: 'H', connected: false, paired: true, batteryAvailable: true, battery: 0.8 }).detail, 'paired');
});

test('a battery outside 0-100, which only a forged headset reports, draws no percentage', () => {
  for (const battery of [2.55, 1.01, -0.1, NaN]) assert.equal(btRow({ name: 'H', connected: true, paired: true, batteryAvailable: true, battery }).detail, 'connected', battery);
  assert.equal(btRow({ name: 'H', connected: true, paired: true, batteryAvailable: true, battery: 1 }).detail, 'connected · 100%');
  assert.equal(btRow({ name: 'H', connected: true, paired: true, batteryAvailable: true, battery: 0 }).detail, 'connected · 0%');
});

test('a headset-controlled name draws on one line without controls or bidi marks, and an empty one as the address', () => {
  const row = (name) => btRow({ name, address: '67:6D:E6:03:06:ED', connected: false, paired: true }).title;
  assert.equal(row('Evil\nSecond line'), 'Evil Second line');
  assert.equal(row('Bad\x1b[31mRED'), 'Bad [31mRED');
  assert.equal(row('Pwn\u202etxt.exe'), 'Pwntxt.exe');
  assert.equal(row(''), '67:6D:E6:03:06:ED');
  assert.equal(row('\u202e \n'), '67:6D:E6:03:06:ED');
});

test('Wi-Fi lists the connected network, then known ones, then the rest by signal', () => {
  const nets = [
    { name: 'cafe', connected: false, known: false, signalStrength: 0.4 },
    { name: 'office', connected: false, known: true, signalStrength: 0.3 },
    { name: 'home', connected: true, known: true, signalStrength: 0.9 },
    { name: 'library', connected: false, known: false, signalStrength: 0.8 },
  ];
  assert.deepEqual(wifiOrder(nets), [2, 1, 3, 0]);
});

test('a Wi-Fi row names the network and reads connected, known or its signal', () => {
  assert.deepEqual(wifiRow({ name: 'home', connected: true, known: true, signalStrength: 0.9 }), { title: 'home', detail: 'connected' });
  assert.deepEqual(wifiRow({ name: 'office', connected: false, known: true, signalStrength: 0.3 }), { title: 'office', detail: 'known' });
  assert.deepEqual(wifiRow({ name: 'cafe', connected: false, known: false, signalStrength: 0.416 }), { title: 'cafe', detail: '42%' });
});

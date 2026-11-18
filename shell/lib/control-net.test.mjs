import { test } from 'node:test';
import assert from 'node:assert/strict';
import { btEmpty, btHint, btLook, btOrder, btRow, wifiLook, wifiOrder, wifiRow } from './control-net.mjs';

test('Bluetooth lists connected devices, then paired, then new ones, by name in each', () => {
  const devs = [
    { name: 'Speaker', connected: false, paired: false },
    { name: 'Mouse', connected: false, paired: true },
    { name: 'Keyboard', connected: true, paired: true },
    { name: 'Headphones', connected: false, paired: true },
  ];
  assert.deepEqual(btOrder(devs, true), [2, 3, 1, 0]);
});

test('the Bluetooth hint names the keys, or says the adapter is off or missing', () => {
  assert.equal(btHint({ adapter: false, enabled: false }), 'No Bluetooth');
  assert.equal(btHint({ adapter: true, enabled: false }), 'Bluetooth off · o turn on');
  assert.equal(btHint({ adapter: true, enabled: true, discovering: false }), '↵ connect · s scan · t trust · p pair · d forget · o off');
  assert.equal(btHint({ adapter: true, enabled: true, discovering: true }), '↵ connect · s stop · t trust · p pair · d forget · o off');
});

test('new devices list only while a scan runs, and a connected one always', () => {
  const devs = [
    { name: 'Mouse', connected: false, paired: false },
    { name: 'Speaker', connected: true, paired: false },
    { name: 'Headphones', connected: false, paired: true },
  ];
  assert.deepEqual(btOrder(devs, false), [1, 2]);
  assert.deepEqual(btOrder(devs, true), [1, 2, 0]);
});

test('a nameless device sorts after the named ones beside it, by address', () => {
  const devs = [
    { name: '', address: '00:00:00:00:00:09', connected: false, paired: false },
    { name: 'Zebra Mouse', address: '00:00:00:00:00:04', connected: false, paired: false },
    { name: '', address: '00:00:00:00:00:07', connected: false, paired: false },
    { name: 'Headphones', address: '00:00:00:00:00:02', connected: false, paired: true },
  ];
  assert.deepEqual(btOrder(devs, true), [3, 1, 2, 0]);
});

test('a Bluetooth row names the device and reads connected, paired or new', () => {
  assert.deepEqual(btRow({ name: 'Test Headphones', connected: true, paired: true }), { title: 'Test Headphones', detail: 'connected' });
  assert.deepEqual(btRow({ name: 'Test Headphones', connected: false, paired: true }), { title: 'Test Headphones', detail: 'paired' });
  assert.deepEqual(btRow({ name: 'Test Speaker', connected: false, paired: false }), { title: 'Test Speaker', detail: 'new' });
});

test('a trusted paired device adds trusted to its detail, before any battery', () => {
  assert.equal(btRow({ name: 'H', connected: false, paired: true, trusted: true }).detail, 'paired · trusted');
  assert.equal(btRow({ name: 'H', connected: true, paired: true, trusted: true }).detail, 'connected · trusted');
  assert.equal(btRow({ name: 'H', connected: true, paired: true, trusted: true, batteryAvailable: true, battery: 0.8 }).detail, 'connected · trusted · 80%');
  assert.equal(btRow({ name: 'H', connected: false, paired: false, trusted: true }).detail, 'new');
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

test('a Wi-Fi page row reads as board 4 draws it: glyph by signal, what it is, and its mark', () => {
  const joined = wifiLook({ connected: true, known: true, secured: true, signalStrength: 0.94 });
  assert.equal(joined.sub, 'Connected · 94%');
  assert.equal(joined.glyph, String.fromCodePoint(0xf0928));
  assert.equal(joined.mark, String.fromCodePoint(0xf012c));
  assert.equal(wifiLook({ connected: false, known: true, secured: true, signalStrength: 0.6 }).sub, 'Saved');
  const locked = wifiLook({ connected: false, known: false, secured: true, signalStrength: 0.4 });
  assert.equal(locked.sub, 'Secured');
  assert.equal(locked.glyph, String.fromCodePoint(0xf0922));
  assert.equal(locked.mark, String.fromCodePoint(0xf033e));
  assert.equal(wifiLook({ connected: false, known: false, secured: false, signalStrength: 0.1 }).sub, 'Open');
});

test('a Bluetooth page row: a glyph by kind, Connected with its battery, and a check while connected', () => {
  const pods = btLook({ icon: 'audio-headset', connected: true, paired: true, battery: 0.8, batteryAvailable: true });
  assert.equal(pods.glyph, String.fromCodePoint(0xf02cb));
  assert.equal(pods.sub, 'Connected · 80%');
  assert.equal(pods.mark, String.fromCodePoint(0xf012c));
  assert.equal(btLook({ icon: 'input-keyboard', connected: false, paired: true, battery: 0, batteryAvailable: false }).sub, 'Paired');
  assert.equal(btLook({ icon: '', connected: false, paired: false, battery: 0, batteryAvailable: false }).glyph, String.fromCodePoint(0xf00af));
  assert.equal(btEmpty({ adapter: false, enabled: false }), 'No Bluetooth');
  assert.equal(btEmpty({ adapter: true, enabled: false }), 'Bluetooth is off');
  assert.equal(btEmpty({ adapter: true, enabled: true }), '');
});

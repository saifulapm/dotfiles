import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SECTIONS, cycle, stepVolume, audioRow } from './control.mjs';

test('the six sections, in Tab order', () => {
  assert.deepEqual(SECTIONS, ['audio', 'wifi', 'bluetooth', 'power', 'display', 'route']);
});

test('Tab steps forward and wraps from route to audio', () => {
  assert.equal(cycle(0, 1), 1);
  assert.equal(cycle(5, 1), 0);
});

test('Shift+Tab steps back and wraps from audio to route', () => {
  assert.equal(cycle(2, -1), 1);
  assert.equal(cycle(0, -1), 5);
});

test('a volume step is 5 % and lands on whole percents', () => {
  assert.equal(stepVolume(0.4, 1), 0.45);
  assert.equal(stepVolume(0.45, -1), 0.4);
  assert.equal(stepVolume(0.30000000000000004, 1), 0.35);
});

test('volume clamps to 0 and 100 %, with no boost', () => {
  assert.equal(stepVolume(0.98, 1), 1);
  assert.equal(stepVolume(1.2, 1), 1);
  assert.equal(stepVolume(0.03, -1), 0);
});

test('a row names the device and reads its kind, volume and default', () => {
  assert.deepEqual(audioRow({ description: 'Dots null sink', name: 'dots-null', isSink: true, volume: 0.45, muted: false, isDefault: true }), {
    title: 'Dots null sink',
    detail: 'Output · 45% · default',
  });
  assert.deepEqual(audioRow({ description: '', name: 'dots-mic', isSink: false, volume: 1, muted: true, isDefault: false }), {
    title: 'dots-mic',
    detail: 'Input · muted',
  });
});

test("a device's row adds its profile and port after the rest", () => {
  const row = audioRow({ description: 'AirPods', name: 'bluez_output', isSink: true, volume: 0.5, muted: false, isDefault: true, device: ['High Fidelity Playback (A2DP Sink, codec AAC)', 'Headphones'] });
  assert.equal(row.detail, 'Output · 50% · default · High Fidelity Playback (A2DP Sink, codec AAC) · Headphones');
});

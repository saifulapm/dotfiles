import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FROST_SWITCH, frostAt } from './frost-switch.mjs';

test('the frost switch covers by 180 ms, swaps the theme there and melts by 280 ms, a frame inside its 300', () => {
  assert.deepEqual(FROST_SWITCH, { coverMs: 180, ms: 280 });
  assert.deepEqual(frostAt(0), { reach: 0, swapped: false });
  assert.deepEqual(frostAt(180 / 280), { reach: 1, swapped: true });
  assert.deepEqual(frostAt(1), { reach: 0, swapped: true });
  assert.equal(frostAt(179 / 280).swapped, false);
});

test('the frost grows in easing in and melts easing out', () => {
  // Ease-in: under half its reach at half the growth.
  assert.ok(frostAt(90 / 280).reach < 0.5);
  // Ease-out: past half its melt at half the melt, so under half its reach is left.
  assert.ok(frostAt(230 / 280).reach < 0.5);
  // It grows the whole way in and melts the whole way back.
  for (let ms = 0; ms < 180; ms += 10) assert.ok(frostAt(ms / 280).reach < frostAt((ms + 10) / 280).reach);
  for (let ms = 180; ms < 280; ms += 10) assert.ok(frostAt(ms / 280).reach > frostAt((ms + 10) / 280).reach);
});

test('a time outside the switch clamps to its ends', () => {
  assert.deepEqual(frostAt(-0.5), frostAt(0));
  assert.deepEqual(frostAt(1.5), frostAt(1));
});

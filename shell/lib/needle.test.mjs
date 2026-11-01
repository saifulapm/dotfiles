import { test } from 'node:test';
import assert from 'node:assert/strict';
import { needleAt, needlePeak, SWING_MS } from './needle.mjs';

const sweep = (from, to) => Array.from({ length: 301 }, (_, ms) => needleAt(from, to, ms));

test('the swing lasts 300 ms and lands exactly on the target', () => {
  assert.equal(SWING_MS, 300);
  assert.equal(needleAt(40, 62, 0), 40);
  assert.equal(needleAt(40, 62, 300), 62);
  assert.equal(needleAt(40, 62, 900), 62);
});

test('a swing from 40 to 62 overshoots by 6 % of the 22 point travel, once', () => {
  assert.ok(needlePeak(40, 62) >= 63.32, `peak ${needlePeak(40, 62)}`);
  const drawn = sweep(40, 62);
  const top = Math.max(...drawn);
  assert.ok(top >= 63.3 && top <= 63.5, `drawn top ${top}`);
  // It rises past 62 once and then comes back down to it, with no second swing.
  const past = drawn.map((v) => v > 62);
  const entries = past.filter((p, i) => p && !past[i - 1]).length;
  assert.equal(entries, 1);
  const peakAt = drawn.indexOf(top);
  assert.ok(drawn.slice(peakAt).every((v, i, a) => i === 0 || v <= a[i - 1]), 'falls back monotonically');
});

test('a downward swing overshoots below its target', () => {
  assert.ok(needlePeak(62, 40) <= 38.68, `peak ${needlePeak(62, 40)}`);
  assert.ok(Math.min(...sweep(62, 40)) <= 38.7);
  assert.equal(needleAt(62, 40, 300), 40);
});

test('a swing retargeted mid-way starts from the value then drawn', () => {
  const mid = needleAt(40, 62, 120);
  assert.ok(mid > 40 && mid < 62);
  assert.equal(needleAt(mid, 56, 0), mid);
  assert.equal(needleAt(mid, 56, 300), 56);
});

test('a slowdown stretches the swing', () => {
  assert.equal(needleAt(40, 62, 300, 600), needleAt(40, 62, 150));
  assert.equal(needleAt(40, 62, 600, 600), 62);
});

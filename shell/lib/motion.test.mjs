import { test } from 'node:test';
import assert from 'node:assert/strict';
import { surfaceMotion, surfacePose, slowdownOf } from './motion.mjs';

const near = (a, b, d = 0.01) => assert.ok(Math.abs(a - b) <= d, `${a} is not within ${d} of ${b}`);

test('Paper drops 6 px in 120 ms with no fade', () => {
  const m = surfaceMotion('snappy');
  assert.equal(m.kind, 'drop');
  assert.equal(m.openMs, 120);
  assert.deepEqual(surfacePose(m, 0), { lift: -6, scale: 1, outline: 1, fill: 1 });
  assert.deepEqual(surfacePose(m, 1), { lift: 0, scale: 1, outline: 1, fill: 1 });
  // niri's snappy curve is front-loaded: halfway through it has dropped most of the way.
  assert.ok(surfacePose(m, 0.5).lift > -1);
});

test('Artboard rises from 96% and 8 px lower on the island spring, and settles within 400 ms', () => {
  const m = surfaceMotion('spring');
  assert.equal(m.kind, 'spring');
  assert.ok(m.openMs > 300 && m.openMs <= 400, `spring settles in ${m.openMs} ms`);
  assert.deepEqual(surfacePose(m, 0), { lift: 8, scale: 0.96, outline: 1, fill: 1 });
  assert.deepEqual(surfacePose(m, 1), { lift: 0, scale: 1, outline: 1, fill: 1 });
  // It overshoots its rest before it settles.
  const peak = Math.max(...Array.from({ length: 101 }, (_, i) => surfacePose(m, i / 100).scale));
  assert.ok(peak > 1.001, `peak scale ${peak}`);
});

test('Blueprint plots the outline in 160 ms, then the fill in 80 ms', () => {
  const m = surfaceMotion('linear');
  assert.equal(m.kind, 'plot');
  assert.equal(m.openMs, 240);
  assert.deepEqual(surfacePose(m, 0), { lift: 0, scale: 1, outline: 0, fill: 0 });
  const at = (ms) => surfacePose(m, ms / 240);
  near(at(80).outline, 0.5);
  assert.equal(at(80).fill, 0);
  assert.equal(at(160).outline, 1);
  assert.equal(at(160).fill, 0);
  near(at(200).fill, 0.5);
  assert.deepEqual(at(240), { lift: 0, scale: 1, outline: 1, fill: 1 });
});

test('closing plays the same poses at 0.8 of the time', () => {
  for (const token of ['snappy', 'spring', 'linear']) {
    const m = surfaceMotion(token);
    assert.equal(m.closeMs, Math.round(m.openMs * 0.8), token);
  }
});

test('the slowdown stretches open and close alike', () => {
  const m = surfaceMotion('linear', 20);
  assert.equal(m.openMs, 4800);
  assert.equal(m.closeMs, 3840);
  near(surfacePose(m, 0.5).outline, 0.75);
});

test('the other motion tokens map to the nearest of the three', () => {
  assert.equal(surfaceMotion('ease').kind, 'drop');
  assert.equal(surfaceMotion('typewriter').kind, 'plot');
  assert.equal(surfaceMotion(undefined), null);
});

test('a slowdown is a positive number, else 1', () => {
  assert.equal(slowdownOf('20'), 20);
  assert.equal(slowdownOf('0.5'), 0.5);
  for (const v of ['', undefined, null, '0', '-3', 'fast', 'Infinity']) assert.equal(slowdownOf(v), 1, String(v));
});

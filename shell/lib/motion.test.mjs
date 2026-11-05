import { test } from 'node:test';
import assert from 'node:assert/strict';
import { surfaceMotion, surfacePose, slowdownOf } from './motion.mjs';

test('a surface rises from 96% and 8 px lower on the island spring, and settles within 400 ms', () => {
  const m = surfaceMotion();
  assert.equal(m.kind, 'spring');
  assert.ok(m.openMs > 300 && m.openMs <= 400, `spring settles in ${m.openMs} ms`);
  assert.deepEqual(surfacePose(m, 0), { lift: 8, scale: 0.96 });
  assert.deepEqual(surfacePose(m, 1), { lift: 0, scale: 1 });
  // It overshoots its rest before it settles.
  const peak = Math.max(...Array.from({ length: 101 }, (_, i) => surfacePose(m, i / 100).scale));
  assert.ok(peak > 1.001, `peak scale ${peak}`);
});

test('closing plays the same poses at 0.8 of the time', () => {
  const m = surfaceMotion();
  assert.equal(m.closeMs, Math.round(m.openMs * 0.8));
});

test('the slowdown stretches open and close alike', () => {
  const m = surfaceMotion(20);
  assert.equal(m.openMs, surfaceMotion().openMs * 20);
  assert.equal(m.closeMs, Math.round(m.openMs * 0.8));
});

test('a slowdown is a positive number, else 1', () => {
  assert.equal(slowdownOf('20'), 20);
  assert.equal(slowdownOf('0.5'), 0.5);
  for (const v of ['', undefined, null, '0', '-3', 'fast', 'Infinity']) assert.equal(slowdownOf(v), 1, String(v));
});

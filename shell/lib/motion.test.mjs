import { test } from 'node:test';
import assert from 'node:assert/strict';
import { surfaceMotion, surfacePose, closePose, slowdownOf } from './motion.mjs';

test('a surface rises from 96% and 8 px lower on the island spring, and settles within 400 ms', () => {
  const m = surfaceMotion();
  assert.equal(m.kind, 'spring');
  assert.ok(m.openMs > 300 && m.openMs <= 400, `spring settles in ${m.openMs} ms`);
  assert.deepEqual(surfacePose(m, 0), { lift: 8, scale: 0.96, opacity: 1 });
  assert.deepEqual(surfacePose(m, 1), { lift: 0, scale: 1, opacity: 1 });
  // It overshoots its rest before it settles.
  const peak = Math.max(...Array.from({ length: 101 }, (_, i) => surfacePose(m, i / 100).scale));
  assert.ok(peak > 1.001, `peak scale ${peak}`);
});

test('a close takes 120 ms whatever the open took, and the slowdown stretches it too', () => {
  assert.equal(surfaceMotion().closeMs, 120);
  assert.equal(surfaceMotion(20).openMs, surfaceMotion().openMs * 20);
  assert.equal(surfaceMotion(20).closeMs, 2400);
});

test('a close fades out fast from its first frame and shrinks 4% from where the open had got to', () => {
  const m = surfaceMotion();
  assert.deepEqual(closePose(m, 1, 1), { lift: 0, scale: 1, opacity: 1 });
  assert.deepEqual(closePose(m, 1, 0), { lift: 0, scale: 0.96, opacity: 0 });
  // A quarter of the way through, under 60% is left: it leaves at once rather than easing in.
  assert.ok(closePose(m, 1, 0.75).opacity < 0.6, `opacity ${closePose(m, 1, 0.75).opacity}`);
  // From mid-open it starts at the pose it was in, so nothing jumps.
  const at = surfacePose(m, 0.3);
  assert.deepEqual(closePose(m, 0.3, 1), Object.assign({}, at, { opacity: 1 }));
  assert.equal(closePose(m, 0.3, 0).scale, at.scale * 0.96);
});

test('an open is fully opaque the whole way', () => {
  const m = surfaceMotion();
  for (let i = 0; i <= 10; i++) assert.equal(surfacePose(m, i / 10).opacity, 1);
});

test('a slowdown is a positive number, else 1', () => {
  assert.equal(slowdownOf('20'), 20);
  assert.equal(slowdownOf('0.5'), 0.5);
  for (const v of ['', undefined, null, '0', '-3', 'fast', 'Infinity']) assert.equal(slowdownOf(v), 1, String(v));
});

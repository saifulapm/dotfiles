import { test } from 'node:test';
import assert from 'node:assert/strict';
import { STEP, MIN, start, move, resize, full, geometry, fileName } from './recorder.mjs';

const out = { x: 100, y: 0, width: 1280, height: 720 };

test('the picker starts on a centred region half the output', () => {
  assert.deepEqual(start(out), { x: 320, y: 180, w: 640, h: 360 });
});

test('h, j, k and l move the region one step, never off the output', () => {
  const r = start(out);
  assert.deepEqual(move(r, 1, 0, out), { x: 320 + STEP, y: 180, w: 640, h: 360 });
  assert.deepEqual(move(r, 0, -1, out), { x: 320, y: 180 - STEP, w: 640, h: 360 });
  assert.deepEqual(move({ x: 630, y: 0, w: 640, h: 360 }, 1, 0, out), { x: 640, y: 0, w: 640, h: 360 });
  assert.deepEqual(move({ x: 5, y: 5, w: 640, h: 360 }, -1, -1, out), { x: 0, y: 0, w: 640, h: 360 });
});

test('H, J, K and L resize from the top-left corner, between MIN and the output edge', () => {
  const r = start(out);
  assert.deepEqual(resize(r, 1, 0, out), { x: 320, y: 180, w: 640 + STEP, h: 360 });
  assert.deepEqual(resize(r, 0, -1, out), { x: 320, y: 180, w: 640, h: 360 - STEP });
  assert.deepEqual(resize({ x: 0, y: 0, w: MIN, h: MIN }, -1, -1, out), { x: 0, y: 0, w: MIN, h: MIN });
  assert.deepEqual(resize({ x: 1200, y: 0, w: 70, h: 100 }, 1, 0, out), { x: 1200, y: 0, w: 80, h: 100 });
});

test('f takes the whole output', () => {
  assert.deepEqual(full(out), { x: 0, y: 0, w: 1280, h: 720 });
});

test('the geometry is in global coordinates, as wf-recorder -g reads it', () => {
  assert.equal(geometry({ x: 20, y: 30, w: 640, h: 360 }, out), '120,30 640x360');
});

test('a recording is named by its local start time', () => {
  assert.equal(fileName(new Date(2026, 9, 19, 2, 40, 5)), '2026-10-19_02-40-05.mp4');
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { STEP, MIN, start, move, resize, span, grab, full, geometry, fileName } from './recorder.mjs';

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

test('a region is never narrower or shorter than 16 px', () => {
  assert.deepEqual(resize({ x: 0, y: 0, w: 30, h: 30 }, -1, -1, out), { x: 0, y: 0, w: 16, h: 16 });
  assert.deepEqual(span({ x: 100, y: 100 }, { x: 105, y: 200 }, out), { x: 100, y: 100, w: 16, h: 100 });
  assert.deepEqual(span({ x: 100, y: 100 }, { x: 95, y: 98 }, out), { x: 84, y: 84, w: 16, h: 16 });
});

test('a drag spans the region from where it starts to the pointer, either way, inside the output', () => {
  assert.deepEqual(span({ x: 40, y: 40 }, { x: 440, y: 340 }, out), { x: 40, y: 40, w: 400, h: 300 });
  assert.deepEqual(span({ x: 440, y: 340 }, { x: 40, y: 40 }, out), { x: 40, y: 40, w: 400, h: 300 });
  assert.deepEqual(span({ x: 1000, y: 600 }, { x: 1400, y: 900 }, out), { x: 1000, y: 600, w: 280, h: 120 });
  assert.deepEqual(span({ x: 5, y: 5 }, { x: 2, y: 2 }, out), { x: 0, y: 0, w: 16, h: 16 });
});

test('a press on a corner handle holds the opposite corner, and one elsewhere holds nothing', () => {
  const r = { x: 40, y: 40, w: 400, h: 300 };
  assert.deepEqual(grab(r, 440, 340), { x: 40, y: 40 });
  assert.deepEqual(grab(r, 46, 35), { x: 440, y: 340 });
  assert.deepEqual(grab(r, 433, 47), { x: 40, y: 340 });
  assert.deepEqual(grab(r, 40, 340), { x: 440, y: 40 });
  assert.equal(grab(r, 240, 190), null);
  assert.equal(grab(r, 40, 60), null);
});

test('dragging the bottom-right handle to 840, 640 makes the region 800 x 600', () => {
  const r = { x: 40, y: 40, w: 400, h: 300 };
  assert.deepEqual(span(grab(r, 440, 340), { x: 840, y: 640 }, out), { x: 40, y: 40, w: 800, h: 600 });
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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { boxJson, clickArea } from './click.mjs';

const shell = new URL('..', import.meta.url).pathname;
const files = readdirSync(shell, { recursive: true }).filter((f) => /\.(qml|mjs|js)$/.test(f) && !f.endsWith('.test.mjs'));

test('every click area is the shared Click.qml, so no file names DekhoClick', () => {
  assert.deepEqual(files.filter((f) => f.includes('DekhoClick') || readFileSync(join(shell, f), 'utf8').includes('DekhoClick')), []);
  assert.ok(files.includes('Click.qml'));
});

const item = (objectName, children = [], visible = true, at = { x: 0, y: 0 }) => ({
  objectName, children, visible, width: 40, height: 20, mapToItem: () => at,
});

test('a box is the first drawn click area by that name, skipping hidden pages', () => {
  const hidden = item('', [item('click:row:0', [], true, { x: 1, y: 1 })], false);
  const shown = item('', [item('click:row:0', [], true, { x: 12, y: 30 })]);
  const root = item('', [hidden, shown]);
  assert.equal(clickArea(root, 'row:0'), shown.children[0]);
  assert.deepEqual(JSON.parse(boxJson(root, 'row:0')), { x: 12, y: 30, w: 40, h: 20 });
  assert.equal(boxJson(root, 'row:1'), 'null');
});

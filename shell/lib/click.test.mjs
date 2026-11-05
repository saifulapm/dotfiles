import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { boxJson, clickArea, onCard } from './click.mjs';

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

// An item whose children sit at fixed boxes, mapping a point into a child as Qt does.
const node = (objectName, box, children = []) => ({
  objectName, box, children, visible: true, width: box.w, height: box.h,
  mapToItem(child, x, y) { return { x: x - child.box.x, y: y - child.box.y }; },
});

test('a press is on the card when any item under it, however deep, is a card', () => {
  const card = node('card', { x: 100, y: 100, w: 200, h: 100 }, [node('', { x: 10, y: 10, w: 50, h: 20 })]);
  const surface = node('', { x: 0, y: 0, w: 1000, h: 800 }, [node('', { x: 0, y: 0, w: 1000, h: 800 }), node('', { x: 0, y: 0, w: 1000, h: 800 }, [card])]);
  assert.equal(onCard(surface, 120, 115), true);
  assert.equal(onCard(surface, 299, 199), true);
  assert.equal(onCard(surface, 50, 50), false);
  assert.equal(onCard(surface, 300, 150), false);
  // A layer drawn over the card, such as a popup's full-size holder, does not hide it.
  const over = node('', { x: 0, y: 0, w: 1000, h: 800 }, [card, node('', { x: 0, y: 0, w: 1000, h: 800 })]);
  assert.equal(onCard(over, 120, 115), true);
  // A card in a holder of no size of its own still counts, since Qt draws children past their parent's bounds.
  const holder = node('', { x: 0, y: 0, w: 0, h: 0 }, [card]);
  assert.equal(onCard(node('', { x: 0, y: 0, w: 1000, h: 800 }, [holder]), 120, 115), true);
  card.visible = false;
  assert.equal(onCard(over, 120, 115), false);
});

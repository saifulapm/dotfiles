import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rank } from './launcher.mjs';

const app = (name, keywords = []) => ({ id: name.toLowerCase(), name, genericName: '', keywords });
const names = (entries) => entries.map((e) => e.name);

test('foot ranks the entry named Foot first', () => {
  const entries = [app('Foot Server'), app('Footnote Editor'), app('Foot Client'), app('Foot'), app('Firefox')];
  assert.deepEqual(names(rank(entries, 'foot')), ['Foot', 'Foot Client', 'Foot Server', 'Footnote Editor']);
});

test('name prefix, then word prefix, then substring, then keywords', () => {
  const entries = [app('Image Editor', ['vips']), app('Davinci'), app('Font Viewer'), app('Vim'), app('Calculator')];
  assert.deepEqual(names(rank(entries, 'vi')), ['Vim', 'Font Viewer', 'Davinci', 'Image Editor']);
});

test('matching ignores case', () => {
  assert.deepEqual(names(rank([app('Font Viewer'), app('mpv')], 'FONT')), ['Font Viewer']);
});

test('an empty query lists every entry by name', () => {
  assert.deepEqual(names(rank([app('zathura'), app('Foot'), app('Chromium')], '')), ['Chromium', 'Foot', 'zathura']);
});

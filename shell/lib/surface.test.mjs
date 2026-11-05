import { test } from 'node:test';
import assert from 'node:assert/strict';
import { surfaceStyle, marginStyle, restyled } from './surface.mjs';
import { schemeTokens } from './colorscheme-file.mjs';

const artboard = schemeTokens('artboard');
const mocha = schemeTokens('catppuccin-mocha');

test("a card is the scheme's surface in a 1 px ink frame, square, with no shadow, over a 0.72 wash", () => {
  assert.deepEqual(surfaceStyle(artboard, 'card'), { fill: '#FFFFFF', text: '#15171B', frame: { width: 1, color: '#15171B' }, wash: 0.72 });
  assert.deepEqual(surfaceStyle(mocha, 'card'), { fill: '#1E1E2E', text: '#CDD6F4', frame: { width: 1, color: '#CDD6F4' }, wash: 0.72 });
});

test("a light scheme's island is an ink slab with paper text; a dark scheme's is its surface with ink text", () => {
  assert.deepEqual(surfaceStyle(artboard, 'island'), { fill: '#15171B', text: '#E4E6EA', frame: { width: 0, color: '#15171B' }, wash: 0.72 });
  assert.deepEqual(surfaceStyle(mocha, 'island'), { fill: '#1E1E2E', text: '#CDD6F4', frame: { width: 0, color: '#CDD6F4' }, wash: 0.72 });
  assert.deepEqual(surfaceStyle(artboard, 'chip'), surfaceStyle(artboard, 'island'));
});

test('every scheme gives the same shape, so nothing but colour changes between them', () => {
  for (const n of ['artboard', 'catppuccin-mocha', 'github-light', 'gruvbox-dark', 'rose-pine-dawn']) {
    for (const role of ['card', 'island', 'chip']) assert.deepEqual(Object.keys(surfaceStyle(schemeTokens(n), role)), ['fill', 'text', 'frame', 'wash'], `${n} ${role}`);
  }
});

test('before the tokens load a surface draws nothing', () => {
  assert.deepEqual(surfaceStyle(null, 'card'), { fill: 'transparent', text: 'transparent', frame: { width: 0, color: 'transparent' }, wash: 0 });
});

test('margins are the ui face at 12 px as written, over ink rules', () => {
  assert.deepEqual(marginStyle(artboard), { font: 'Maple Mono', size: 12, caps: false, tracking: 0, rules: true });
  assert.equal(marginStyle(null).rules, false);
});

test('a restyle swaps the fill, text and frame it names and keeps the rest (m21 lease warning)', () => {
  const style = surfaceStyle(artboard, 'island');
  assert.deepEqual(restyled(style, null), style);
  assert.deepEqual(restyled(style, { fill: '#B4380B' }), Object.assign({}, style, { fill: '#B4380B' }));
  assert.deepEqual(restyled(style, { frame: { width: 2, color: '#3D5AFE' } }).frame, { width: 2, color: '#3D5AFE' });
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { surfaceStyle, marginStyle, restyled } from './surface.mjs';
import { schemeTokens, schemeNames } from './colorscheme-file.mjs';

const artboard = schemeTokens('artboard');
const mocha = schemeTokens('catppuccin-mocha');

test("a card is the scheme's surface in a 1 px line frame, square, with no shadow, over a 0.72 wash", () => {
  assert.deepEqual(surfaceStyle(artboard, 'card'), { fill: '#FFFFFF', text: '#15171B', frame: { width: 1, color: '#D0D7DE' }, wash: 0.72 });
  assert.deepEqual(surfaceStyle(mocha, 'card'), { fill: '#1E1E2E', text: '#CDD6F4', frame: { width: 1, color: '#37394B' }, wash: 0.72 });
});

test("a light scheme's island is an ink slab with paper text; a dark scheme's is its surface with ink text", () => {
  assert.deepEqual(surfaceStyle(artboard, 'island'), { fill: '#15171B', text: '#E4E6EA', frame: { width: 0, color: '#15171B' }, wash: 0.72 });
  assert.deepEqual(surfaceStyle(mocha, 'island'), { fill: '#1E1E2E', text: '#CDD6F4', frame: { width: 0, color: '#CDD6F4' }, wash: 0.72 });
  assert.deepEqual(surfaceStyle(artboard, 'chip'), surfaceStyle(artboard, 'island'));
});

test('every scheme gives the same shape, so nothing but colour changes between them', () => {
  for (const n of schemeNames()) {
    for (const role of ['card', 'island', 'chip']) assert.deepEqual(Object.keys(surfaceStyle(schemeTokens(n), role)), ['fill', 'text', 'frame', 'wash'], `${n} ${role}`);
  }
});

test('before the tokens load a surface draws nothing', () => {
  assert.deepEqual(surfaceStyle(null, 'card'), { fill: 'transparent', text: 'transparent', frame: { width: 0, color: 'transparent' }, wash: 0 });
});

test('margins are the ui face at 12 px as written, with no rules under them', () => {
  assert.deepEqual(marginStyle(artboard), { font: 'Maple Mono', size: 12, caps: false, tracking: 0 });
});

test('a restyle swaps the fill, text and frame it names and keeps the rest (m21 lease warning)', () => {
  const style = surfaceStyle(artboard, 'island');
  assert.deepEqual(restyled(style, null), style);
  assert.deepEqual(restyled(style, { fill: '#B4380B' }), Object.assign({}, style, { fill: '#B4380B' }));
  assert.deepEqual(restyled(style, { frame: { width: 2, color: '#3D5AFE' } }).frame, { width: 2, color: '#3D5AFE' });
});

// A panel floats over the desk as a floating window does: on the paper, 97% so a window under it reads only as a shade, inside a 1 px edge of the accent fading into the paper.
test('a card on the desk tokens is 97% paper inside the accent edge every floating window wears', async () => {
  const { deskTokens } = await import('./voice.mjs');
  for (const t of [artboard, mocha]) {
    const s = surfaceStyle(deskTokens(t), 'card');
    assert.equal(s.fill, `#F7${t.color.paper.slice(1).toUpperCase()}`);
    assert.deepEqual(s.frame, { width: 1, color: t.niri.edge.from, gradient: { from: t.niri.edge.from, to: t.niri.edge.to } });
    assert.equal(s.text, deskTokens(t).color.ink);
    assert.equal(s.wash, 0.72);
  }
  assert.deepEqual(surfaceStyle(artboard, 'card').frame, { width: 1, color: artboard.niri.border_inactive }, 'a card off the desk keeps its quiet frame');
  assert.equal(surfaceStyle(deskTokens(artboard), 'island').frame.gradient, undefined, 'an island is no card');
});

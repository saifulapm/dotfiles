import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme } from './theme.mjs';
import { surfaceStyle, marginStyle, restyled } from './surface.mjs';

const load = (name) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8')));
const paper = load('paper');
const artboard = load('artboard');
const blueprint = load('blueprint');

test('Paper: a square ink card with a hard 6,6 ink shadow over a 0.72 wash', () => {
  assert.deepEqual(surfaceStyle(paper, 'card'), {
    fill: '#FAF6EC',
    text: '#1C1915',
    frame: { width: 1.5, color: '#1C1915' },
    corner: { radius: 0, chamfer: 0 },
    shadow: { kind: 'hard', x: 6, y: 6, blur: 0, spread: 0, color: '#1C1915', alpha: 1 },
    wash: 0.72,
    misregistered: false,
    handles: false,
    ticks: false,
  });
});

test('Paper: the island is ink with a misregistered vermilion shadow at 3,3', () => {
  assert.deepEqual(surfaceStyle(paper, 'island'), {
    fill: '#1C1915',
    text: '#F1E9D8',
    frame: { width: 0, color: '#1C1915' },
    corner: { radius: 0, chamfer: 0 },
    shadow: { kind: 'hard', x: 3, y: 3, blur: 0, spread: 0, color: '#C8381E', alpha: 1 },
    wash: 0.72,
    misregistered: true,
    handles: false,
    ticks: false,
  });
});

test('Artboard: a white round card, accent outline, long soft shadow, label and handles', () => {
  assert.deepEqual(surfaceStyle(artboard, 'card'), {
    fill: '#FFFFFF',
    text: '#15171B',
    frame: { width: 1.5, color: '#3D5AFE' },
    corner: { radius: 14, chamfer: 0 },
    shadow: { kind: 'soft', x: 0, y: 32, blur: 64, spread: -12, color: '#15171B', alpha: 0.28 },
    wash: 0.62,
    misregistered: false,
    handles: true,
    ticks: false,
  });
});

test('Artboard: the island is an ink pill with a soft shadow', () => {
  assert.deepEqual(surfaceStyle(artboard, 'island'), {
    fill: '#15171B',
    text: '#E4E6EA',
    frame: { width: 0, color: '#15171B' },
    corner: { radius: 17, chamfer: 0 },
    shadow: { kind: 'soft', x: 0, y: 12, blur: 32, spread: -6, color: '#15171B', alpha: 0.45 },
    wash: 0.62,
    misregistered: false,
    handles: false,
    ticks: false,
  });
});

test('Blueprint: a chamfered card with a 1 px cyan stroke, a cyan glow and ticks', () => {
  assert.deepEqual(surfaceStyle(blueprint, 'card'), {
    fill: '#0A1526',
    text: '#D6F4F8',
    frame: { width: 1, color: '#7FE3F0' },
    corner: { radius: 0, chamfer: 12 },
    shadow: { kind: 'glow', x: 0, y: 0, blur: 14, spread: 0, color: '#7FE3F0', alpha: 0.28 },
    wash: 0.72,
    misregistered: false,
    handles: false,
    ticks: true,
  });
});

test('Blueprint: the island is a chamfered surface box with the cyan stroke and glow', () => {
  assert.deepEqual(surfaceStyle(blueprint, 'island'), {
    fill: '#0A1526',
    text: '#D6F4F8',
    frame: { width: 1, color: '#7FE3F0' },
    corner: { radius: 0, chamfer: 10 },
    shadow: { kind: 'glow', x: 0, y: 0, blur: 8, spread: 0, color: '#7FE3F0', alpha: 0.35 },
    wash: 0.72,
    misregistered: false,
    handles: false,
    ticks: false,
  });
});

test('a specimen card draws its island as a chip at half size: the island look without the card signatures', () => {
  const w = (t) => surfaceStyle(t, 'chip');
  assert.deepEqual([w(paper).fill, w(paper).text, w(paper).shadow, w(paper).corner, w(paper).misregistered], [
    '#1C1915', '#F1E9D8', { kind: 'hard', x: 2, y: 2, blur: 0, spread: 0, color: '#C8381E', alpha: 1 }, { radius: 0, chamfer: 0 }, true,
  ]);
  assert.deepEqual([w(artboard).fill, w(artboard).shadow, w(artboard).corner], [
    '#15171B', { kind: 'soft', x: 0, y: 4, blur: 10, spread: -3, color: '#15171B', alpha: 0.4 }, { radius: 8, chamfer: 0 },
  ]);
  assert.deepEqual([w(blueprint).fill, w(blueprint).frame, w(blueprint).shadow, w(blueprint).corner], [
    '#0A1526', { width: 1, color: '#7FE3F0' }, { kind: 'glow', x: 0, y: 0, blur: 4, spread: 0, color: '#7FE3F0', alpha: 0.35 }, { radius: 0, chamfer: 5 },
  ]);
  assert.deepEqual([paper, artboard, blueprint].map((t) => [w(t).handles, w(t).ticks]), [[false, false], [false, false], [false, false]]);
});

test('the look follows the primitives, not the name', () => {
  const mix = Object.assign({}, paper, { name: 'mix', primitive: Object.assign({}, paper.primitive, { corner: 'cut', frame: 'none' }) });
  const s = surfaceStyle(mix, 'card');
  assert.deepEqual([s.corner, s.frame, s.shadow.kind, s.handles, s.ticks], [
    { radius: 0, chamfer: 12 },
    { width: 1.5, color: '#C8381E' },
    'hard',
    true,
    true,
  ]);
});

test('before the tokens load a surface draws nothing', () => {
  const s = surfaceStyle(null, 'card');
  assert.deepEqual([s.fill, s.frame.width, s.shadow.kind, s.wash, s.handles, s.ticks], ['transparent', 0, 'none', 0, false, false]);
  assert.equal(marginStyle(null).rules, false);
});

test('margins: caps and bracket voices are 11 px uppercase, over ink rules where the frame is ink; plain is 12 px as written', () => {
  assert.deepEqual(marginStyle(paper), { font: 'Maple Mono', size: 11, caps: true, tracking: 1.32, rules: true });
  assert.deepEqual(marginStyle(artboard), { font: 'Maple Mono', size: 12, caps: false, tracking: 0, rules: false });
  assert.deepEqual(marginStyle(blueprint), { font: 'Maple Mono', size: 11, caps: true, tracking: 1.32, rules: false });
});

test('a restyle swaps the fill, text, frame and shadow colour it names and keeps the rest (m21 lease warning)', () => {
  const base = { fill: 'a', text: 'b', frame: { width: 0, color: 'c' }, corner: { radius: 17, chamfer: 0 }, shadow: { kind: 'glow', color: 'd', alpha: 0.35 } };
  assert.equal(restyled(base, null), base);
  const r = restyled(base, { fill: 'F', frame: { width: 1.5, color: 'R' }, glow: 'G' });
  assert.deepEqual([r.fill, r.text, r.frame, r.corner, r.shadow.color, r.shadow.alpha], ['F', 'b', { width: 1.5, color: 'R' }, base.corner, 'G', 0.35]);
  const h = restyled(Object.assign({ handles: false }, base), { handles: true, handleFill: 'W' });
  assert.deepEqual([h.handles, h.handleFill], [true, 'W']);
});

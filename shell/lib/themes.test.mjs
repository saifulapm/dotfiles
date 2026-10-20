import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme } from './theme.mjs';
import { step, summary, windowLook, terminalLines, swatches, specimenMargins } from './themes.mjs';

const load = (name) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8')));
const paper = load('paper');
const artboard = load('artboard');
const blueprint = load('blueprint');

const names = ['paper', 'artboard', 'blueprint'];

test('step moves the cursor by one name and stops at the ends', () => {
  assert.equal(step(names, 'paper', 1), 'artboard');
  assert.equal(step(names, 'blueprint', -1), 'artboard');
  assert.equal(step(names, 'blueprint', 1), 'blueprint');
  assert.equal(step(names, 'paper', -1), 'paper');
});

test('summary names the mode, frame and shadow', () => {
  assert.equal(summary({ mode: 'light', primitive: { frame: 'ink', shadow: 'hard-offset' } }), 'light · ink · hard shadow');
  assert.equal(summary({ mode: 'dark', primitive: { frame: 'glow', shadow: 'none' } }), 'dark · glow · no shadow');
  assert.equal(summary({ mode: 'light', primitive: { frame: 'none', shadow: 'soft' } }), 'light · no frame · soft shadow');
});

test('a specimen window is framed as niri frames it: Paper ink then muted, hard 2,2 shadows', () => {
  assert.deepEqual(windowLook(paper, true), { fill: '#FAF6EC', frame: { width: 1, color: '#1C1915' }, shadow: { x: 2, y: 2, blur: 0, color: '#ff1C1915' }, radius: 0 });
  assert.deepEqual(windowLook(paper, false).frame, { width: 1, color: '#6A6052' });
  assert.equal(windowLook(paper, false).shadow.color, '#ff6A6052');
});

test('Artboard rings only the focused window in blue, rounds both, and shades the other at 0.75 as niri does', () => {
  assert.deepEqual(windowLook(artboard, true), { fill: '#FFFFFF', frame: { width: 1.5, color: '#3D5AFE' }, shadow: { x: 0, y: 9, blur: 20, color: '#2e15171B' }, radius: 6 });
  assert.deepEqual(windowLook(artboard, false).frame, { width: 0, color: 'transparent' });
  assert.equal(windowLook(artboard, false).shadow.color, '#2315171B');
});

test('Blueprint frames the focused window cyan with its glow, the other #2E5A72 with none', () => {
  assert.deepEqual(windowLook(blueprint, true), { fill: '#0A1526', frame: { width: 1, color: '#7FE3F0' }, shadow: { x: 0, y: 0, blur: 9, color: '#407FE3F0' }, radius: 0 });
  assert.deepEqual(windowLook(blueprint, false).frame, { width: 1, color: '#2E5A72' });
  assert.equal(windowLook(blueprint, false).shadow.color, '#00000000');
});

test('a theme without niri shadow keys draws its specimen windows with none', () => {
  const flat = { ...paper, niri: { gaps: 16, border: 1, blur: false } };
  assert.equal(windowLook(flat, true).shadow, null);
});

test('the terminal reads four lines in the ANSI colours: blue path, red prompt, green pass, yellow hash', () => {
  const lines = terminalLines(blueprint);
  assert.equal(lines.length, 4);
  assert.deepEqual(lines.map((l) => l.map((r) => r.text).join('')), [
    '~/S/g/dotfiles ❯ just test', '✓ 42 passed · 0.9 s', '~/S/g/dotfiles ❯ git log -1', 'a1e9e71 blueprint on the shelf',
  ]);
  assert.deepEqual([lines[0][0].color, lines[0][1].color, lines[1][0].color, lines[3][0].color], ['#6CB4FF', '#FF6B6B', '#8FE3A6', '#FFB547']);
});

test('the palette strip is ink, ANSI 1 to 6 and the paper', () => {
  assert.deepEqual(swatches(paper), ['#1C1915', '#C8381E', '#3D6B3A', '#A86A12', '#2C4A9A', '#7A3E7A', '#2F6F6A', '#F1E9D8']);
  assert.deepEqual(swatches(blueprint), ['#D6F4F8', '#FF6B6B', '#8FE3A6', '#FFB547', '#6CB4FF', '#C7A2FF', '#7FE3F0', '#0C1A2E']);
});

test('the specimen margins read one scene in each voice: 03 — FOOT, Page 03 / foot, [03] FOOT', () => {
  const read = (t) => { const m = specimenMargins(t); return [m.number + m.tail, m.goal + m.date, m.rules]; };
  assert.deepEqual(read(paper), ['03 — FOOT · ~', 'SHIP V2 · 3D — SUN 18 OCT', true]);
  assert.deepEqual(read(artboard), ['Page 03 / foot — ~', 'Ship v2 · 3d  Sun 18 Oct', false]);
  assert.deepEqual(read(blueprint), ['[03] FOOT — ~', 'SHIP V2 T−3D · 2026-10-18', false]);
  assert.equal(specimenMargins(blueprint).goalColor, '#FFB547');
});

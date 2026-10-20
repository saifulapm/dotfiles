import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme } from './theme.mjs';
import { step, jump, previewSwitch, cardName, tagline, pickerLook, windowLook, terminalLines, swatches, specimenMargins } from './themes.mjs';

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

test('each card names its theme in its own typeface and voice', () => {
  assert.deepEqual([paper, artboard, blueprint].map((t) => { const n = cardName(t); return [n.text, n.font, n.size, n.weight]; }), [
    ['Paper', 'Instrument Serif', 26, 400],
    ['Artboard', 'Maple Mono', 16, 700],
    ['BLUEPRINT', 'Maple Mono', 14, 700],
  ]);
});

test('each card sums up its primitives in its own voice', () => {
  assert.deepEqual([paper, artboard, blueprint].map((t) => tagline(t).text), ['grain, ink, a hard shadow', 'Dots · soft shadow · round', 'GRID // GLOW // CUT']);
  assert.equal(tagline(paper).italic, true);
});

test('Paper dresses the picker: a serif header, three on the shelf, a vermilion 2 px cursor with a 4 px hard shadow, IN USE', () => {
  const l = pickerLook(paper);
  assert.deepEqual([l.header(3, 'paper').title, l.header(3, 'paper').sub, l.header(3, 'paper').right], ['Themes', 'three on the shelf', 'PAPER IN USE']);
  assert.equal(l.header(4, 'paper').sub, 'four on the shelf');
  assert.deepEqual([l.cursor.border, l.cursor.shadow.kind, l.cursor.shadow.x, l.cursor.shadow.color], [{ width: 2, color: '#C8381E' }, 'hard', 4, '#C8381E']);
  assert.equal(l.tag(true, false).text, 'IN USE');
  assert.equal(l.tag(false, true), null);
  assert.deepEqual(l.legend(3).map((k) => `${k.key} ${k.word}`), ['J/K CHOOSE', '1–3 JUMP', '↵ APPLY']);
  assert.equal(l.number(0), '');
});

test('Artboard dresses the picker: Themes · 3 themes, a white tile outlined 1.5 px blue, Current and a return badge', () => {
  const l = pickerLook(artboard);
  assert.deepEqual([l.header(3, 'artboard').title, l.header(3, 'artboard').sub], ['Themes', '3 themes']);
  assert.deepEqual([l.cursor.fill, l.cursor.border], ['#FFFFFF', { width: 1.5, color: '#3D5AFE' }]);
  assert.equal(l.tile.fill, '#F6F7F9');
  assert.deepEqual([l.tag(true, true).text, l.tag(false, true).text, l.tag(false, false)], ['Current', '↵', null]);
  assert.deepEqual(l.legend(3).map((k) => `${k.key} ${k.word}`), ['j/k choose', '1–3 jump', '↵ apply']);
  assert.equal(l.chips, true);
});

test('Blueprint dresses the picker: THEMES // 3 SHEETS, ACTIVE: BLUEPRINT, numbered sheets, [ACTIVE] and [↵]', () => {
  const l = pickerLook(blueprint);
  const h = l.header(3, 'blueprint');
  assert.deepEqual([h.title + h.sub, h.right], ['THEMES // 3 SHEETS', 'ACTIVE: BLUEPRINT']);
  assert.deepEqual([0, 1, 2].map(l.number), ['01', '02', '03']);
  assert.deepEqual([l.tag(true, false).text, l.tag(false, true).text], ['[ACTIVE]', '[↵]']);
  assert.deepEqual([l.cursor.border, l.cursor.ticks], [{ width: 1, color: '#7FE3F0' }, true]);
  assert.deepEqual(l.legend(3).map((k) => `${k.key} ${k.word}`), ['[J/K] CHOOSE', '[1–3] JUMP', '[↵] APPLY']);
  assert.equal(l.esc, '[ESC]');
});

test('a specimen window is framed as niri frames it: Paper ink then muted, hard 2,2 shadows', () => {
  assert.deepEqual(windowLook(paper, true), { fill: '#FAF6EC', frame: { width: 1, color: '#1C1915' }, shadow: { x: 2, y: 2, blur: 0, color: '#1C1915' }, radius: 0 });
  assert.deepEqual(windowLook(paper, false).frame, { width: 1, color: '#6A6052' });
  assert.equal(windowLook(paper, false).shadow.color, '#6A6052');
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

test('niri border and ring colours with alpha read as Qt reads them, #AARRGGBB', () => {
  const t = { ...blueprint, niri: { ...blueprint.niri, border_inactive: '#2E5A7280' } };
  assert.equal(windowLook(t, false).frame.color, '#802E5A72');
  const r = { ...artboard, niri: { ...artboard.niri, ring_color: '#3D5AFE80' } };
  assert.equal(windowLook(r, true).frame.color, '#803D5AFE');
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

test('before the theme loads the picker still has a whole look', () => {
  const l = pickerLook(null);
  assert.deepEqual([l.header(3, '').title, l.tag(true, false).text, l.cursor.border.width, l.legend(3).length], ['Themes', 'IN USE', 2, 3]);
});

test('a digit jumps to its card, and one with no card changes nothing', () => {
  const names = ['paper', 'artboard', 'blueprint'];
  assert.equal(jump(names, 'paper', 3), 'blueprint');
  assert.equal(jump(names, 'blueprint', 1), 'paper');
  assert.equal(jump(names, 'artboard', 7), 'artboard');
  assert.equal(jump(names, 'artboard', 0), 'artboard');
});

test('a card plays its own theme switch in miniature: Paper slides, Artboard zooms, Blueprint scans, in 220 ms', () => {
  assert.deepEqual([paper, artboard, blueprint].map((t) => previewSwitch(t.primitive.motion, 1)), [
    { kind: 'slide', ms: 220 }, { kind: 'zoom', ms: 220 }, { kind: 'scan', ms: 220 },
  ]);
  assert.deepEqual(previewSwitch('ease', 1), { kind: 'cut', ms: 0 });
  assert.deepEqual(previewSwitch('linear', 10), { kind: 'scan', ms: 2200 });
});

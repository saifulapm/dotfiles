import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { launcherLook, MODES } from './launcher-look.mjs';

const theme = (name) => parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8'));
const look = (name) => launcherLook(theme(name));

test('Paper keeps its launcher: an ink cursor row with a red marker, a 34 px serif query and an italic serif detail', () => {
  const p = look('paper');
  assert.deepEqual([p.cursor.fill, p.cursor.marker, p.slot], ['#1C1915', '#C8381E', 'marker']);
  assert.deepEqual([p.query.font, p.query.size], ['Instrument Serif', 34]);
  assert.deepEqual([p.detail.font, p.detail.size, p.detail.italic], ['Instrument Serif', 16, true]);
  assert.deepEqual([p.label.kind, p.label.text('apps'), p.count(3)], ['chip', 'APPS', '3 FOUND']);
});

test("Artboard's launcher follows its board: a search glyph, an Apps pill, icon tiles and a tinted rounded cursor with a return badge", () => {
  const a = look('artboard');
  assert.equal(a.prompt.search, true);
  assert.deepEqual([a.query.font, a.query.size], ['Maple Mono', 20]);
  assert.deepEqual([a.label.kind, a.label.text('apps'), a.label.fill, a.label.color], ['pill', 'Apps', '#EEF1FF', '#3D5AFE']);
  assert.deepEqual([a.slot, a.tile.size, a.tile.fill], ['icon', 32, '#F2F3F6']);
  assert.deepEqual([a.cursor.fill, a.cursor.text, a.cursor.radius, a.cursor.badge], ['#EEF1FF', '#2638C9', 10, '↵']);
  assert.deepEqual([a.name.size, a.name.weight, a.cursor.weight, a.detail.size, a.detail.color], [15, 500, 600, 12, '#5F6672']);
  assert.equal(a.count(3), '');
});

test("Blueprint's launcher follows its board: LAUNCH // <mode>, n MATCHES, a > prompt, numbered uppercase rows and a cyan cursor", () => {
  const b = look('blueprint');
  assert.deepEqual([b.label.kind, b.label.text('apps'), b.count(3)], ['header', 'LAUNCH // APPS', '3 MATCHES']);
  assert.deepEqual([b.prompt.text, b.prompt.color, b.caret], ['>', '#7FE3F0', 'block']);
  assert.deepEqual([b.slot, b.number(0), b.number(7)], ['number', '01', '08']);
  assert.deepEqual([b.title('Font Viewer'), b.detailText('e-book reader')], ['FONT VIEWER', 'E-BOOK READER']);
  assert.deepEqual([b.cursor.fill, b.cursor.text], ['#7FE3F0', '#0A1526']);
});

test('only Blueprint draws its rules dashed', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => look(n).rule.dashed), [false, false, true]);
});

test('every mode is named in the theme voice', () => {
  assert.deepEqual(MODES, ['apps', 'windows', 'clipboard', 'emoji', 'calculator', 'commands']);
  assert.equal(look('paper').label.text('clipboard'), 'CLIPBOARD');
  assert.equal(look('artboard').label.text('clipboard'), 'Clipboard');
  assert.equal(look('blueprint').label.text('clipboard'), 'LAUNCH // CLIPBOARD');
  for (const n of ['paper', 'artboard', 'blueprint']) for (const m of MODES) assert.ok(look(n).label.text(m), `${n} ${m}`);
});

test('the apps legend names the five prefixes in each voice, then the moving keys in one short tail', () => {
  const keys = (n) => look(n).legend('apps').keys.map((k) => `${k.key} ${k.word}`);
  assert.deepEqual(keys('paper'), ['W WINDOWS', 'V CLIPBOARD', ': EMOJI', '= CALC', '> COMMANDS']);
  assert.deepEqual(keys('artboard'), ['w windows', 'v clipboard', ': emoji', '= calculator', '> commands']);
  assert.deepEqual(keys('blueprint'), ['[W] WINDOWS', '[V] CLIPBOARD', '[:] EMOJI', '[=] CALC', '[>] COMMANDS']);
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => look(n).legend('apps').tail), ['J/K · ↵ · ESC', 'j/k · ↵ · esc', 'J/K · ↵ · ESC']);
  assert.equal(look('artboard').legend('apps').chips, true);
  assert.equal(look('blueprint').legend('apps').chips, false);
});

test('inside a mode the legend keeps to the moving keys and drops the prefixes', () => {
  for (const n of ['paper', 'artboard', 'blueprint']) {
    const l = look(n).legend('clipboard');
    assert.deepEqual(l.keys, [], n);
    assert.match(l.tail, /j\/k.*↵.*esc/i, n);
  }
});

test('the legend reads as one line for the state and the footer checks', () => {
  assert.equal(look('blueprint').legendLine('apps'), '[W] WINDOWS  [V] CLIPBOARD  [:] EMOJI  [=] CALC  [>] COMMANDS  J/K · ↵ · ESC');
});

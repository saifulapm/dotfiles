import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { notesLook, tagColour, keyLine, KEYS, EMPTY_KEYS } from './notes-look.mjs';

const theme = (name) => parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8'));

test('the selected card is outlined in the theme accent in all three themes', () => {
  for (const [name, accent] of [['paper', '#C8381E'], ['artboard', '#3D5AFE'], ['blueprint', '#7FE3F0']]) {
    const look = notesLook(theme(name));
    assert.equal(look.card(true, false).border.color, accent, name);
    assert.ok(look.card(true, false).border.width >= 1, name);
    assert.notEqual(look.card(false, false).border.color, accent, name);
  }
});

test('each theme draws its own header, as its design does', () => {
  assert.deepEqual([notesLook(theme('paper')).title.text, notesLook(theme('paper')).title.font], ['Notes', 'Instrument Serif']);
  assert.equal(notesLook(theme('blueprint')).title.text, 'NOTES');
  assert.equal(notesLook(theme('artboard')).title.bold, true);
  assert.equal(notesLook(theme('paper')).sectionLabel('inbox'), '§ inbox');
  assert.equal(notesLook(theme('artboard')).sectionLabel('inbox'), '# inbox');
  assert.equal(notesLook(theme('blueprint')).sectionLabel('inbox'), '§INBOX');
});

test('the six tags take their colours from the theme ANSI colours', () => {
  const t = theme('paper');
  assert.deepEqual(['red', 'orange', 'yellow', 'green', 'blue', 'purple'].map((g) => tagColour(t, g)), [t.color.ansi[1], t.color.ansi[3], t.color.ansi[11], t.color.ansi[2], t.color.ansi[4], t.color.ansi[5]]);
});

test('the key line reads in each theme voice', () => {
  assert.equal(keyLine(theme('paper'), [['␣', 'done'], ['/', 'search']]), '␣ DONE  / SEARCH');
  assert.equal(keyLine(theme('artboard'), [['␣', 'done'], ['/', 'search']]), '␣ done  / search');
  assert.equal(keyLine(theme('blueprint'), [['␣', 'done'], ['/', 'search']]), '[␣] DONE  [/] SEARCH');
});

test('the empty line names section and attach, and the strip names every list key', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) assert.match(keyLine(theme(name), EMPTY_KEYS), /section.*attach/i);
  assert.deepEqual(KEYS.map((k) => k[0]), ['j/k', '␣', '↵', '1–6', 'v', 'm', '⇧M', 'y', '⇧Y', '⌃Y', '⌃V', 'd', '/', '⌃K', 'esc']);
});

test('Blueprint draws its rules and done cards dashed, the others solid', () => {
  const bp = notesLook(theme('blueprint'));
  assert.equal(bp.rule.dashed, true);
  assert.equal(bp.card(false, true).dashed, true);
  assert.equal(bp.card(true, true).dashed, false);
  for (const name of ['paper', 'artboard']) assert.equal(notesLook(theme(name)).card(false, true).dashed, false);
});

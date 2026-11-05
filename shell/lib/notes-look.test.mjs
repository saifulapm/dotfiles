import { test } from 'node:test';
import assert from 'node:assert/strict';
import { notesLook, tagColour, keyLine, keyPairs, KEYS, EMPTY_KEYS, tabLabels, cardMeta, SHELF_PLACEHOLDER } from './notes-look.mjs';
import { schemeTokens } from './colorscheme-file.mjs';

const artboard = schemeTokens('artboard');
const gruvbox = schemeTokens('gruvbox-dark');

test("the selected card is outlined 2 px in the scheme's accent, the rest 1 px in ink, a done one in the line colour", () => {
  for (const t of [artboard, gruvbox]) {
    const look = notesLook(t);
    assert.deepEqual(look.card(true, false), { fill: t.color.surface, border: { width: 2, color: t.color.accent } }, t.name);
    assert.deepEqual(look.card(false, false).border, { width: 1, color: t.color.ink }, t.name);
    assert.deepEqual(look.card(false, true).border, { width: 1, color: t.color.line }, t.name);
  }
});

test('the header reads Notes in bold, the sections as # names, square', () => {
  const look = notesLook(artboard);
  assert.deepEqual([look.title.text, look.title.font, look.title.bold], ['Notes', 'Maple Mono', true]);
  assert.equal(look.sectionLabel('inbox'), '# inbox');
  assert.equal(look.radius, 0);
  assert.equal(look.keyHint, '⌃K');
});

test('the six tags take their colours from the scheme ANSI colours', () => {
  const t = gruvbox;
  assert.deepEqual(['red', 'orange', 'yellow', 'green', 'blue', 'purple'].map((g) => tagColour(t, g)), [t.color.ansi[1], t.color.ansi[3], t.color.ansi[11], t.color.ansi[2], t.color.ansi[4], t.color.ansi[5]]);
});

test('the key line reads its keys and words as written', () => {
  assert.equal(keyLine([['␣', 'done'], ['/', 'search']]), '␣ done  / search');
});

test('the empty line names section and attach, and the strip names every list key', () => {
  assert.match(keyLine(EMPTY_KEYS), /section.*attach/);
  assert.deepEqual(KEYS.map((k) => k[0]), ['j/k', '␣', '↵', '1–6', 'v', 'm', '⇧M', 'y', '⇧Y', '⌃Y', '⌃V', 'd', '/', '⌃K', 'esc']);
});

test('the key strip lays out whole pairs, so a key never wraps away from its word', () => {
  assert.deepEqual(keyPairs([['m', 'merge'], ['⇧M', 'move']]), ['m merge', '⇧M move']);
  assert.equal(keyLine(KEYS), keyPairs(KEYS).join('  '));
});

test('the key strip and the header are not ruled off', () => {
  const look = notesLook(artboard);
  assert.equal(look.strip, undefined);
  assert.equal(look.rule, undefined);
});

test('the tab row lists the sections in order, Shelf pinned first and the current one marked', () => {
  const look = notesLook(artboard);
  assert.deepEqual(tabLabels(look, ['Shelf', 'inbox', 'work'], 'inbox'), [
    { name: 'Shelf', label: 'Shelf', pinned: true, current: false },
    { name: 'inbox', label: '# inbox', pinned: false, current: true },
    { name: 'work', label: '# work', pinned: false, current: false },
  ]);
  assert.equal(tabLabels(look, ['Shelf'], 'Shelf')[0].current, true);
});

test('a section name typed or synced is one line and bidi-safe in the tab row', () => {
  const [tab] = tabLabels(notesLook(artboard), ['a\nb‮c\u0085d'], 'x');
  assert.equal(tab.label, '# a b⟨U+202E⟩c d');
});

test('a card says its time and kind: text, image, or the file type', () => {
  const at = new Date(2026, 9, 18, 13, 55).getTime();
  const note = (attachments) => ({ createdAt: at, attachments });
  const file = (name, mime) => ({ name, mime, size: 1, sha256: 'x' });
  assert.equal(cardMeta(note([])), '13:55 · text');
  assert.equal(cardMeta(note([file('p.png', 'image/png')])), '13:55 · image');
  assert.equal(cardMeta(note([file('ferry-ticket.pdf', 'application/pdf')])), '13:55 · PDF');
  assert.equal(cardMeta(note([file('blob', 'application/octet-stream')])), '13:55 · file');
});

test('the Shelf composer says how to paste and drop', () => {
  assert.equal(SHELF_PLACEHOLDER, '⌃V paste · drop files or images here · ↵ save text');
});

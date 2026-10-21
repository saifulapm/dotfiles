import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { listLook } from './voice.mjs';
import { parseEntries, passRows, segments, passKeys, copiedText, failedText, pathTag, deleteText, changedText, LENGTH } from './pass.mjs';

const theme = (name) => parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8'));
const listed = 'web/github.com\t1\nmail/icloud\t0\nweb/gitlab.com\t0\nnote\t0\n';

test("dots-pass list's lines become entries with their folder, leaf and OTP tag, in its order", () => {
  assert.deepEqual(parseEntries(listed + '\n'), [
    { name: 'web/github.com', folder: 'web/', leaf: 'github.com', otp: true },
    { name: 'mail/icloud', folder: 'mail/', leaf: 'icloud', otp: false },
    { name: 'web/gitlab.com', folder: 'web/', leaf: 'gitlab.com', otp: false },
    { name: 'note', folder: '', leaf: 'note', otp: false },
  ]);
  assert.deepEqual(parseEntries(''), []);
});

test('typing filters by subsequence, keeping the recent-first order, and marks the matched letters', () => {
  const rows = passRows(parseEntries(listed), 'ghb');
  assert.deepEqual(rows.map((r) => r.name), ['web/github.com']);
  assert.deepEqual(rows[0].hits, [4, 7, 9]);
  assert.deepEqual(passRows(parseEntries(listed), 'gl').map((r) => r.name), ['web/gitlab.com']);
  assert.deepEqual(passRows(parseEntries(listed), 'web').map((r) => r.name), ['web/github.com', 'web/gitlab.com']);
});

test('matching ignores case and the edges of the query, and an empty query lists everything unmarked', () => {
  assert.deepEqual(passRows(parseEntries(listed), ' GHB ').map((r) => r.name), ['web/github.com']);
  const all = passRows(parseEntries(listed), '');
  assert.equal(all.length, 4);
  assert.deepEqual(all[0].hits, []);
});

test('a row draws as runs: the folder muted, matched letters underlined', () => {
  const [row] = passRows(parseEntries(listed), 'ghb');
  assert.deepEqual(segments(row), [
    { text: 'web/', folder: true, hit: false },
    { text: 'g', folder: false, hit: true },
    { text: 'it', folder: false, hit: false },
    { text: 'h', folder: false, hit: true },
    { text: 'u', folder: false, hit: false },
    { text: 'b', folder: false, hit: true },
    { text: '.com', folder: false, hit: false },
  ]);
  const [w] = passRows(parseEntries(listed), 'w');
  assert.deepEqual(segments(w).slice(0, 2), [
    { text: 'w', folder: true, hit: true },
    { text: 'eb/', folder: true, hit: false },
  ]);
});

test("a name's bidi controls never reach the drawn row", () => {
  const [row] = passRows(parseEntries('web/‮good\t0\n'), 'go');
  assert.deepEqual(segments(row), [
    { text: 'web/', folder: true, hit: false },
    { text: 'go', folder: false, hit: true },
    { text: 'od', folder: false, hit: false },
  ]);
});

test("the key strip reads the board's keys in each theme's voice", () => {
  const strip = (name) => passKeys(listLook(theme(name))).map((k) => `${k.key} ${k.word}`.trim()).join(' · ');
  assert.equal(strip('artboard'), '↵ copy · o otp · s show · n new · e edit · d delete · q qr · esc');
  assert.equal(strip('paper'), '↵ COPY · O OTP · S SHOW · N NEW · E EDIT · D DELETE · Q QR · ESC');
  assert.equal(strip('blueprint'), '[↵] COPY · [O] OTP · [S] SHOW · [N] NEW · [E] EDIT · [D] DELETE · [Q] QR · [ESC]');
});

test("the island's notice says what was copied, and a failure says why in one line", () => {
  assert.equal(copiedText('copy'), 'Copied · clears in 45s');
  assert.equal(copiedText('otp'), 'OTP copied · clears in 45s');
  assert.equal(failedText('dots-pass: could not decrypt web/github.com\n'), 'Not copied · could not decrypt web/github.com');
  assert.equal(failedText(''), 'Not copied');
});

test("a new entry's path is tagged new or exists, and a path pass could not save is tagged nothing", () => {
  const entries = parseEntries(listed);
  assert.equal(pathTag(entries, 'web/linear.app'), 'new');
  assert.equal(pathTag(entries, ' web/github.com '), 'exists');
  for (const bad of ['', '  ', 'web/', '/web/x', 'web//x', '../x', 'a/./b', 'a\tb']) assert.equal(pathTag(entries, bad), '', bad);
});

test('a new password starts at 24 characters, from 8 to 128', () => {
  assert.deepEqual(LENGTH, { start: 24, min: 8, max: 128 });
});

test("the delete question names the entry on one line, with the theme's y and n", () => {
  const artboard = listLook(theme('artboard'));
  assert.deepEqual(deleteText(artboard, 'web/linear\n.app'), { question: 'Delete web/linear .app?', keys: [{ key: 'y', word: 'yes' }, { key: 'n', word: 'no' }] });
  assert.deepEqual(deleteText(listLook(theme('blueprint')), 'x').keys, [{ key: '[Y]', word: 'YES' }, { key: '[N]', word: 'NO' }]);
});

test("the island's word after a change: done, saved but not pushed, or why not", () => {
  assert.equal(changedText('insert', 'web/linear.app', 0, ''), 'Saved · web/linear.app');
  assert.equal(changedText('delete', 'web/linear.app', 0, ''), 'Deleted · web/linear.app');
  assert.equal(changedText('qr-save', 'web/github.com', 0, ''), 'OTP saved · web/github.com');
  assert.equal(changedText('insert', 'web/x', 3, 'dots-pass: saved, not pushed\n'), 'Saved · not pushed');
  assert.equal(changedText('insert', 'web/x', 1, 'dots-pass: web/x exists\n'), 'Not saved · web/x exists');
  assert.equal(changedText('qr-save', 'web/x', 1, 'dots-pass: the qr code is not an otpauth code\n'), 'OTP not saved · the qr code is not an otpauth code');
});

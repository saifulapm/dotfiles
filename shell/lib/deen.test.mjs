import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as D from './deen.mjs';

test('the five tabs run in the boards\' order, and Tab past the last comes back to Read', () => {
  assert.deepEqual(D.TABS, ['read', 'memorise', 'duas', 'hadith', 'prayer']);
  assert.equal(D.tabAfter('read', 1), 'memorise');
  assert.equal(D.tabAfter('prayer', 1), 'read');
  assert.equal(D.tabAfter('read', -1), 'prayer');
  assert.equal(D.tabAfter('nowhere', 1), 'read');
});

test('each tab is named as the boards name it', () => {
  assert.deepEqual(D.TABS.map(D.tabName), ['Read', 'Memorise', 'Duas', 'Hadith', 'Prayer']);
});

test('the backend\'s answer is its one JSON object, or null for anything else', () => {
  assert.deepEqual(D.answer('{"surahs":[]}\n'), { surahs: [] });
  assert.equal(D.answer(''), null);
  assert.equal(D.answer('thread main panicked'), null);
  assert.equal(D.answer('[1]'), null);
});

test('outside text is one line without controls or bidi overrides, and Arabic keeps its harakat', () => {
  assert.equal(D.oneLine('Low\nTide‮\u001b Radio'), 'Low Tide Radio');
  assert.equal(D.oneLine('a⁦b⁩c‪d'), 'abcd');
  assert.equal(D.oneLine('بِاسْـمِكَ اللّهُـمَّ\nأَمـوتُ'), 'بِاسْـمِكَ اللّهُـمَّ أَمـوتُ');
});

test('Arabic draws in Amiri where it is installed, else in Noto Naskh Arabic', () => {
  assert.equal(D.arabicFamily(['Maple Mono', 'Amiri', 'Noto Naskh Arabic']), 'Amiri');
  assert.equal(D.arabicFamily(['Maple Mono', 'Noto Naskh Arabic']), 'Noto Naskh Arabic');
});

test('Bangla draws in Noto Serif Bengali on Paper, and in Noto Sans Bengali on Artboard and Blueprint', () => {
  assert.equal(D.bengaliFamily('caps'), 'Noto Serif Bengali');
  assert.equal(D.bengaliFamily('plain'), 'Noto Sans Bengali');
  assert.equal(D.bengaliFamily('bracket'), 'Noto Sans Bengali');
});

test('a tab without its Bangla data says how to get it', () => {
  assert.equal(D.NO_DATA, 'Bangla data is not on this machine: gh auth login, then dots update');
});

test('deen has no Bangla data when it cannot read the Quran text or the duas', () => {
  assert.equal(D.noData({ error: 'cannot read the Quran text at /home/s/.local/share/deen/quran.json: No such file or directory (os error 2)' }), true);
  assert.equal(D.noData({ error: 'cannot read the duas at /home/s/.local/share/deen/duas.json: No such file or directory (os error 2)' }), true);
});

test('a surah whose words carry no Bangla meaning is no Bangla data, but one with some is', () => {
  const ayahs = [{ a: 1, ar: 'إِنَّ' }];
  assert.equal(D.noData({ ayahs, words: [[{ i: 1, en: 'Indeed' }], [{ i: 1, en: 'with', bn: '' }]] }), true);
  assert.equal(D.noData({ ayahs, words: [[{ i: 1, en: 'Indeed', bn: 'নিশ্চয়ই' }]] }), false);
  assert.equal(D.noData({ ayahs, words: [[{ i: 1, en: 'Indeed' }], [{ i: 1, en: 'with', bn: 'সাথে' }]] }), false);
});

test('any other failure, or no answer, is not missing Bangla data', () => {
  assert.equal(D.noData(null), false);
  assert.equal(D.noData({ error: 'no state dir' }), false);
  assert.equal(D.noData({ due: [{ reference: '1:2', ayah: { ar: 'ٱلْحَمْدُ', en: 'Praise' } }] }), false);
  assert.equal(D.noData({ chapters: [{ n: 1, en: 'When waking up' }], duas: [] }), false);
});

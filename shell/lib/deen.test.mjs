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

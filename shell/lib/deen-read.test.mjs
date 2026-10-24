import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as R from './deen-read.mjs';

// Al-Fatihah's word counts: ayah 1 has 4 words, ayah 2 has 4, ayah 3 has 2.
const lengths = [4, 4, 2];

test('h steps to the next word, and past an ayah\'s last word to the next ayah\'s first', () => {
  assert.deepEqual(R.stepWord(lengths, { a: 1, i: 1 }, 1), { a: 1, i: 2 });
  assert.deepEqual(R.stepWord(lengths, { a: 1, i: 4 }, 1), { a: 2, i: 1 });
  assert.deepEqual(R.stepWord(lengths, { a: 3, i: 2 }, 1), { a: 3, i: 2 });
});

test('l steps back, and before an ayah\'s first word to the previous ayah\'s last', () => {
  assert.deepEqual(R.stepWord(lengths, { a: 2, i: 3 }, -1), { a: 2, i: 2 });
  assert.deepEqual(R.stepWord(lengths, { a: 3, i: 1 }, -1), { a: 2, i: 4 });
  assert.deepEqual(R.stepWord(lengths, { a: 1, i: 1 }, -1), { a: 1, i: 1 });
});

test('j and k move a whole ayah and put the cursor on its first word', () => {
  assert.deepEqual(R.stepAyah(lengths, { a: 1, i: 3 }, 1), { a: 2, i: 1 });
  assert.deepEqual(R.stepAyah(lengths, { a: 3, i: 2 }, -1), { a: 2, i: 1 });
  assert.deepEqual(R.stepAyah(lengths, { a: 3, i: 2 }, 1), { a: 3, i: 1 });
  assert.deepEqual(R.stepAyah(lengths, { a: 1, i: 2 }, -1), { a: 1, i: 1 });
});

test('the heading line counts the ayat, names Meccan Makki and Medinan Madani, and gives the juz', () => {
  assert.equal(R.headingText({ n: 36, en: 'Yaseen' }), 'Surah 36 · Yaseen');
  assert.equal(R.metaText('caps', { count: 83, type: 'Meccan' }, 22), '83 ayat · Makki · juz 22');
  assert.equal(R.metaText('plain', { count: 286, type: 'Medinan' }, 1), '286 ayat · Madani · juz 1');
  assert.equal(R.metaText('caps', { count: 7, type: 'Meccan' }, null), '7 ayat · Makki');
  assert.equal(R.metaText('bracket', { count: 7, type: 'Meccan' }, 1), '7 AYAT · MAKKI · JUZ 1');
});

test('the bar reads the word\'s transliteration, place and root, leaving out a root it has none of', () => {
  assert.equal(R.wordLine('caps', { i: 3, tr: 'rabbi', root: 'ر ب ب' }, 2), 'rabbi · ayah 2, word 3 · root ر ب ب');
  assert.equal(R.wordLine('plain', { i: 1, tr: 'ya-seen', root: null }, 1), 'ya-seen · ayah 1, word 1');
  assert.equal(R.wordLine('bracket', { i: 3, tr: 'rabbi', root: 'ر ب ب' }, 2), 'RABBI · AYAH 2, WORD 3 · ROOT ر ب ب');
  assert.equal(R.hearHint('caps'), '↵ hear this word');
  assert.equal(R.hearHint('bracket'), '[↵] HEAR THIS WORD');
});

const surahs = [
  { n: 1, ar: 'سُورَةُ ٱلْفَاتِحَةِ', en: 'Al-Faatiha', tr: 'The Opening' },
  { n: 3, ar: 'سُورَةُ آلِ عِمۡرَانَ', en: 'Aal-i-Imraan', tr: 'The Family of Imraan' },
  { n: 13, ar: 'سُورَةُ الرَّعۡدِ', en: 'Ar-Ra\'d', tr: 'The Thunder' },
  { n: 36, ar: 'سُورَةُ يسٓ', en: 'Yaseen', tr: 'Yaseen' },
  { n: 103, ar: 'سُورَةُ العَصۡرِ', en: 'Al-Asr', tr: 'The Declining Day, Epoch' },
];

test('the picker finds a surah by number, the exact one first', () => {
  assert.deepEqual(R.surahsMatching(surahs, '36').map((s) => s.n), [36]);
  assert.deepEqual(R.surahsMatching(surahs, '3').map((s) => s.n), [3, 13, 36, 103]);
  assert.deepEqual(R.surahsMatching(surahs, '').map((s) => s.n), [1, 3, 13, 36, 103]);
});

test('the picker finds a surah by its English name, its meaning or its Arabic name without harakat', () => {
  assert.deepEqual(R.surahsMatching(surahs, 'yas').map((s) => s.n), [36]);
  assert.deepEqual(R.surahsMatching(surahs, 'thunder').map((s) => s.n), [13]);
  assert.deepEqual(R.surahsMatching(surahs, 'يس').map((s) => s.n), [36]);
  assert.deepEqual(R.surahsMatching(surahs, ' opening ').map((s) => s.n), [1]);
});

test('an answer is a surah to read only when it carries ayat and their words', () => {
  assert.equal(R.readable(null), false);
  assert.equal(R.readable({ error: 'no quran.json' }), false);
  assert.equal(R.readable({ surah: { n: 1 }, ayahs: [], words: [] }), false);
  assert.equal(R.readable({ surah: { n: 1 }, ayahs: [{ a: 1 }], words: [[{ i: 1 }]] }), true);
});

test('m says the surah went into Memorise, or why it did not', () => {
  assert.equal(R.addedText({ added: 83, already: 0, enrolled: 83 }, 'Yaseen'), 'Yaseen added to Memorise');
  assert.equal(R.addedText({ error: 'no state dir' }, 'Yaseen'), 'no state dir');
  assert.equal(R.addedText(null, 'Yaseen'), 'Yaseen could not be added to Memorise');
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as U from './deen-duas.mjs';

const real = JSON.parse(readFileSync(new URL('../../dev/deen/dua-list.json', import.meta.url), 'utf8'));
const book = U.parseList(real);

// The crate's normalise.rs: marks and tatweel go, alef carriers fold to alef.
const letters = (s) => s.replace(/[ً-ٰٟۖ-ۭـ࣓-ࣿ]/g, '').replace(/[آأإٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه');

test('the backend\'s list is read chapter by chapter with each chapter\'s own duas, and the book\'s count', () => {
  assert.equal(book.count, 268);
  assert.equal(book.chapters.length, 134);
  assert.equal(book.chapters[0].name, 'When waking up');
  assert.equal(book.chapters[0].duas.length, 4);
  const sleeping = book.chapters.find((c) => c.name === 'Before sleeping');
  assert.equal(sleeping.duas.length, 13);
  assert.equal(sleeping.duas[6].id, '105');
});

test('dua 105 keeps the book\'s tatweel and matches the plan\'s letters once normalised', () => {
  const d = book.chapters.find((c) => c.name === 'Before sleeping').duas[6];
  assert.ok(d.ar.includes('ـ'));
  assert.equal(letters(d.ar), 'باسمك اللهم اموت واحيا');
  assert.ok(d.tr.startsWith('Bismika Allāhumma amūtu wa aḥyā'));
  assert.ok(d.en.startsWith('In Your Name, O Allah, I die and I live'));
});

test('a chapter name is one line without controls, and a dua\'s text loses controls and overrides', () => {
  assert.equal(book.chapters[132].name, 'Forged chapter [31m');
  const b = U.parseList({ chapters: [{ n: 1, en: 'A', ar: 'ا' }], duas: [{ id: '9', chapter: 1, ar: 'x\u202ey', tr: 'a\nb\u001bc', en: 'e', ref: 'r' }] });
  assert.deepEqual(b.chapters[0].duas[0], { id: '9', ar: 'xy', tr: 'a b c', en: 'e', ref: 'r' });
});

test('no list, an error or no chapters is no book', () => {
  assert.equal(U.parseList(null), null);
  assert.equal(U.parseList({ error: 'no duas.json' }), null);
  assert.equal(U.parseList({ chapters: [], duas: [] }), null);
});

test('the heading is the book and its count', () => {
  assert.equal(U.heading(268), 'Hisn al-Muslim · 268 duas');
});

test('chapters filter by English or Arabic name, any case', () => {
  const names = (q) => U.filter(book.chapters, q).map((c) => c.name);
  assert.deepEqual(names('SLEEPING'), ['Before sleeping']);
  assert.deepEqual(names('ذكار النوم'), ['Before sleeping']);
  assert.deepEqual(names('forged'), ['Forged chapter [31m']);
  assert.equal(names('').length, 134);
  assert.deepEqual(names('zzz'), []);
});

test('the cursor stops at the ends, and n wraps to the first dua', () => {
  assert.equal(U.step(0, -1, 5), 0);
  assert.equal(U.step(3, 1, 5), 4);
  assert.equal(U.step(4, 1, 5), 4);
  assert.equal(U.step(0, 1, 0), 0);
  assert.equal(U.nextDua(0, 13), 1);
  assert.equal(U.nextDua(12, 13), 0);
});

test('the pane\'s head counts the dua within its chapter', () => {
  assert.equal(U.duaHead(7, 13), 'dua 7 of 13');
});

test('the source is the dua\'s ref then the book and its id', () => {
  assert.equal(U.sourceLine({ id: '1', ref: 'Al-Bukhari 11/113' }), 'Al-Bukhari 11/113 · Hisn al-Muslim 1');
  assert.equal(U.sourceLine({ id: '2', ref: '' }), 'Hisn al-Muslim 2');
});

test('a copy is four lines: Arabic, transliteration, meaning, source', () => {
  const d = { id: '105', ar: 'ع', tr: 'T', en: 'E', ref: 'R' };
  assert.equal(U.copyText(d), 'ع\nT\nE\nR · Hisn al-Muslim 105');
});

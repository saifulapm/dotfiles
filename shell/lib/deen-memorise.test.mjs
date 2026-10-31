import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as M from './deen-memorise.mjs';

const read = (name) => JSON.parse(readFileSync(fileURLToPath(new URL(`../../dev/deen/${name}.json`, import.meta.url)), 'utf8'));
const deck = () => read('hifz-due---limit-40');

test('a next review under an hour reads in minutes, under a day in hours, then days', () => {
  assert.equal(M.nextText('caps', 600), '10 min');
  assert.equal(M.nextText('caps', 60), '1 min');
  assert.equal(M.nextText('caps', 3600), '1 hour');
  assert.equal(M.nextText('caps', 7200), '2 hours');
  assert.equal(M.nextText('caps', 86400), '1 day');
  assert.equal(M.nextText('caps', 259200), '3 days');
});

test('a next review past 60 days reads in months', () => {
  assert.equal(M.nextText('caps', 60 * 86400), '60 days');
  assert.equal(M.nextText('caps', 61 * 86400), '2 months');
  assert.equal(M.nextText('caps', 90 * 86400), '3 months');
});

test('Blueprint writes the next review in capitals', () => {
  assert.equal(M.nextText('bracket', 600), '10 MIN');
  assert.equal(M.nextText('bracket', 259200), '3 DAYS');
});

test('a card shows the first half of its words, at least one and at most five', () => {
  assert.deepEqual(M.firstWords('ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ'), { shown: 'ٱلْحَمْدُ لِلَّهِ', hidden: 2 });
  assert.deepEqual(M.firstWords('قُلْ'), { shown: 'قُلْ', hidden: 0 });
  assert.deepEqual(M.firstWords('أ ب ج'), { shown: 'أ', hidden: 2 });
  assert.deepEqual(M.firstWords('١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩ ١٠ ١١ ١٢'), { shown: '١ ٢ ٣ ٤ ٥', hidden: 7 });
  assert.deepEqual(M.firstWords('  أ\n ب  '), { shown: 'أ', hidden: 1 });
});

test('the deck opens on the first due card with the backend counts', () => {
  const s = M.openDeck(deck());
  assert.equal(s.left, 7);
  assert.equal(s.fresh, 2);
  assert.equal(M.current(s).reference, '1:2');
  assert.deepEqual(M.current(s).next, { again: 600, hard: 86400, good: 86400, easy: 86400 });
});

test('an answer that is not a deck opens nothing', () => {
  assert.equal(M.openDeck(null), null);
  assert.equal(M.openDeck({ error: 'no data' }), null);
  assert.equal(M.openDeck({ due: 'x' }), null);
});

test('a rated card leaves the list and the count drops by one, a new card also the new count', () => {
  const s = M.rate(M.openDeck(deck()), read('hifz-grade-1:2-good'));
  assert.equal(M.current(s).reference, '1:3');
  assert.deepEqual([s.left, s.fresh, s.rated], [6, 1, 1]);
  assert.equal(s.nextIn, 86400);
});

test('Again also removes the card, and the soonest return is kept', () => {
  const a = M.rate(M.openDeck(deck()), read('hifz-grade-1:2-good'));
  const b = M.rate(a, read('hifz-grade-1:3-again'));
  assert.equal(M.current(b).reference, '1:4');
  assert.deepEqual([b.left, b.fresh], [5, 0]);
  assert.equal(b.nextIn, 600);
});

test('a failed grade changes nothing', () => {
  const s = M.openDeck(deck());
  assert.equal(M.rate(s, null), null);
  assert.equal(M.rate(s, { error: 'x' }), null);
});

test('skip moves the card to the end and keeps the count', () => {
  const s = M.skip(M.openDeck(deck()));
  assert.equal(M.current(s).reference, '1:3');
  assert.equal(s.left, 7);
  assert.equal(s.cards[6].reference, '1:2');
});

test('after the last card nothing is current', () => {
  let s = M.openDeck({ due: [deck().due[0]], total_due: 1, new_due: 1 });
  s = M.rate(s, read('hifz-grade-1:2-good'));
  assert.equal(M.current(s), null);
  assert.equal(s.left, 0);
});

test('Paper and Artboard write the count and its line in sentence case, Blueprint in capitals', () => {
  assert.equal(M.words('caps').due(7), '7 due today');
  assert.equal(M.words('plain').line(2, 1, 7), '2 new · 1 of 7 · self-graded, nothing is recorded');
  assert.equal(M.words('bracket').due(7), '7 DUE TODAY');
  assert.equal(M.words('bracket').line(2, 1, 7), '2 NEW · 1 OF 7 · SELF-GRADED, NOTHING IS RECORDED');
});

test('each theme writes the card badge and the rating head as its board does', () => {
  assert.equal(M.words('caps').badge(false), '1 · RECALL');
  assert.equal(M.words('plain').badge(true), '2 · revealed');
  assert.equal(M.words('bracket').badge(false), '[1 · RECALL]');
  assert.equal(M.words('caps').ask, 'HOW DID IT GO · NEXT REVIEW');
  assert.equal(M.words('plain').ask, 'How did it go · next review');
  assert.deepEqual(M.words('bracket').grades, ['AGAIN', 'HARD', 'GOOD', 'EASY']);
  assert.deepEqual(M.words('plain').grades, ['again', 'hard', 'good', 'easy']);
});

test('the done line names the next review when one is known', () => {
  assert.equal(M.words('plain').done(600), 'Done for today. Next review in 10 min.');
  assert.equal(M.words('plain').done(null), 'Done for today.');
  assert.equal(M.words('plain').nothing, 'Nothing due today. Press m in Read to add a surah to Memorise.');
});

test('a surah is named by its Bangla name, else by its number in Bangla digits', () => {
  const surahs = read('api-surahs');
  assert.equal(M.surahName(surahs, 94), 'সূরা আশ-শারহ');
  assert.equal(M.surahName(null, 112), 'সূরা ১১২');
});

test('a card\'s heading gives its Bangla surah name and its reference in Bangla digits', () => {
  assert.equal(M.words('caps').heading('সূরা আশ-শারহ', 94, 6), 'সূরা আশ-শারহ ৯৪:৬');
  assert.equal(M.words('bracket').heading('সূরা আল-ফাতিহা', 1, 2), 'সূরা আল-ফাতিহা ১:২');
});

// The test files are left out: they name the very tools this test looks for.
test('nothing in Deen records audio or opens the microphone', () => {
  const shell = fileURLToPath(new URL('..', import.meta.url));
  const files = readdirSync(shell)
    .filter((f) => /^Deen.*\.qml$/.test(f) || f === 'deen.qml')
    .map((f) => `${shell}/${f}`)
    .concat(
      readdirSync(`${shell}/lib`)
        .filter((f) => /^deen.*\.mjs$/.test(f) && !f.endsWith('.test.mjs'))
        .map((f) => `${shell}/lib/${f}`),
    );
  assert.ok(files.length >= 8, `read ${files.length} files`);
  const banned = /pw-record|parecord|arecord|voxtype|whisper|MediaDevices|AudioInput|CaptureSession|MediaRecorder/;
  for (const f of files) assert.doesNotMatch(readFileSync(f, 'utf8'), banned, f);
});

// An Again card is due in 10 minutes, so a page left open on "done" must ask for the deck again then (review of m36).
test('the page knows when its first rated card comes back, and reloads once that time has passed', () => {
  const t = 1_700_000_000_000;
  assert.equal(M.backAt(null, t, { due_in_days: 600 / 86400 }), t + 600_000);
  assert.equal(M.backAt(t + 600_000, t + 1000, { due_in_days: 1 }), t + 600_000);
  assert.equal(M.backAt(null, t, null), null);
  assert.equal(M.reloadNow('done', t + 600_000, t + 599_999), false);
  assert.equal(M.reloadNow('done', t + 600_000, t + 600_000), true);
  assert.equal(M.reloadNow('card', t + 600_000, t + 700_000), false);
  assert.equal(M.reloadNow('done', null, t), false);
});

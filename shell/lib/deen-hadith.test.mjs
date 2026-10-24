import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as H from './deen-hadith.mjs';

test('a progress event reads its percent, size, speed and time left in whole MB', () => {
  assert.deepEqual(H.progress({ done: 38000000, total: 123880000, rate: 6200000 }), {
    fraction: 38000000 / 123880000,
    percent: '31%',
    size: '38 of 124 MB',
    speed: '6.2 MB/s',
    left: 'about 14 s',
  });
  assert.equal(H.progress({ done: 10000000, total: 123880000, rate: 1000000 }).left, 'about 2 min');
});

test('a progress event with no rate yet draws no speed or time left', () => {
  const p = H.progress({ done: 0, total: 123880000, rate: 0 });
  assert.equal(p.percent, '0%');
  assert.equal(p.speed, '');
  assert.equal(p.left, '');
});

test('the corpus dir reads with the home dir as ~', () => {
  assert.equal(H.tilde('/home/saiful/.local/share/deen/hadith', '/home/saiful'), '~/.local/share/deen/hadith');
  assert.equal(H.tilde('/srv/deen/hadith', '/home/saiful'), '/srv/deen/hadith');
  assert.equal(H.tilde('/home/saifulx/deen', '/home/saiful'), '/home/saifulx/deen');
});

test("each line of fetch's output is one event, and anything else is none", () => {
  assert.deepEqual(H.event('{"event":"progress","done":1,"total":2,"rate":3}'), { event: 'progress', done: 1, total: 2, rate: 3 });
  assert.equal(H.event('curl: (6) could not resolve'), null);
  assert.equal(H.event('{"done":1}'), null);
});

test('the download moves from running to converting to done, and fails on an error or an exit before done', () => {
  let d = H.START;
  d = H.afterEvent(d, { event: 'progress', done: 20000000, total: 123880000, rate: 6200000 });
  assert.deepEqual(d, { phase: 'running', done: 20000000, total: 123880000, rate: 6200000, message: '' });
  assert.equal(H.afterEvent(d, { event: 'converting' }).phase, 'converting');
  const done = H.afterEvent(H.afterEvent(d, { event: 'converting' }), { event: 'done', total: 123880000 });
  assert.equal(done.phase, 'done');
  assert.equal(H.afterExit(done).phase, 'done');
  const cut = H.afterEvent(d, { event: 'error', message: 'the connection dropped', done: 38000000, total: 123880000 });
  assert.deepEqual(cut, { phase: 'failed', done: 38000000, total: 123880000, rate: 6200000, message: 'the connection dropped' });
  assert.deepEqual(H.afterExit(d), { phase: 'failed', done: 20000000, total: 123880000, rate: 6200000, message: '' });
});

test('a failure reads where it stopped and what is kept', () => {
  const cut = { phase: 'failed', done: 38000000, total: 123880000, rate: 0, message: 'the connection dropped' };
  assert.equal(H.failText(cut), 'The connection dropped at 38 of 124 MB. The part already saved is kept, so retrying carries on from there.');
  assert.equal(H.failText({ phase: 'failed', done: 38000000, total: 123880000, rate: 0, message: '' }), 'The download stopped at 38 of 124 MB. The part already saved is kept, so retrying carries on from there.');
  assert.equal(H.failText({ phase: 'failed', done: 0, total: 0, rate: 0, message: 'boom\n‮\u001b[2J' }), 'Boom [2J at 0 of 0 MB. The part already saved is kept, so retrying carries on from there.');
  assert.equal(H.mb(38000000), '38 MB');
});

test('collections draw by the boards’ names, and an unknown slug by the backend’s', () => {
  assert.equal(H.boardName('bukhari', 'Sahih al Bukhari'), 'Sahih al-Bukhari');
  assert.equal(H.boardName('abudawud', 'Sunan Abu Dawud'), 'Sunan Abi Dawud');
  assert.equal(H.boardName('dehlawi', 'Forty Hadith of Shah Waliullah Dehlawi'), '40 Hadith Shah Waliullah');
  assert.equal(H.boardName('darimi', 'Sunan ad-Darimi'), 'Sunan ad-Darimi');
});

test('grades: agreeing graders draw one, others each with their grader, and ungraded by collection', () => {
  const albani = { by: 'Al-Albani', grade: 'Sahih' };
  assert.equal(H.gradeText('abudawud', [albani, { by: 'Shuaib Al Arnaut', grade: 'Sahih' }]), 'Sahih');
  assert.equal(H.gradeText('abudawud', [albani, { by: 'Shuaib Al Arnaut', grade: 'Hasan' }]), 'Sahih (Al-Albani) · Hasan (Shuaib Al Arnaut)');
  assert.equal(H.gradeText('bukhari', null), 'Sahih');
  assert.equal(H.gradeText('muslim', []), 'Sahih');
  assert.equal(H.gradeText('nawawi', null), 'ungraded');
  assert.equal(H.gradeText('tirmidhi', [{ by: '', grade: 'Hasan' }]), 'Hasan');
});

test('grades handed over as a list model row, an array-like, still draw', () => {
  const rowGrades = { length: 2, 0: { by: 'Al-Albani', grade: 'Sahih' }, 1: { by: 'Shuaib Al Arnaut', grade: 'Hasan' } };
  assert.equal(H.gradeText('abudawud', rowGrades), 'Sahih (Al-Albani) · Hasan (Shuaib Al Arnaut)');
});

test("the narrator is split off the English's leading Narrated <name>:", () => {
  assert.deepEqual(H.narrator("Narrated 'Umar bin Al-Khattab: I heard Allah's Messenger"), { by: "'Umar bin Al-Khattab", body: "I heard Allah's Messenger" });
  assert.deepEqual(H.narrator('Narrated Ibn `Abbas:The people used to think'), { by: 'Ibn `Abbas', body: 'The people used to think' });
  assert.deepEqual(H.narrator('The Prophet said, "Actions are by intentions."'), { by: '', body: 'The Prophet said, "Actions are by intentions."' });
});

test('wrapped outside text keeps its lines but loses controls and bidi overrides', () => {
  assert.equal(H.wrapped('one\ntwo‮ three\u001b[2J⁦x'), 'one\ntwo three[2Jx');
});

test('the narrations sum every collection with a thousands comma', () => {
  assert.equal(H.narrations({ collections: [{ hadiths: 7589 }, { hadiths: 28923 }] }), '36,512');
  assert.equal(H.narrations({ collections: [{ hadiths: 40 }] }), '40');
  assert.equal(H.narrations(null), '');
});

test('a query runs as its words split on spaces with the limit, and an empty one runs none', () => {
  assert.deepEqual(H.searchArgs('  actions  intentions '), ['hadith', 'search', 'actions', 'intentions', '--limit', '40']);
  assert.equal(H.searchArgs('   '), null);
  assert.equal(H.resultsText(4), '4 results');
  assert.equal(H.resultsText(1), '1 result');
});

test('y copies the name and number, the Arabic, the English with its narrator and the url', () => {
  const hit = { collection: 'bukhari', name: 'Sahih al Bukhari', url: 'https://sunnah.com/bukhari:1', hadith: { n: '1', ar: 'إِنَّمَا', en: "Narrated 'Umar: Actions are by intentions." } };
  assert.equal(H.copyText(hit), "Sahih al-Bukhari 1\n\nإِنَّمَا\n\nActions are by intentions.\nNarrated by 'Umar\n\nhttps://sunnah.com/bukhari:1");
});

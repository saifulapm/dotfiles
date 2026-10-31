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

test('a failure reads where it stopped', () => {
  const cut = { phase: 'failed', done: 38000000, total: 123880000, rate: 0, message: 'the connection dropped' };
  assert.equal(H.failText(cut), 'The connection dropped at 38 of 124 MB.');
  assert.equal(H.failText({ phase: 'failed', done: 38000000, total: 123880000, rate: 0, message: '' }), 'The download stopped at 38 of 124 MB.');
  assert.equal(H.failText({ phase: 'failed', done: 0, total: 0, rate: 0, message: 'boom\n‮\u001b[2J' }), 'Boom [2J at 0 of 0 MB.');
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

test('the narrations sum every collection\'s narrations with text, with a thousands comma', () => {
  assert.equal(H.narrations({ collections: [{ hadiths: 7589, count: 7583 }, { hadiths: 28923, count: 28606 }] }), '36,189');
  assert.equal(H.narrations({ collections: [{ hadiths: 40, count: 40 }] }), '40');
  assert.equal(H.narrations(null), '');
});

test('a query runs as its words split on spaces with the limit, and an empty one runs none', () => {
  assert.deepEqual(H.searchArgs('  actions  intentions '), ['hadith', 'search', '--limit', '40', '--', 'actions', 'intentions']);
  // A typed word that starts with a dash is a word to find, never one of deen's flags; a pasted newline splits words as a space does.
  assert.deepEqual(H.searchArgs('--collection muslim'), ['hadith', 'search', '--limit', '40', '--', '--collection', 'muslim']);
  assert.deepEqual(H.searchArgs('a\nb\tc'), ['hadith', 'search', '--limit', '40', '--', 'a', 'b', 'c']);
  assert.equal(H.searchArgs('   '), null);
  assert.equal(H.resultsText(4), '4 results');
  assert.equal(H.resultsText(1), '1 result');
});

test('y copies the name and number, the Arabic, the English with its narrator and the url', () => {
  const hit = { collection: 'bukhari', name: 'Sahih al Bukhari', url: 'https://sunnah.com/bukhari:1', hadith: { n: '1', ar: 'إِنَّمَا', en: "Narrated 'Umar: Actions are by intentions." } };
  assert.equal(H.copyText(hit), "Sahih al-Bukhari 1\n\nإِنَّمَا\n\nActions are by intentions.\nNarrated by 'Umar\n\nhttps://sunnah.com/bukhari:1");
});

const bukhari = { slug: 'bukhari', name: 'Sahih al Bukhari', bn: 'সহীহ বুখারী', hadiths: 7589, count: 7583 };
const n1bn = '‘আলক্বামাহ ইবনু ওয়াক্কাস আল-লায়সী (রহ.) হতে বর্ণিত।';
const listed = {
  collection: 'bukhari',
  bn: 'সহীহ বুখারী',
  name: 'Sahih al Bukhari',
  book: { n: 1, bn: 'ওহীর সূচনা', en: 'Revelation', count: 7 },
  hadiths: [{ n: '1', ar: 'إِنَّمَا', en: "Narrated 'Umar: Actions are by intentions.", bn: n1bn, grades: [], book: 1, in_book: 1 }],
};

test('a collection row reads its Bangla name, the board’s English name and its count', () => {
  assert.equal(H.rowText(H.collectionRow(bukhari)), 'সহীহ বুখারী  Sahih al-Bukhari  7583');
  assert.deepEqual(H.collectionRow(bukhari).cells.map((c) => c.face), ['bn', 'en', 'count']);
});

test('a book row numbers it in Bangla digits beside its count, and book 0 draws without a number', () => {
  assert.equal(H.rowText(H.bookRow({ n: 1, bn: 'ওহীর সূচনা', en: 'Revelation', count: 7 })), '১. ওহীর সূচনা  7');
  assert.equal(H.rowText(H.bookRow({ n: 97, bn: 'তাওহীদ', en: 'Oneness', count: 192 })), '৯৭. তাওহীদ  192');
  assert.equal(H.rowText(H.bookRow({ n: 0, bn: 'অন্যান্য', en: '', count: 307 })), 'অন্যান্য  307');
});

test('a narration row is one line of its Bangla, or of its English under the English mark', () => {
  assert.deepEqual(H.narrationRow({ n: '1', bn: 'কাজ\nনিয়্যাত অনুযায়ী।', en: 'Narrated Umar: Actions' }), { english: false, cells: [{ text: 'কাজ নিয়্যাত অনুযায়ী।', face: 'bn' }] });
  const qudsi = H.narrationRow({ n: '1', en: 'Narrated Abu Hurairah: When Allah decreed the Creation' });
  assert.equal(qudsi.english, true);
  assert.equal(H.rowText(qudsi), 'English  When Allah decreed the Creation');
  assert.equal(H.narrationRow({ n: '1', bn: '', en: 'Forged' }).english, true);
});

test('a search hit row leads with its Bangla reference', () => {
  const hit = { collection: 'bukhari', bn: 'সহীহ বুখারী', hadith: { n: '1', bn: n1bn, en: 'x' } };
  assert.equal(H.rowText(H.hitRow(hit)), `সহীহ বুখারী ১  ${n1bn}`);
  assert.equal(H.rowText(H.hitRow({ collection: 'qudsi', bn: 'চল্লিশ হাদীসে কুদসী', hadith: { n: '12', en: 'Allah said' } })), 'চল্লিশ হাদীসে কুদসী ১২  English  Allah said');
});

test('a reference is the collection’s Bangla name and the number in Bangla digits', () => {
  assert.equal(H.reference('সহীহ বুখারী', '1'), 'সহীহ বুখারী ১');
  assert.equal(H.reference('সুনান আবূ দাউদ', '402.2'), 'সুনান আবূ দাউদ ৪০২.২');
  assert.equal(H.bnDigits(6114), '৬১১৪');
});

test('a listed narration opens as a hit with its collection, book and sunnah.com url', () => {
  assert.deepEqual(H.listHit(listed, listed.hadiths[0]), {
    collection: 'bukhari',
    name: 'Sahih al Bukhari',
    bn: 'সহীহ বুখারী',
    book: { n: 1, bn: 'ওহীর সূচনা', en: 'Revelation' },
    url: 'https://sunnah.com/bukhari:1',
    hadith: listed.hadiths[0],
  });
});

test('an opened narration draws its Arabic, Bangla and Bangla reference, and no English or grade', () => {
  assert.deepEqual(H.pane(H.listHit(listed, listed.hadiths[0])), {
    title: 'ওহীর সূচনা',
    ar: 'إِنَّمَا',
    text: n1bn,
    english: false,
    by: '',
    grade: '',
    reference: 'সহীহ বুখারী ১',
  });
});

test('a narration without Bangla draws its English, narrator and grade, still with the Bangla reference', () => {
  const hit = { collection: 'qudsi', name: 'Forty Hadith Qudsi', bn: 'চল্লিশ হাদীসে কুদসী', book: { n: 1, bn: 'চল্লিশ হাদীসে কুদসী', en: 'Forty Hadith Qudsi' }, hadith: { n: '1', ar: 'لَمَّا', en: 'Narrated Abu Hurairah: When Allah decreed\nthe Creation', grades: [] } };
  assert.deepEqual(H.pane(hit), {
    title: 'চল্লিশ হাদীসে কুদসী',
    ar: 'لَمَّا',
    text: 'When Allah decreed\nthe Creation',
    english: true,
    by: 'Abu Hurairah',
    grade: 'ungraded',
    reference: 'চল্লিশ হাদীসে কুদসী ১',
  });
});

test('Enter goes down a level, Esc back up keeping the cursor, and Esc on the collections closes', () => {
  let s = H.LEVELS;
  assert.deepEqual(s, [{ level: 'collections', cursor: 0 }]);
  assert.equal(H.up(s), null);
  s = H.withCursor(s, 3);
  s = H.down(s, { level: 'books', data: listed });
  assert.deepEqual(s.map((e) => [e.level, e.cursor]), [['collections', 3], ['books', 0]]);
  s = H.down(H.withCursor(s, 2), { level: 'narrations', data: listed });
  s = H.down(s, { level: 'narration' });
  assert.equal(H.listEntry(s).level, 'narrations');
  s = H.up(s);
  assert.equal(s[s.length - 1].level, 'narrations');
  s = H.up(H.up(s));
  assert.deepEqual(s, [{ level: 'collections', cursor: 3 }]);
});

test('/ opens search over any level once, and Esc from it returns to that level', () => {
  const books = H.down(H.LEVELS, { level: 'books', data: listed });
  const s = H.search(books);
  assert.equal(s[s.length - 1].level, 'search');
  assert.equal(H.search(s), s);
  assert.equal(H.listEntry(s).level, 'search');
  assert.deepEqual(H.up(s), books);
});

test('the heading names where the list is', () => {
  assert.equal(H.heading(H.LEVELS), 'Collections');
  const books = H.down(H.LEVELS, { level: 'books', data: { collection: 'bukhari', bn: 'সহীহ বুখারী', books: [] } });
  assert.equal(H.heading(books), 'সহীহ বুখারী');
  assert.equal(H.heading(H.down(books, { level: 'narrations', data: listed })), 'সহীহ বুখারী · ওহীর সূচনা');
  assert.equal(H.heading(H.search(books)), '');
});

test('a fetch that finds no deen-data is no data, any other failure is not', () => {
  const failed = (message) => H.afterEvent(H.START, { event: 'error', message, done: 0, total: 0 });
  assert.equal(H.noData(failed('cannot read the hadith editions at /home/s/.local/share/deen-data/hadith: run dots update, or set DEEN_SOURCES')), true);
  assert.equal(H.noData(failed('building the corpus failed: boom')), false);
  assert.equal(H.noData(H.START), false);
});

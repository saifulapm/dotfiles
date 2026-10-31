import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as U from './deen-duas.mjs';

const real = JSON.parse(readFileSync(new URL('../../dev/deen/dua-list.json', import.meta.url), 'utf8'));
const book = U.parseList(real);
const dua = (id) => book.chapters.flatMap((c) => c.duas).find((d) => d.id === id);

// The crate's normalise.rs: marks and tatweel go, alef carriers fold to alef.
const letters = (s) => s.replace(/[ً-ٰٟۖ-ۭـ࣓-ࣿ]/g, '').replace(/[آأإٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه');

// The book writes most য় and ড় as one code point (U+09DF, U+09DC), which an editor's NFC splits, so those and U+200C are escaped; 16's আল্লাহ্‌র holds a U+200C.
const meaning16 = 'আল্লাহ্\u200cর নামে (বের হচ্ছি)। আল্লাহর উপর ভরসা করলাম। আর আল্লাহর সাহায্য ছা\u09dcা (পাপ কাজ থেকে দূরে থাকার) কোনো উপা\u09df এবং (সৎকাজ করার) কোনো শক্তি কারো নেই';
const pron16 = 'বিসমিল্লাহি, তাও\u09dfাককালতু ‘আলাল্লা-হি, ও\u09dfালা হাওলা ও\u09dfালা কুও\u09dfাতা ইল্লা বিল্লাহ';
const pron229 = 'ইযা- সামি‘তুম নুবা-হালকিলা-বি ওয\u09bcানাহীক্বালহামীরি বিল্লাইলি ফাতা‘আউওয\u09bcাযূ বিল্লা-হি মিনহুন্ন, ফাইন্নাহুন্না ইয\u09bcারাইনা মা- লা- তারাউন';

test('the backend\'s list is read chapter by chapter with each chapter\'s own duas, and the book\'s count', () => {
  assert.equal(book.count, 268);
  assert.equal(book.chapters.length, 134);
  assert.equal(book.chapters[0].en, 'When waking up');
  assert.equal(book.chapters[0].duas.length, 4);
  const sleeping = book.chapters.find((c) => c.en === 'Before sleeping');
  assert.equal(sleeping.duas.length, 13);
  assert.equal(sleeping.duas[6].id, '105');
});

test('chapters are named in Bangla from the book', () => {
  const name = (n) => book.chapters.find((c) => c.n === n).name;
  assert.equal(name(1), 'ঘুম থেকে জেগে উঠার সম\u09dfের যিক্\u200cরসমূহ');
  assert.equal(name(10), 'বা\u09dcি থেকে বের হও\u09dfার সম\u09dfের যিক্\u200cর');
  assert.equal(name(49), 'রোগী দেখতে গি\u09dfে তার জন্য দো‘আ');
  assert.equal(name(50), 'রোগী দেখতে যাও\u09dfার ফযিলত');
});

test('dua 105 keeps the book\'s tatweel and matches the plan\'s letters once normalised', () => {
  const d = book.chapters.find((c) => c.en === 'Before sleeping').duas[6];
  assert.ok(d.ar.includes('ـ'));
  assert.equal(letters(d.ar), 'باسمك اللهم اموت واحيا');
});

test('dua 16 reads the book\'s pronunciation, Bangla meaning and Bangla reference, none marked English', () => {
  const d = dua('16');
  assert.equal(d.pron, pron16);
  assert.ok(d.meaning.endsWith('কোনো শক্তি কারো নেই'));
  assert.equal(d.meaning, meaning16);
  assert.equal(d.meaningEnglish, false);
  assert.equal(d.source, 'আবূ দাউদ ৪/৩২৫, নং ৫০৯৫; তিরমিযী ৫/৪৯০, ৩৪২৬। আরও দেখুন, সহীহুত তিরমিযী, ৩/১৫১');
  assert.equal(d.sourceEnglish, false);
});

test('dua 229, which the Bangla book lacks, reads its English meaning and reference, each marked English', () => {
  const d = dua('229');
  assert.equal(d.pron, pron229);
  assert.equal(d.meaning, 'When you hear a dog barking or a donkey braying in the night, then seek refuge in Allah from them, for surely they have seen what you see not.');
  assert.equal(d.meaningEnglish, true);
  assert.equal(d.source, 'Abu Dawud 4/327, Ahmad 3/306. Al-Albani graded it authentic in Sahih Abu Dawud 3/961.');
  assert.equal(d.sourceEnglish, true);
});

test('dua 236 reads its Bangla meaning though one segment\'s pronunciation is the engine\'s', () => {
  const d = dua('236');
  assert.ok(d.meaning.startsWith('নিশ্চ\u09dfই সাফা ও মারও\u09dfা'));
  assert.equal(d.meaningEnglish, false);
});

test('a chapter name is one line without controls, and a dua\'s text loses controls and overrides', () => {
  assert.equal(book.chapters[132].name, 'জাল অধ্যায\u09bc [31m');
  const b = U.parseList({ chapters: [{ n: 1, en: 'A', ar: 'ا', bn: 'অ' }], duas: [{ id: '9', chapter: 1, ar: 'x‮y', tr: 't', en: 'e', ref: 'r', bn: 'ক\nখ\u001bগ', bn_pron: 'প‮', bn_ref: 'স' }] });
  assert.deepEqual(b.chapters[0].duas[0], { id: '9', ar: 'xy', pron: 'প', meaning: 'ক খ গ', meaningEnglish: false, source: 'স', sourceEnglish: false });
});

test('no list, an error or no chapters is no book', () => {
  assert.equal(U.parseList(null), null);
  assert.equal(U.parseList({ error: 'no duas.json' }), null);
  assert.equal(U.parseList({ chapters: [], duas: [] }), null);
});

test('a list whose chapters carry no Bangla name is data older than this deen: no book, and no data', () => {
  const old = { ...real, chapters: real.chapters.map(({ bn, ...c }) => c) };
  assert.equal(U.parseList(old), null);
  assert.equal(U.noData(old), true);
  assert.equal(U.noData(real), false);
  assert.equal(U.noData({ error: 'cannot read the duas at /x/duas.json: No such file or directory (os error 2)' }), true);
  assert.equal(U.noData({ error: 'no duas.json' }), false);
});

test('the heading is the book and its count', () => {
  assert.equal(U.heading(268), 'Hisn al-Muslim · 268 duas');
});

test('chapters filter by Bangla, English or Arabic name, any case', () => {
  const names = (q) => U.filter(book.chapters, q).map((c) => c.en);
  const numbers = (q) => U.filter(book.chapters, q).map((c) => c.n);
  assert.deepEqual(numbers('বের'), [7, 10, 14, 30, 81]);
  assert.deepEqual(numbers('বের হও\u09dfার সম\u09dfের'), [10]);
  assert.deepEqual(numbers('Leaving'), [7, 10, 14]);
  // য় typed as য plus nukta finds the book's one code point, and a name typed without its ZWNJ finds the one with it.
  assert.deepEqual(numbers('বের হও\u09af\u09bcার সম\u09af\u09bcের'), [10]);
  assert.deepEqual(numbers('বা\u09a1\u09bcি থেকে'), [10]);
  assert.equal(U.filter(book.chapters, 'যিক্র').length, U.filter(book.chapters, 'যিক্\u200cর').length);
  assert.ok(U.filter(book.chapters, 'যিক্র').length > 1);
  assert.deepEqual(names('LEAVING THE HOME'), ['Remembrance when leaving the home']);
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
  assert.equal(U.duaHead(7, 13, false), 'dua 7 of 13');
  assert.equal(U.duaHead(7, 13, true), 'DUA 7 OF 13');
});

test('a copy is the four lines drawn: Arabic, pronunciation, meaning, source', () => {
  assert.equal(U.copyText(dua('16')), [
    'بِسْمِ اللهِ ، تَوَكَّلْـتُ عَلى اللهِ وَلا حَوْلَ وَلا قُـوَّةَ إِلاّ بِالله',
    pron16,
    meaning16,
    'আবূ দাউদ ৪/৩২৫, নং ৫০৯৫; তিরমিযী ৫/৪৯০, ৩৪২৬। আরও দেখুন, সহীহুত তিরমিযী, ৩/১৫১',
  ].join('\n'));
  assert.equal(U.copyText(dua('229')), [
    // 229's Arabic puts shadda before fatha, an order NFC would swap, so it comes from the fixture as deen sends it.
    real.duas.find((d) => d.id === '229').ar,
    pron229,
    'When you hear a dog barking or a donkey braying in the night, then seek refuge in Allah from them, for surely they have seen what you see not.',
    'Abu Dawud 4/327, Ahmad 3/306. Al-Albani graded it authentic in Sahih Abu Dawud 3/961.',
  ].join('\n'));
});

test('a long dua draws smaller so it fits the pane, the board\'s 46 px for a short one', () => {
  assert.equal(U.arabicSize('x'.repeat(40)), 46);
  assert.equal(U.arabicSize('x'.repeat(100)), 34);
  assert.equal(U.arabicSize('x'.repeat(240)), 26);
  assert.equal(U.arabicSize('x'.repeat(1800)), 20);
});

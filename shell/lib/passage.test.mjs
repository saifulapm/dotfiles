import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as P from './passage.mjs';

const LIST = ['ayah 94:6', 'ayah 2:152', 'hadith bukhari:1', 'dua 1', 'dua 75a', 'quote Action is the foundational key to all success. — Pablo Picasso'].join('\n');

test('each kind of line parses to its kind and reference', () => {
  assert.deepEqual(P.parse(LIST).entries, [
    { kind: 'ayah', ref: '94:6', line: 1 },
    { kind: 'ayah', ref: '2:152', line: 2 },
    { kind: 'hadith', ref: 'bukhari:1', line: 3 },
    { kind: 'dua', ref: '1', line: 4 },
    { kind: 'dua', ref: '75a', line: 5 },
    { kind: 'quote', text: 'Action is the foundational key to all success.', author: 'Pablo Picasso', line: 6 },
  ]);
});

test('a quote holding the dash twice splits at the last one', () => {
  const [q] = P.parse("quote Whether you think you can, or you think you can't — you're right. — Henry Ford").entries;
  assert.equal(q.text, "Whether you think you can, or you think you can't — you're right.");
  assert.equal(q.author, 'Henry Ford');
});

test('blank lines, comments and trailing spaces are not part of an entry', () => {
  const { entries, bad } = P.parse('# ayat\n\nayah 94:6   \n  # indented\ndua 16 # Hisn 16\n');
  assert.deepEqual(entries, [
    { kind: 'ayah', ref: '94:6', line: 3 },
    { kind: 'dua', ref: '16', line: 5 },
  ]);
  assert.deepEqual(bad, []);
});

test('a line that fits no kind is bad, with its number and why', () => {
  assert.deepEqual(P.parse('ayah 94:5-6\nhadith abudawud:1\npoem roses\nquote no author\nayah 94:6').bad, [
    { line: 1, text: 'ayah 94:5-6', why: 'not one ayah' },
    { line: 2, text: 'hadith abudawud:1', why: 'not Bukhari or Muslim' },
    { line: 3, text: 'poem roses', why: 'no such kind' },
    { line: 4, text: 'quote no author', why: 'no author' },
  ]);
});

test('the day is the local date counted from 1970-01-01', () => {
  assert.equal(P.dayOf('2026-11-01'), 20758);
  assert.equal(P.dayOf('1970-01-01'), 0);
  assert.equal(P.dateOf(20760), '2026-11-03');
  // 00:30 at +06 is still the evening before in UTC, but the day is the local one.
  assert.equal(P.today(new Date(2026, 10, 3, 0, 30)), '2026-11-03');
});

test('a date that is not YYYY-MM-DD, or no such day, has no day number', () => {
  for (const s of ['', '2026-11-3', '2026-02-30', '2026-13-01', 'today', '1969-12-31']) assert.equal(P.dayOf(s), null, s);
});

test('the day turns at local midnight, wherever the machine is', (t) => {
  const tz = process.env.TZ;
  t.after(() => (tz === undefined ? delete process.env.TZ : (process.env.TZ = tz)));
  for (const zone of ['Asia/Dhaka', 'UTC']) {
    process.env.TZ = zone;
    assert.equal(P.dayOf(P.today(new Date(2026, 9, 31, 23, 59, 59))), 20757, zone);
    assert.equal(P.dayOf(P.today(new Date(2026, 10, 1, 0, 0, 0))), 20758, zone);
  }
});

const entries = [
  ...Array.from({ length: 30 }, (_, i) => ({ kind: 'ayah', ref: `a${i}` })),
  ...Array.from({ length: 30 }, (_, i) => ({ kind: 'hadith', ref: `h${i}` })),
  ...Array.from({ length: 30 }, (_, i) => ({ kind: 'dua', ref: `d${i}` })),
  ...Array.from({ length: 102 }, (_, i) => ({ kind: 'quote', text: `q${i}`, author: 'x' })),
];

test('the kind turns ayah, hadith, dua, quote, and the entry is the day over 4 within that kind', () => {
  const at = (iso) => (({ kind, entry, date }) => [date, kind, entry])(P.pick(P.dayOf(iso), entries));
  assert.deepEqual(at('2026-11-03'), ['2026-11-03', 'ayah', 0]);
  assert.deepEqual(at('2026-11-04'), ['2026-11-04', 'hadith', 0]);
  assert.deepEqual(at('2026-11-01'), ['2026-11-01', 'dua', 29]);
  assert.deepEqual(at('2026-11-02'), ['2026-11-02', 'quote', 89]);
  assert.equal(P.pick(P.dayOf('2026-11-03'), entries).item.ref, 'a0');
});

test("a day deen cannot answer falls back to a later block's quote, never its own block's", () => {
  // 2026-11-04 is a hadith day in block 5190: (5190 + 1 + 1) mod 102.
  assert.deepEqual(P.fallback(P.dayOf('2026-11-04'), entries), { entry: 92, item: { kind: 'quote', text: 'q92', author: 'x' } });
  for (let day = 20756; day < 20756 + 4 * 102; day++) {
    const own = P.pick(Math.floor(day / 4) * 4 + 3, entries).entry;
    assert.notEqual(P.fallback(day, entries).entry, own, `day ${day}`);
  }
});

test('each kind asks deen its own way, and a quote asks nothing', () => {
  assert.deepEqual(P.deenArgs({ kind: 'ayah', ref: '94:6' }), ['api', 'ayah', '94:6']);
  assert.deepEqual(P.deenArgs({ kind: 'hadith', ref: 'bukhari:1' }), ['hadith', 'show', 'bukhari:1']);
  assert.deepEqual(P.deenArgs({ kind: 'dua', ref: '16' }), ['dua', 'show', '16']);
  assert.equal(P.deenArgs({ kind: 'quote', text: 't', author: 'a' }), null);
});

const SURAHS = JSON.stringify({ surahs: [{ n: 93, en: 'Ad-Dhuhaa', bn: 'সূরা আদ-দুহা' }, { n: 94, en: 'Ash-Sharh', bn: 'সূরা আশ-শারহ' }] });
const json = (o) => JSON.stringify(o);
const AYAH = { s: 94, a: 6, ar: 'إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا', bn_pron: 'ইন্না মা‘আল‘উসরি ইউসরা-', bn: 'নিশ্চয় কষ্টের সাথেই স্বস্তি আছে।', en: 'Indeed, with hardship [will be] ease.' };

test('an ayah draws its Arabic, Bangla pronunciation and Bangla meaning, under its surah in Bangla and Bangla digits', () => {
  assert.deepEqual(P.shape({ kind: 'ayah', ref: '94:6' }, json({ ayah: AYAH }), SURAHS), {
    ar: 'إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا',
    bn_pron: 'ইন্না মা‘আল‘উসরি ইউসরা-',
    bn: 'নিশ্চয় কষ্টের সাথেই স্বস্তি আছে।',
    en: '',
    ref: 'সূরা আশ-শারহ ৯৪:৬',
  });
});

test('an ayah whose surah deen did not name still reads its number in Bangla', () => {
  assert.equal(P.shape({ kind: 'ayah', ref: '94:6' }, json({ ayah: AYAH }), '').ref, 'সূরা ৯৪:৬');
});

const hadith = (collection, bn, n, text) => json({ hit: { collection, bn, name: 'x', hadith: { n, ar: 'حَدَّثَنَا', bn: text, bn_raw: `x ..... ${text}`, en: 'Narrated x:y' } } });

test('a hadith draws only its cleaned Bangla, narrator in it, over its collection in Bangla and its number in Bangla digits', () => {
  const h = hadith('bukhari', 'সহীহ বুখারী', '6807', 'সাহল ইবনু সা‘দ সা‘ঈদী (রাঃ) হতে বর্ণিত। নবী সাল্লাল্লাহু আলাইহি ওয়াসাল্লাম বলেছেনঃ যে কেউ আমার জন্য দায়িত্ব নেবে।');
  assert.deepEqual(P.shape({ kind: 'hadith', ref: 'bukhari:6807' }, h, SURAHS), {
    ar: '',
    bn_pron: '',
    bn: 'সাহল ইবনু সা‘দ সা‘ঈদী (রাঃ) হতে বর্ণিত। নবী সাল্লাল্লাহু আলাইহি ওয়াসাল্লাম বলেছেনঃ যে কেউ আমার জন্য দায়িত্ব নেবে।',
    en: '',
    ref: 'সহীহ বুখারী ৬৮০৭',
  });
  assert.equal(P.shape({ kind: 'hadith', ref: 'muslim:6602' }, hadith('muslim', 'সহীহ মুসলিম', '6602', 'নম্রতা'), SURAHS).ref, 'সহীহ মুসলিম ৬৬০২');
});

test('a dua draws its Arabic as the book spells it, the Bangla book\'s pronunciation and meaning, from Hisnul Muslim in Bangla digits', () => {
  const d = json({ dua: { id: '235', ar: 'رَبَّنَا آتِنَا', bn_pron: 'রব্বানা আ-তিনা', bn: 'হে আমাদের রব্ব!', bn_ref: 'আবূ দাউদ ২/১৭৯', en: 'Our Lord', ref: 'Abu Dawud 2/179' } });
  assert.deepEqual(P.shape({ kind: 'dua', ref: '235' }, d, SURAHS), { ar: 'رَبَّنَا آتِنَا', bn_pron: 'রব্বানা আ-তিনা', bn: 'হে আমাদের রব্ব!', en: '', ref: 'হিসনুল মুসলিম ২৩৫' });
});

test('a quote draws its English sentence over its author, with no deen answer', () => {
  assert.deepEqual(P.shape({ kind: 'quote', text: 'The best way to get started is to quit talking and begin doing.', author: 'Walt Disney' }, '', SURAHS), {
    ar: '',
    bn_pron: '',
    bn: '',
    en: 'The best way to get started is to quit talking and begin doing.',
    ref: 'Walt Disney',
  });
});

test('an answer that leaves a drawn line empty, or no answer, shapes to nothing', () => {
  assert.equal(P.shape({ kind: 'hadith', ref: 'muslim:1' }, hadith('muslim', 'সহীহ মুসলিম', '1', ''), SURAHS), null);
  assert.equal(P.shape({ kind: 'ayah', ref: '94:6' }, json({ ayah: { ...AYAH, ar: '' } }), SURAHS), null);
  assert.equal(P.shape({ kind: 'dua', ref: '16' }, json({ dua: { id: '16', ar: 'x', bn_pron: 'y', bn: ' ' } }), SURAHS), null);
  assert.equal(P.shape({ kind: 'ayah', ref: '94:6' }, 'deen: no such ayah', SURAHS), null);
});

test('a deen with no Bangla data, answering in English alone, shapes to nothing, so the day falls back', () => {
  const { bn, bn_pron, ...english } = AYAH;
  assert.equal(P.shape({ kind: 'ayah', ref: '94:6' }, json({ ayah: english }), SURAHS), null);
  assert.equal(P.shape({ kind: 'ayah', ref: '94:6' }, json({ ayah: { ...english, bn } }), SURAHS), null);
  assert.equal(P.shape({ kind: 'dua', ref: '16' }, json({ dua: { id: '16', ar: 'x', en: 'In the Name of Allah' } }), SURAHS), null);
  // An older deen gave a hadith its raw Bangla but no collection name in Bangla.
  assert.equal(P.shape({ kind: 'hadith', ref: 'bukhari:1' }, json({ hit: { collection: 'bukhari', name: 'x', hadith: { n: '1', bn: 'x', en: 'y' } } }), SURAHS), null);
});

test("an answer past the list's 280 characters, in any drawn line, is not drawn, and the line is named", () => {
  const ok = { ar: 'ا'.repeat(280), bn_pron: 'ক'.repeat(280), bn: 'ক'.repeat(280), en: '', ref: 'r' };
  assert.equal(P.within(ok), true);
  assert.equal(P.overLimit(ok), null);
  for (const [line, name] of [['ar', 'Arabic'], ['bn_pron', 'pronunciation'], ['bn', 'Bangla'], ['en', 'English']]) {
    const d = { ...ok, [line]: 'x'.repeat(281) };
    assert.equal(P.within(d), false, line);
    assert.equal(P.overLimit(d), `${name} is 281 characters`);
  }
  assert.equal(P.within(null), false);
});

test('the kind label and the reference line speak in each voice', () => {
  assert.deepEqual(P.voiced('caps', 'ayah', 'Ash-Sharh 94:6'), { label: 'AYAH', ref: 'Ash-Sharh 94:6' });
  assert.deepEqual(P.voiced('plain', 'ayah', 'Ash-Sharh 94:6'), { label: 'Ayah', ref: 'Ash-Sharh 94:6' });
  assert.deepEqual(P.voiced('bracket', 'ayah', 'Ash-Sharh 94:6'), { label: '[AYAH]', ref: 'ASH-SHARH 94:6' });
  assert.deepEqual(P.voiced('bracket', 'hadith', 'Sahih al-Bukhari 6114 · Abu Huraira'), { label: '[HADITH]', ref: 'SAHIH AL-BUKHARI 6114 · ABU HURAIRA' });
  assert.deepEqual(P.voiced('plain', 'quote', 'Walt Disney'), { label: 'Quote', ref: 'Walt Disney' });
});

const tokens = (name, voice, display) => ({ name, color: { ink: '#111', muted: '#555', line: '#ccc', accent: '#a00', danger: '#fb4', paper: '#eee', surface: '#fff' }, type: { display, ui: 'Maple Mono', voice } });

test("Paper draws a printed epigraph: tracked capitals in the accent, Arabic, italic serif English, an ink rule and a muted serif reference, centred", () => {
  const l = P.look(tokens('paper', 'caps', 'Instrument Serif'));
  assert.deepEqual([l.frame, l.width, l.pad, l.gap], ['none', 1024, [0, 0, 0], 35]);
  assert.deepEqual(l.label, { font: 'Maple Mono', size: 18, spacing: 5, color: '#a00' });
  assert.deepEqual(l.ar, { size: 86, align: 'center', glow: '' });
  assert.deepEqual(l.en, { font: 'Instrument Serif', size: 51, italic: true, height: 1.25, align: 'center' });
  assert.deepEqual(l.rule, { width: 48, color: '#111' });
  assert.deepEqual(l.ref, { font: 'Instrument Serif', size: 27, spacing: 0, color: '#555', align: 'center', dimension: false });
});

test('Paper draws Bangla upright in Noto Serif Bengali: a muted pronunciation, a larger meaning and a muted reference', () => {
  const l = P.look(tokens('paper', 'caps', 'Instrument Serif'));
  assert.deepEqual(l.pron, { font: 'Noto Serif Bengali', size: 30, height: 1.5, color: '#555' });
  assert.deepEqual(l.bn, { font: 'Noto Serif Bengali', size: 43, height: 1.5 });
  assert.deepEqual(l.bnRef, { font: 'Noto Serif Bengali', size: 24 });
});

test('Artboard draws a selected card with its frame label, right-aligned Arabic, mono English, a line rule and a muted reference, its Bangla in Noto Sans Bengali', () => {
  const l = P.look(tokens('artboard', 'plain', 'Maple Mono'));
  assert.deepEqual([l.frame, l.width, l.pad, l.gap], ['card', 992, [64, 77, 51], 29]);
  assert.deepEqual(l.label, { font: 'Maple Mono', size: 18, spacing: 0, color: '#a00' });
  assert.deepEqual(l.ar, { size: 74, align: 'right', glow: '' });
  assert.deepEqual(l.en, { font: 'Maple Mono', size: 29, italic: false, height: 1.55, align: 'left' });
  assert.deepEqual(l.rule, { width: -1, color: '#ccc' });
  assert.deepEqual(l.ref, { font: 'Maple Mono', size: 19, spacing: 0, color: '#555', align: 'left', dimension: false });
  assert.deepEqual(l.pron, { font: 'Noto Sans Bengali', size: 24, height: 1.6, color: '#555' });
  assert.deepEqual(l.bn, { font: 'Noto Sans Bengali', size: 30, height: 1.6 });
  assert.deepEqual(l.bnRef, { font: 'Noto Sans Bengali', size: 21 });
});

test('Blueprint draws crop marks, a bracketed label in the danger pen, glowing Arabic, its pronunciation in the accent and its reference on a dimension line', () => {
  const l = P.look(tokens('blueprint', 'bracket', 'Maple Mono'));
  assert.deepEqual([l.frame, l.width, l.pad, l.gap], ['marks', 1024, [58, 64, 58], 29]);
  assert.deepEqual(l.label, { font: 'Maple Mono', size: 18, spacing: 3, color: '#fb4' });
  assert.deepEqual(l.ar, { size: 77, align: 'right', glow: '#a00' });
  assert.deepEqual(l.en, { font: 'Maple Mono', size: 27, italic: false, height: 1.6, align: 'left' });
  assert.equal(l.rule, null);
  assert.deepEqual(l.ref, { font: 'Maple Mono', size: 18, spacing: 3.6, color: '#a00', align: 'center', dimension: true });
  assert.deepEqual(l.pron, { font: 'Noto Sans Bengali', size: 24, height: 1.6, color: '#a00' });
  assert.deepEqual(l.bn, { font: 'Noto Sans Bengali', size: 29, height: 1.6 });
  assert.deepEqual(l.bnRef, { font: 'Noto Sans Bengali', size: 21 });
});

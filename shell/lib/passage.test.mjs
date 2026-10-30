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
  for (const s of ['', '2026-11-3', '2026-02-30', '2026-13-01', 'today']) assert.equal(P.dayOf(s), null, s);
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

test('each kind asks deen its own way, and a quote asks nothing', () => {
  assert.deepEqual(P.deenArgs({ kind: 'ayah', ref: '94:6' }), ['api', 'ayah', '94:6']);
  assert.deepEqual(P.deenArgs({ kind: 'hadith', ref: 'bukhari:1' }), ['hadith', 'show', 'bukhari:1']);
  assert.deepEqual(P.deenArgs({ kind: 'dua', ref: '16' }), ['dua', 'show', '16']);
  assert.equal(P.deenArgs({ kind: 'quote', text: 't', author: 'a' }), null);
});

const SURAHS = JSON.stringify({ surahs: [{ n: 93, en: 'Ad-Dhuhaa' }, { n: 94, en: 'Ash-Sharh' }] });
const json = (o) => JSON.stringify(o);

test('an ayah draws its Arabic over its English, its brackets kept, under its surah and number', () => {
  const a = json({ ayah: { s: 94, a: 6, ar: 'إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا', en: 'Indeed, with hardship [will be] ease.' } });
  assert.deepEqual(P.shape({ kind: 'ayah', ref: '94:6' }, a, SURAHS), { ar: 'إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا', en: 'Indeed, with hardship [will be] ease.', ref: 'Ash-Sharh 94:6' });
});

const hadith = (collection, n, en) => json({ hit: { collection, name: 'x', hadith: { n, ar: 'حَدَّثَنَا', en } } });

test("a Bukhari hadith's narrator moves from its text to the reference line", () => {
  const h = hadith('bukhari', '6114', "Narrated Abu Huraira:Allah's Messenger (ﷺ) said, \"The strong is not the one who overcomes the people by his strength.\"");
  assert.deepEqual(P.shape({ kind: 'hadith', ref: 'bukhari:6114' }, h, SURAHS), {
    ar: '',
    en: "Allah's Messenger (ﷺ) said, \"The strong is not the one who overcomes the people by his strength.\"",
    ref: 'Sahih al-Bukhari 6114 · Abu Huraira',
  });
});

test('a hadith that opens a quote it never closes gains the closing mark, and a balanced one none', () => {
  const open = hadith('bukhari', '6013', 'Narrated Jarir bin `Abdullah:The Prophet (ﷺ) said, "He who is not merciful to others, will not be treated mercifully');
  assert.equal(P.shape({ kind: 'hadith', ref: 'bukhari:6013' }, open, SURAHS).en, 'The Prophet (ﷺ) said, "He who is not merciful to others, will not be treated mercifully"');
  const shut = hadith('bukhari', '1', 'Narrated \'Umar bin Al-Khattab: I heard him saying, "Deeds are by intentions."');
  assert.equal(P.shape({ kind: 'hadith', ref: 'bukhari:1' }, shut, SURAHS).en, 'I heard him saying, "Deeds are by intentions."');
});

test('a Muslim hadith draws as given, a space after a run-on colon, with no narrator in its reference', () => {
  const h = hadith('muslim', '6602', "A'isha, the wife of Allah's Apostle (ﷺ), reported Allah's Apostle (ﷺ) as saying:Kindness is not to be found in anything but that it adds to its beauty.");
  assert.deepEqual(P.shape({ kind: 'hadith', ref: 'muslim:6602' }, h, SURAHS), {
    ar: '',
    en: "A'isha, the wife of Allah's Apostle (ﷺ), reported Allah's Apostle (ﷺ) as saying: Kindness is not to be found in anything but that it adds to its beauty.",
    ref: 'Sahih Muslim 6602',
  });
  assert.equal(P.shape({ kind: 'hadith', ref: 'muslim:1' }, hadith('muslim', '1', 'Prayed at 4:30 and said: go'), SURAHS).en, 'Prayed at 4:30 and said: go');
});

test("a dua draws its Arabic as the book spells it, over its English, from Hisn al-Muslim", () => {
  const d = json({ dua: { id: '16', ar: 'بِسْمِ اللهِ ، تَوَكَّلْـتُ عَلى اللهِ', en: 'In the Name of Allah, I have placed my trust in Allah.' } });
  assert.deepEqual(P.shape({ kind: 'dua', ref: '16' }, d, SURAHS), { ar: 'بِسْمِ اللهِ ، تَوَكَّلْـتُ عَلى اللهِ', en: 'In the Name of Allah, I have placed my trust in Allah.', ref: 'Hisn al-Muslim 16' });
});

test('a quote draws its sentence over its author, with no deen answer', () => {
  assert.deepEqual(P.shape({ kind: 'quote', text: 'The best way to get started is to quit talking and begin doing.', author: 'Walt Disney' }, '', SURAHS), {
    ar: '',
    en: 'The best way to get started is to quit talking and begin doing.',
    ref: 'Walt Disney',
  });
});

test('an answer that leaves a drawn field empty, or no answer, shapes to nothing', () => {
  assert.equal(P.shape({ kind: 'hadith', ref: 'muslim:1' }, hadith('muslim', '1', ''), SURAHS), null);
  assert.equal(P.shape({ kind: 'ayah', ref: '94:6' }, json({ ayah: { s: 94, a: 6, ar: '', en: 'x' } }), SURAHS), null);
  assert.equal(P.shape({ kind: 'dua', ref: '16' }, json({ dua: { id: '16', ar: 'x', en: ' ' } }), SURAHS), null);
  assert.equal(P.shape({ kind: 'ayah', ref: '94:6' }, 'deen: no such ayah', SURAHS), null);
});

test('the kind label and the reference line speak in each voice', () => {
  assert.deepEqual(P.voiced('caps', 'ayah', 'Ash-Sharh 94:6'), { label: 'AYAH', ref: 'Ash-Sharh 94:6' });
  assert.deepEqual(P.voiced('plain', 'ayah', 'Ash-Sharh 94:6'), { label: 'Ayah', ref: 'Ash-Sharh 94:6' });
  assert.deepEqual(P.voiced('bracket', 'ayah', 'Ash-Sharh 94:6'), { label: '[AYAH]', ref: 'ASH-SHARH 94:6' });
  assert.deepEqual(P.voiced('bracket', 'hadith', 'Sahih al-Bukhari 6114 · Abu Huraira'), { label: '[HADITH]', ref: 'SAHIH AL-BUKHARI 6114 · ABU HURAIRA' });
  assert.deepEqual(P.voiced('plain', 'quote', 'Walt Disney'), { label: 'Quote', ref: 'Walt Disney' });
});

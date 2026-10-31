// Deen's Duas: Hisn al-Muslim read from `deen dua list`, its chapters filtered and stepped, and a dua made ready to draw and to copy.
import { oneLine, noData as noTextData } from './deen.mjs';

const BOOK = 'Hisn al-Muslim';

// A dua draws the Bangla book's pronunciation, meaning and reference, or the English, marked, where the book lacks one; each field loses controls and bidi overrides, keeping harakat, tatweel and U+200C.
function cleanDua(d) {
  const bn = oneLine(d.bn);
  const bnRef = oneLine(d.bn_ref);
  return {
    id: oneLine(d.id),
    ar: oneLine(d.ar),
    pron: oneLine(d.bn_pron),
    meaning: bn || oneLine(d.en),
    meaningEnglish: bn === '',
    // The reference alone: the book's name and sunnah.com's number would put English beside a Bangla line.
    source: bnRef || oneLine(d.ref),
    sourceEnglish: bnRef === '',
  };
}

// deen built these duas before it gave chapters Bangla names, so the Bangla data is not here.
const unnamed = (answer) => Array.isArray(answer.chapters) && answer.chapters.length > 0 && !answer.chapters.some((c) => c && typeof c.bn === 'string' && c.bn !== '');

export const noData = (answer) => noTextData(answer) || (!!answer && !answer.error && unnamed(answer));

// The list as chapters in the book's order, each with its own duas; null when the book or its Bangla is not on this machine.
export function parseList(answer) {
  if (!answer || answer.error || !Array.isArray(answer.chapters) || answer.chapters.length === 0 || unnamed(answer)) return null;
  const all = Array.isArray(answer.duas) ? answer.duas : [];
  const chapters = answer.chapters.map((c) => ({
    n: c.n,
    name: oneLine(c.bn),
    en: oneLine(c.en),
    ar: oneLine(c.ar),
    duas: all.filter((d) => d.chapter === c.n).map(cleanDua),
  }));
  const said = answer.source && answer.source.duas;
  return { count: typeof said === 'number' ? said : all.length, chapters };
}

export const heading = (count) => `${BOOK} · ${count} duas`;

// Decomposed and without ZWNJ or ZWJ, so য় typed as one code point or as য plus nukta, and যিক্‌র typed with or without its ZWNJ, match alike.
const folded = (s) => s.normalize('NFD').replace(/[\u200c\u200d]/g, '').toLowerCase();

// Chapters whose Bangla, English or Arabic name holds the query, any case.
export function filter(chapters, query) {
  const q = folded(oneLine(query));
  return chapters.filter((c) => [c.name, c.en, c.ar].some((s) => folded(s).includes(q)));
}

// The cursor moves by one and stops at the ends.
export const step = (i, by, len) => Math.max(0, Math.min(len - 1, i + by));

// n wraps from a chapter's last dua to its first.
export const nextDua = (k, m) => (k + 1) % m;

// Blueprint writes it in capitals.
export const duaHead = (k, m, upper) => (upper ? `DUA ${k} OF ${m}` : `dua ${k} of ${m}`);

export const copyText = (d) => [d.ar, d.pron, d.meaning, d.source].join('\n');

// The board sets one short dua at 46 px; the book's longest runs to 1800 letters, so the size steps down with the length.
export const arabicSize = (text) => (text.length <= 45 ? 46 : text.length <= 110 ? 34 : text.length <= 250 ? 26 : 20);

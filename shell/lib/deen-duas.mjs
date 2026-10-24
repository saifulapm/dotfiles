// Deen's Duas: Hisn al-Muslim read from `deen dua list`, its chapters filtered and stepped, and a dua made ready to draw and to copy.
import { oneLine } from './deen.mjs';

const BOOK = 'Hisn al-Muslim';

// A dua's fields are the book's text, so each loses its controls and bidi overrides; Arabic keeps its letters, tatweel and harakat.
function cleanDua(d) {
  return { id: oneLine(d.id), ar: oneLine(d.ar), tr: oneLine(d.tr), en: oneLine(d.en), ref: oneLine(d.ref) };
}

// The list as chapters in the book's order, each with its own duas; null when the book is not on this machine.
export function parseList(answer) {
  if (!answer || answer.error || !Array.isArray(answer.chapters) || answer.chapters.length === 0) return null;
  const all = Array.isArray(answer.duas) ? answer.duas : [];
  const chapters = answer.chapters.map((c) => ({
    n: c.n,
    name: oneLine(c.en),
    ar: oneLine(c.ar),
    duas: all.filter((d) => d.chapter === c.n).map(cleanDua),
  }));
  const said = answer.source && answer.source.duas;
  return { count: typeof said === 'number' ? said : all.length, chapters };
}

export const heading = (count) => `${BOOK} · ${count} duas`;

// Chapters whose English or Arabic name holds the query, any case.
export function filter(chapters, query) {
  const q = oneLine(query).toLowerCase();
  return chapters.filter((c) => c.name.toLowerCase().includes(q) || c.ar.toLowerCase().includes(q));
}

// The cursor moves by one and stops at the ends.
export const step = (i, by, len) => Math.max(0, Math.min(len - 1, i + by));

// n wraps from a chapter's last dua to its first.
export const nextDua = (k, m) => (k + 1) % m;

// Blueprint writes it in capitals.
export const duaHead = (k, m, upper) => (upper ? `DUA ${k} OF ${m}` : `dua ${k} of ${m}`);

export const sourceLine = (d) => (d.ref ? `${d.ref} · ${BOOK} ${d.id}` : `${BOOK} ${d.id}`);

export const copyText = (d) => [d.ar, d.tr, d.en, sourceLine(d)].join('\n');

// The board sets one short dua at 46 px; the book's longest runs to 1800 letters, so the size steps down with the length.
export const arabicSize = (text) => (text.length <= 45 ? 46 : text.length <= 110 ? 34 : text.length <= 250 ? 26 : 20);

// Hadith's words: the corpus download read from fetch's events, a hit's collection, grade and narrator, and the text y copies.
import { answer, oneLine } from './deen.mjs';

const MB = 1e6;
const whole = (bytes) => Math.round((bytes || 0) / MB);
export const mb = (bytes) => `${whole(bytes)} MB`;
const sizeOf = (d) => `${whole(d.done)} of ${whole(d.total)} MB`;

function leftText(s) {
  return s < 60 ? `about ${Math.round(s)} s` : `about ${Math.round(s / 60)} min`;
}

export function progress(d) {
  const fraction = d.total > 0 ? Math.min(1, d.done / d.total) : 0;
  return {
    fraction,
    percent: `${Math.round(fraction * 100)}%`,
    size: sizeOf(d),
    speed: d.rate > 0 ? `${(d.rate / MB).toFixed(1)} MB/s` : '',
    left: d.rate > 0 ? leftText(Math.max(0, d.total - d.done) / d.rate) : '',
  };
}

export function tilde(dir, home) {
  const d = String(dir || '');
  return home && (d === home || d.startsWith(home + '/')) ? '~' + d.slice(home.length) : d;
}

export function event(line) {
  const e = answer(line);
  return e && typeof e.event === 'string' ? e : null;
}

export const START = { phase: 'idle', done: 0, total: 0, rate: 0, message: '' };

const update = (d, change) => Object.assign({}, d, change);

export function afterEvent(d, e) {
  if (e.event === 'progress') return update(d, { phase: 'running', done: e.done || 0, total: e.total || 0, rate: e.rate || 0 });
  if (e.event === 'converting') return update(d, { phase: 'converting' });
  if (e.event === 'done') return update(d, { phase: 'done' });
  if (e.event === 'error') return update(d, { phase: 'failed', done: e.done ?? d.done, total: e.total ?? d.total, message: String(e.message || '') });
  return d;
}

// fetch that ends without its done event has failed, whether or not it said why.
export const afterExit = (d) => (d.phase === 'done' || d.phase === 'failed' ? d : update(d, { phase: 'failed' }));

export function failText(d) {
  const why = oneLine(d.message);
  const lead = why ? why.charAt(0).toUpperCase() + why.slice(1) : 'The download stopped';
  return `${lead} at ${sizeOf(d)}. The part already saved is kept, so retrying carries on from there.`;
}

const NAMES = {
  bukhari: 'Sahih al-Bukhari',
  muslim: 'Sahih Muslim',
  abudawud: 'Sunan Abi Dawud',
  tirmidhi: 'Jami at-Tirmidhi',
  nasai: "Sunan an-Nasa'i",
  ibnmajah: 'Sunan Ibn Majah',
  malik: 'Muwatta Malik',
  nawawi: '40 Hadith Nawawi',
  qudsi: '40 Hadith Qudsi',
  dehlawi: '40 Hadith Shah Waliullah',
};

export const boardName = (slug, name) => NAMES[slug] || oneLine(name);

// The corpus carries no grades for Bukhari and Muslim, whose own standard is sahih; a list model hands its rows' arrays over as array-likes.
export function gradeText(slug, grades) {
  const g = grades && typeof grades.length === 'number' ? Array.from(grades).filter((x) => x && x.grade) : [];
  if (g.length === 0) return slug === 'bukhari' || slug === 'muslim' ? 'Sahih' : 'ungraded';
  if (g.every((x) => x.grade === g[0].grade)) return oneLine(g[0].grade);
  return g.map((x) => (x.by ? `${oneLine(x.grade)} (${oneLine(x.by)})` : oneLine(x.grade))).join(' · ');
}

export function narrator(en) {
  const s = String(en || '');
  const m = /^Narrated ([^:\n]{1,100}):\s*/.exec(s);
  return m ? { by: m[1].trim(), body: s.slice(m[0].length) } : { by: '', body: s };
}

// Text that wraps keeps its newlines; every other control and the bidi overrides and isolates go.
export const wrapped = (s) => String(s ?? '').replace(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f‪-‮⁦-⁩]/g, '');

export function narrations(a) {
  if (!a || !Array.isArray(a.collections)) return '';
  const n = a.collections.reduce((sum, c) => sum + (c.hadiths || 0), 0);
  return String(n).replace(/\B(?=(\d{3})+$)/g, ',');
}

// The flags come first and -- before the words, so a typed word that starts with a dash is searched for, not obeyed.
export function searchArgs(query) {
  const words = String(query || '').split(/\s+/).filter((w) => w);
  return words.length ? ['hadith', 'search', '--limit', '40', '--'].concat(words) : null;
}

export const resultsText = (n) => `${n} ${n === 1 ? 'result' : 'results'}`;

// A number in Bangla digits, as a reference beside a Bangla name is written; a sub-number such as 402.2 keeps its dot.
export const bnDigits = (n) => String(n).replace(/[0-9]/g, (d) => '০১২৩৪৫৬৭৮৯'[d]);

export const reference = (bn, n) => `${oneLine(bn)} ${bnDigits(oneLine(n))}`;

// A row is cells along one line, each drawn in its face: bn and ref in the Bangla face, en and count in the body face, mark as the English label.
export const rowText = (row) => row.cells.map((c) => c.text).join('  ');

export const collectionRow = (c) => ({
  english: false,
  cells: [
    { text: oneLine(c.bn), face: 'bn' },
    { text: boardName(c.slug, c.name), face: 'en' },
    { text: oneLine(c.count), face: 'count' },
  ],
});

// Book 0 gathers the narrations the corpus files under no book, so it has a name and no number.
export const bookRow = (b) => ({
  english: false,
  cells: [
    { text: b.n === 0 ? oneLine(b.bn) : `${bnDigits(b.n)}. ${oneLine(b.bn)}`, face: 'bn' },
    { text: oneLine(b.count), face: 'count' },
  ],
});

// English is drawn only where the narration has no Bangla.
export function narrationRow(h) {
  const bn = oneLine(h.bn);
  if (bn) return { english: false, cells: [{ text: bn, face: 'bn' }] };
  return { english: true, cells: [{ text: 'English', face: 'mark' }, { text: oneLine(narrator(h.en).body), face: 'en' }] };
}

export function hitRow(hit) {
  const row = narrationRow(hit.hadith || {});
  return { english: row.english, cells: [{ text: reference(hit.bn, (hit.hadith || {}).n), face: 'ref' }].concat(row.cells) };
}

// A narration from `hadith list` made into the shape a search hit has, so both open and copy alike.
export const listHit = (answer, h) => ({
  collection: answer.collection,
  name: answer.name,
  bn: answer.bn,
  book: { n: answer.book.n, bn: answer.book.bn, en: answer.book.en },
  url: `https://sunnah.com/${answer.collection}:${h.n}`,
  hadith: h,
});

// An opened narration: its Arabic, then its Bangla, or its English with narrator and grade where it has no Bangla, and its reference in Bangla.
export function pane(hit) {
  const h = hit.hadith || {};
  const english = oneLine(h.bn) === '';
  const told = english ? narrator(h.en) : { by: '', body: h.bn };
  return {
    title: oneLine(hit.book && hit.book.bn),
    ar: wrapped(h.ar),
    text: wrapped(told.body),
    english,
    by: oneLine(told.by),
    grade: english ? gradeText(hit.collection, h.grades) : '',
    reference: reference(hit.bn, h.n),
  };
}

// The levels as a stack: Enter pushes one, Esc pops one, and Esc on the collections, with nothing under them, closes Deen.
export const LEVELS = [{ level: 'collections', cursor: 0 }];

export const down = (s, entry) => s.concat([Object.assign({ cursor: 0 }, entry)]);

export const up = (s) => (s.length > 1 ? s.slice(0, -1) : null);

const top = (s) => s[s.length - 1];

// An open narration shows over its book's list, so the cursor and rows are that list's.
export const listEntry = (s) => (top(s).level === 'narration' ? s[s.length - 2] : top(s));

export function withCursor(s, cursor) {
  const i = s.indexOf(listEntry(s));
  return s.slice(0, i).concat([Object.assign({}, s[i], { cursor })], s.slice(i + 1));
}

// / from search stays in it; from any other level it opens over that level.
export const search = (s) => (top(s).level === 'search' ? s : down(s, { level: 'search' }));

export function heading(s) {
  const e = listEntry(s);
  if (e.level === 'collections') return 'Collections';
  if (e.level === 'books') return oneLine(e.data.bn);
  if (e.level === 'narrations') return `${oneLine(e.data.bn)} · ${oneLine(e.data.book.bn)}`;
  return '';
}

export function copyText(hit) {
  const h = hit.hadith || {};
  const n = narrator(h.en);
  const english = n.by ? `${wrapped(n.body)}\nNarrated by ${oneLine(n.by)}` : wrapped(n.body);
  return [`${boardName(hit.collection, hit.name)} ${oneLine(h.n)}`, wrapped(h.ar), english, oneLine(hit.url)].join('\n\n');
}

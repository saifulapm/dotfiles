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

export function searchArgs(query) {
  const words = String(query || '').split(' ').filter((w) => w);
  return words.length ? ['hadith', 'search'].concat(words, ['--limit', '40']) : null;
}

export const resultsText = (n) => `${n} ${n === 1 ? 'result' : 'results'}`;

export function copyText(hit) {
  const h = hit.hadith || {};
  const n = narrator(h.en);
  const english = n.by ? `${wrapped(n.body)}\nNarrated by ${oneLine(n.by)}` : wrapped(n.body);
  return [`${boardName(hit.collection, hit.name)} ${oneLine(h.n)}`, wrapped(h.ar), english, oneLine(hit.url)].join('\n\n');
}

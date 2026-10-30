// The daily passage: the list's lines read, the day's pick, deen's answer shaped to draw, and its label and reference line in each voice.
import { answer, oneLine } from './deen.mjs';
import { boardName, narrator } from './deen-hadith.mjs';
import { pad2 } from './margins.mjs';

export const KINDS = ['ayah', 'hadith', 'dua', 'quote'];

// A # at the start of a line or after a space starts a comment; no quote holds one.
const bare = (line) => line.replace(/(^|\s)#.*$/, '').trim();

function entryOf(text) {
  const [, kind, rest] = /^(\S+)\s*(.*)$/.exec(text);
  if (kind === 'ayah') return /^\d+:\d+$/.test(rest) ? { kind, ref: rest } : { why: 'not one ayah' };
  if (kind === 'hadith') return /^(bukhari|muslim):\d+[a-z]?$/.test(rest) ? { kind, ref: rest } : { why: 'not Bukhari or Muslim' };
  if (kind === 'dua') return /^\d+[a-z]?$/.test(rest) ? { kind, ref: rest } : { why: 'not a dua id' };
  if (kind === 'quote') {
    // Greedy, so a quote that holds the dash itself splits at the last one.
    const m = /^(.+) — (.+)$/.exec(rest);
    return m ? { kind, text: m[1], author: m[2] } : { why: 'no author' };
  }
  return { why: 'no such kind' };
}

export function parse(text) {
  const entries = [];
  const bad = [];
  String(text ?? '').split('\n').forEach((raw, i) => {
    const line = bare(raw);
    if (!line) return;
    const e = entryOf(line);
    if (e.why) bad.push({ line: i + 1, text: line, why: e.why });
    else entries.push(Object.assign(e, { line: i + 1 }));
  });
  return { entries, bad };
}

const DAY = 86400000;

// The day number of a YYYY-MM-DD date, counted in whole calendar days, so no time zone moves it; null for anything else.
export function dayOf(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso ?? ''));
  if (!m) return null;
  const t = Date.UTC(+m[1], m[2] - 1, +m[3]);
  return new Date(t).toISOString().slice(0, 10) === iso ? t / DAY : null;
}

export const dateOf = (day) => new Date(day * DAY).toISOString().slice(0, 10);

export const today = (now) => `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;

export function pick(day, entries) {
  const kind = KINDS[day % 4];
  const of = entries.filter((e) => e.kind === kind);
  const entry = Math.floor(day / 4) % of.length;
  return { day, date: dateOf(day), kind, entry, item: of[entry] };
}

export function deenArgs(item) {
  if (item.kind === 'ayah') return ['api', 'ayah', item.ref];
  if (item.kind === 'hadith') return ['hadith', 'show', item.ref];
  if (item.kind === 'dua') return ['dua', 'show', item.ref];
  return null;
}

// A hadith that opens a quote it never closes ends with the closing mark.
const closed = (s) => ((s.match(/"/g) || []).length % 2 ? s + '"' : s);

function hadithText(hit) {
  const h = hit.hadith || {};
  const n = oneLine(h.n);
  if (hit.collection === 'muslim') return { en: closed(oneLine(h.en).replace(/:(?=[^\s\d])/g, ': ')), ref: `${boardName('muslim')} ${n}` };
  const said = narrator(oneLine(h.en));
  return { en: closed(said.body), ref: `${boardName(hit.collection)} ${n}${said.by ? ` · ${said.by}` : ''}` };
}

function drawn(item, a, surahs) {
  if (item.kind === 'quote') return { ar: '', en: oneLine(item.text), ref: oneLine(item.author) };
  if (!a) return null;
  if (item.kind === 'ayah' && a.ayah) {
    const s = ((surahs && surahs.surahs) || []).find((x) => x.n === a.ayah.s);
    return { ar: oneLine(a.ayah.ar), en: oneLine(a.ayah.en), ref: `${s ? oneLine(s.en) : 'Surah'} ${a.ayah.s}:${a.ayah.a}` };
  }
  if (item.kind === 'hadith' && a.hit) return Object.assign({ ar: '' }, hadithText(a.hit));
  if (item.kind === 'dua' && a.dua) return { ar: oneLine(a.dua.ar), en: oneLine(a.dua.en), ref: `Hisn al-Muslim ${oneLine(a.dua.id)}` };
  return null;
}

// What the passage draws from deen's answer and `deen api surahs`; null when deen gave no answer or left a drawn field empty.
export function shape(item, text, surahsText) {
  const d = drawn(item, answer(text), answer(surahsText));
  if (!d || !d.en || (item.kind !== 'hadith' && item.kind !== 'quote' && !d.ar)) return null;
  return d;
}

// Paper's tracked capitals, Artboard's frame label, Blueprint's brackets and capitals.
export function voiced(voice, kind, ref) {
  if (voice === 'plain') return { label: kind.charAt(0).toUpperCase() + kind.slice(1), ref };
  if (voice === 'bracket') return { label: `[${kind.toUpperCase()}]`, ref: ref.toUpperCase() };
  return { label: kind.toUpperCase(), ref };
}

// Each theme's passage as its board draws it, in logical pixels on a 2048 px wide output: Paper's epigraph, Artboard's selected card, Blueprint's drawing with crop marks.
export function look(tokens) {
  const c = tokens.color;
  const t = tokens.type;
  if (t.voice === 'plain') {
    return {
      frame: 'card',
      width: 992,
      pad: [64, 77, 51],
      gap: 29,
      label: { font: t.ui, size: 18, spacing: 0, color: c.accent },
      ar: { size: 74, align: 'right', glow: '' },
      en: { font: t.ui, size: 29, italic: false, height: 1.55, align: 'left' },
      rule: { width: -1, color: c.line },
      ref: { font: t.ui, size: 19, spacing: 0, color: c.muted, align: 'left', dimension: false },
    };
  }
  if (t.voice === 'bracket') {
    return {
      frame: 'marks',
      width: 1024,
      pad: [58, 64, 58],
      gap: 29,
      label: { font: t.ui, size: 18, spacing: 3, color: c.danger },
      ar: { size: 77, align: 'right', glow: c.accent },
      en: { font: t.ui, size: 27, italic: false, height: 1.6, align: 'left' },
      rule: null,
      ref: { font: t.ui, size: 18, spacing: 3.6, color: c.accent, align: 'center', dimension: true },
    };
  }
  return {
    frame: 'none',
    width: 1024,
    pad: [0, 0, 0],
    gap: 35,
    label: { font: t.ui, size: 18, spacing: 5, color: c.accent },
    ar: { size: 86, align: 'center', glow: '' },
    en: { font: t.display, size: 51, italic: true, height: 1.25, align: 'center' },
    rule: { width: 48, color: c.ink },
    ref: { font: t.display, size: 27, spacing: 0, color: c.muted, align: 'center', dimension: false },
  };
}

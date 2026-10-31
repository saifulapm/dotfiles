// The daily passage: the list's lines read, the day's pick, deen's answer shaped to draw, and its label and reference line in each voice.
import { answer, oneLine } from './deen.mjs';
import { bnDigits, reference } from './deen-hadith.mjs';
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

// The day number of a YYYY-MM-DD date, counted in whole calendar days, so no time zone moves it; null for anything else, a day before 1970-01-01 too.
export function dayOf(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso ?? ''));
  if (!m) return null;
  const t = Date.UTC(+m[1], m[2] - 1, +m[3]);
  return t >= 0 && new Date(t).toISOString().slice(0, 10) === iso ? t / DAY : null;
}

export const dateOf = (day) => new Date(day * DAY).toISOString().slice(0, 10);

export const today = (now) => `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;

export function pick(day, entries) {
  const kind = KINDS[day % 4];
  const of = entries.filter((e) => e.kind === kind);
  const entry = Math.floor(day / 4) % of.length;
  return { day, date: dateOf(day), kind, entry, item: of[entry] };
}

// The quote a day shows when deen cannot answer it: one the next blocks hold, never this block's own.
export function fallback(day, entries) {
  const quotes = entries.filter((e) => e.kind === 'quote');
  const entry = (Math.floor(day / 4) + 1 + (day % 4)) % quotes.length;
  return { entry, item: quotes[entry] };
}

export function deenArgs(item) {
  if (item.kind === 'ayah') return ['api', 'ayah', item.ref];
  if (item.kind === 'hadith') return ['hadith', 'show', item.ref];
  if (item.kind === 'dua') return ['dua', 'show', item.ref];
  return null;
}

const NONE = { ar: '', bn_pron: '', bn: '', en: '' };

// The lines an ayah or dua draws: its Arabic, its Bangla pronunciation and its Bangla meaning.
const threeLines = (x) => ({ ar: oneLine(x.ar), bn_pron: oneLine(x.bn_pron), bn: oneLine(x.bn) });

function drawn(item, a, surahs) {
  if (item.kind === 'quote') return Object.assign({}, NONE, { en: oneLine(item.text), ref: oneLine(item.author) });
  if (!a) return null;
  if (item.kind === 'ayah' && a.ayah) {
    const s = ((surahs && surahs.surahs) || []).find((x) => x.n === a.ayah.s);
    const name = s && oneLine(s.bn) ? oneLine(s.bn) : 'সূরা';
    return Object.assign({}, NONE, threeLines(a.ayah), { ref: `${name} ${bnDigits(a.ayah.s)}:${bnDigits(a.ayah.a)}` });
  }
  // deen gives a hadith's Bangla cleaned, its narrator left in; the collection's Bangla name is what an older deen, with no clean Bangla, lacks.
  if (item.kind === 'hadith' && a.hit && oneLine(a.hit.bn)) {
    const h = a.hit.hadith || {};
    return Object.assign({}, NONE, { bn: oneLine(h.bn), ref: reference(a.hit.bn, h.n) });
  }
  if (item.kind === 'dua' && a.dua) return Object.assign({}, NONE, threeLines(a.dua), { ref: `হিসনুল মুসলিম ${bnDigits(oneLine(a.dua.id))}` });
  return null;
}

// What the passage draws from deen's answer and `deen api surahs`; null when deen gave no answer or left a drawn line empty: a quote its English, a hadith its Bangla, an ayah or dua any of its three lines.
export function shape(item, text, surahsText) {
  const d = drawn(item, answer(text), answer(surahsText));
  if (!d) return null;
  const lines = item.kind === 'quote' ? ['en'] : item.kind === 'hadith' ? ['bn'] : ['ar', 'bn_pron', 'bn'];
  return lines.every((l) => d[l]) ? d : null;
}

const NAMES = { ar: 'Arabic', bn_pron: 'pronunciation', bn: 'Bangla', en: 'English' };

// The first drawn line past the list's 280 characters, as "<line> is <n> characters"; null when every line keeps to it.
export function overLimit(d) {
  const l = Object.keys(NAMES).find((k) => d[k].length > 280);
  return l ? `${NAMES[l]} is ${d[l].length} characters` : null;
}

// The list's limits, which a day's answer from deen keeps too, or the day falls back.
export const within = (d) => d !== null && overLimit(d) === null;

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

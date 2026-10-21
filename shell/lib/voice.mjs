// How the shell speaks under a token set, from its voice, as the three themes' boards draw it: the launcher and the lists that share its idioms, the island's notification and OSD, and the margins.

import { dateText, pad2 } from './margins.mjs';
import { chipLabel } from './notifs.mjs';
import { captureText } from './island.mjs';

export const MODES = ['apps', 'windows', 'clipboard', 'emoji', 'calculator', 'commands', 'reminder'];

// Each mode's prefix and the word the boards give it; Artboard spells calculator out.
const PREFIXES = [['w', 'windows'], ['v', 'clipboard'], [':', 'emoji'], ['=', 'calc'], ['>', 'commands']];
const PLAIN_WORD = { calc: 'calculator' };
const CAPS_NAME = { calculator: 'CALC', reminder: 'REMIND' };

// Artboard's board tints, which no token carries and no mix of tokens lands on.
const ARTBOARD = { tint: '#EEF1FF', deep: '#2638C9', tile: '#F2F3F6' };

// An open can come before the theme's tokens load; until then the launcher draws in black and white.
const UNTHEMED = { color: { ink: 'white', muted: 'gray', line: 'gray', surface: 'black', accent: 'white' }, type: { display: '', ui: '', mono: '', voice: 'caps' } };

// Bidi embedding, override and isolate controls, which let an app's name redraw itself in another order.
const BIDI = /[\u202A-\u202E\u2066-\u2069]/g;
const same = (s) => (s || '').replace(BIDI, '');
// Text a sender wrote, drawn in the order it is spelt; its lines stay.
export const inOrder = same;
const upper = (s) => same(s).toUpperCase();
// A one-line label: newlines and tabs become single spaces, so a sender cannot stack lines.
export const line = (s) => same(s).replace(/\s+/g, ' ').trim();

export function launcherLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const caps = voice !== 'plain';
  const key = (k) => (voice === 'bracket' ? `[${upper(k)}]` : caps ? upper(k) : k);
  // Reminder mode names the keys its rows take; Paper also names Enter's, as its board does.
  const REMINDER_KEYS = voice === 'caps' ? [['↵', 'set'], ['d', 'delete']] : [['d', 'delete']];
  const legend = (mode) => ({
    keys:
      mode === 'apps'
        ? PREFIXES.map(([k, w]) => ({ key: key(k), word: caps ? upper(w) : PLAIN_WORD[w] || w }))
        : mode === 'reminder'
          ? REMINDER_KEYS.map(([k, w]) => ({ key: key(k), word: caps ? upper(w) : w }))
          : [],
    tail: caps ? 'J/K · ↵ · ESC' : 'j/k · ↵ · esc',
    chips: voice === 'plain',
  });
  const base = {
    voice,
    legend,
    legendLine(mode) {
      const l = legend(mode);
      return l.keys.map((k) => `${k.key} ${k.word}`).concat([l.tail]).join('  ');
    },
    number: (i) => String(i + 1).padStart(2, '0'),
    title: same,
    detailText: same,
    // A row's global key: Artboard writes it as niri does, Paper in tracked caps and Blueprint in brackets.
    rowKey: (k) => (!k ? '' : voice === 'plain' ? k : key(k.replace(/\+/g, ' ').replace(/\bShift\b/, '⇧'))),
    // Paper names a capture row's tool and Blueprint leaves it bare, as the m24 boards draw them.
    rowDetail(row) {
      if (row.tool && voice === 'caps') return same(row.tool);
      if (row.tool && voice === 'bracket') return '';
      return this.detailText(row.detail);
    },
    count: () => '',
    pendingCount: (n) => (caps ? `${n} PENDING` : ''),
    // The head over the pending reminders; Blueprint counts them against the cap at the right.
    pendingHead: (n) => (voice === 'plain' ? { text: `Pending · ${n}`, right: '' } : { text: 'PENDING', right: voice === 'bracket' ? `${n} OF 50` : '' }),
    prompt: { text: '', color: c.accent, search: false },
    caret: 'line',
    rule: { color: c.ink, dashed: false },
    small: { font: t.ui, size: 10, spacing: 1.4, color: c.muted },
    tile: { size: 32, radius: 9, fill: ARTBOARD.tile },
  };
  if (voice === 'plain') {
    return Object.assign(base, {
      query: { font: t.ui, size: 20, italic: false },
      prompt: { text: '', color: c.muted, search: true },
      label: { kind: 'pill', text: (m) => m.charAt(0).toUpperCase() + m.slice(1), fill: ARTBOARD.tint, color: c.accent },
      slot: 'icon',
      name: { font: t.ui, size: 15, weight: 500, spacing: 0, color: c.ink },
      detail: { font: t.ui, size: 12, italic: false, color: c.muted },
      cursor: { fill: ARTBOARD.tint, text: ARTBOARD.deep, detail: c.muted, marker: 'transparent', radius: 10, weight: 600, badge: '↵' },
      rule: { color: c.line, dashed: false },
      small: { font: t.ui, size: 11, spacing: 0, color: c.muted },
      chip: { fill: ARTBOARD.tile, key: c.ink },
      keyChip: { fill: ARTBOARD.tile, text: c.muted, border: 0, borderColor: 'transparent', cursorFill: c.surface, cursorText: ARTBOARD.deep, cursorBorder: 'transparent', radius: 6, size: 11, spacing: 0, column: 0 },
    });
  }
  if (voice === 'bracket') {
    return Object.assign(base, {
      query: { font: t.mono, size: 22, italic: false },
      prompt: { text: '>', color: c.accent, search: false },
      caret: 'block',
      label: { kind: 'header', text: (m) => `LAUNCH // ${upper(m)}`, fill: 'transparent', color: c.muted },
      count: (n) => `${n} MATCHES`,
      slot: 'number',
      title: upper,
      detailText: upper,
      name: { font: t.mono, size: 15, weight: 400, spacing: 0.6, color: c.ink },
      detail: { font: t.mono, size: 11, italic: false, spacing: 1.3, color: c.muted },
      cursor: { fill: c.accent, text: c.surface, detail: c.surface, marker: 'transparent', radius: 0, weight: 700, badge: '' },
      rule: { color: c.line, dashed: true },
      small: { font: t.mono, size: 10, spacing: 1.6, color: c.muted },
      chip: { fill: 'transparent', key: c.accent },
      keyChip: { fill: 'transparent', text: c.muted, border: 0, borderColor: 'transparent', cursorFill: 'transparent', cursorText: c.surface, cursorBorder: 'transparent', radius: 0, size: 11, spacing: 1.3, column: 0 },
    });
  }
  return Object.assign(base, {
    query: { font: t.display, size: 34, italic: false },
    label: { kind: 'chip', text: (m) => CAPS_NAME[m] || upper(m), fill: c.ink, color: c.surface },
    count: (n) => `${n} FOUND`,
    slot: 'marker',
    name: { font: t.ui, size: 15, weight: 400, spacing: 0, color: c.ink },
    detail: { font: t.display, size: 16, italic: true, color: c.muted },
    cursor: { fill: c.ink, text: c.surface, detail: c.line, marker: c.accent, radius: 0, weight: 500, badge: '' },
    chip: { fill: 'transparent', key: c.ink },
    keyChip: { fill: 'transparent', text: c.ink, border: 1, borderColor: c.ink, cursorFill: 'transparent', cursorText: c.surface, cursorBorder: c.surface, radius: 0, size: 10, spacing: 1.4, column: 96 },
  });
}

// The island's board tints on its dark box, which no token carries.
const ISLAND = {
  caps: { head: '#B9AE99', body: '#D9CFBB' },
  plain: { head: '#A3A9B4', body: '#C9CED6', summary: '#FFFFFF', tile: '#2B2F36', bar: '#6C83FF' },
};

// How the island draws a notification; every colour not named here is the island's own text colour.
export function islandLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const appText = (app) => (voice === 'plain' ? line(app) : line(app).toUpperCase());
  const base = {
    voice,
    appText,
    brackets: voice === 'bracket',
    appLabel(app) {
      const a = appText(app);
      return a && voice === 'bracket' ? `[ ${a} ]` : a;
    },
    summaryText: line,
    bodyText: same,
    glyph: (app) => upper(app).charAt(0) || '•',
    tile: null,
  };
  if (voice === 'plain') {
    return Object.assign(base, {
      width: 440,
      age: 'now',
      pad: { x: 16, top: 14, bottom: 14 },
      head: { font: t.ui, size: 12, spacing: 0, color: ISLAND.plain.head },
      summary: { font: t.ui, size: 15, weight: 600, spacing: 0, color: ISLAND.plain.summary },
      body: { font: t.ui, size: 13, color: ISLAND.plain.body },
      tile: { size: 40, radius: 12, fill: ISLAND.plain.tile },
    });
  }
  if (voice === 'bracket') {
    return Object.assign(base, {
      width: 420,
      age: 'T+0S',
      pad: { x: 18, top: 12, bottom: 14 },
      head: { font: t.mono, size: 10, spacing: 1.6, color: c.muted },
      summary: { font: t.mono, size: 15, weight: 700, spacing: 0.6, color: c.accent },
      summaryText: (x) => line(x).toUpperCase(),
      body: { font: t.mono, size: 12, color: c.ink },
    });
  }
  return Object.assign(base, {
    width: 420,
    age: 'NOW',
    pad: { x: 16, top: 12, bottom: 14 },
    head: { font: t.ui, size: 10, spacing: 1.4, color: tokens ? ISLAND.caps.head : c.muted },
    summary: { font: t.display, size: 24, weight: 400, spacing: 0, color: '' },
    body: { font: t.mono, size: 12, color: tokens ? ISLAND.caps.body : c.ink },
  });
}

// What each capture card says under its result: Artboard's line names how it was read; niri's pick gives no place, so a colour says only that it was picked.
const CAPTURE_BODY = { ocr: 'eng + ben · from region', qr: 'from region', colour: 'colour picked' };

// How the island draws dots-capture's result, as each theme's board does: Paper's pill (a check, the title in caps, the count in serif, a colour's swatch and hex), or Artboard's and Blueprint's notification card, fed a note the card already draws. A colour left empty is the island's own text colour.
export function captureLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const card = (note) => ({ card: true, note: (r) => Object.assign({ swatch: r.swatch, icon: '', files: [] }, note(r)) });
  if (voice === 'plain') return card((r) => ({ app: 'Capture', summary: captureText(r), body: CAPTURE_BODY[r.kind] }));
  if (voice === 'bracket')
    return card((r) => ({
      app: r.kind.toUpperCase(),
      summary: r.kind === 'colour' || !r.title ? captureText(r) : r.title,
      body: r.kind === 'colour' ? CAPTURE_BODY.colour : r.title ? r.detail : '',
    }));
  return {
    card: false,
    height: 34,
    pad: 14,
    gap: 10,
    check: 12,
    swatch: 14,
    titleText: (s) => line(s).toUpperCase(),
    title: { font: t.ui, size: 10, spacing: 1.4 },
    // A colour's hex in mono, a count in the italic serif; a miss's words are muted.
    detail: (r) =>
      r.kind === 'colour'
        ? { font: t.mono, size: 12, weight: 500, spacing: 0.72, italic: false, color: '' }
        : { font: t.display, size: 17, weight: 400, spacing: 0, italic: true, color: r.title ? '' : tokens ? ISLAND.caps.head : c.muted },
  };
}

// The m21 boards' colours that no token carries: Artboard's last-minute chip.
const LEASE = { artboardWarn: '#B4380B', artboardChip: '#FFF1E8' };

// How the island draws an agent's lease in place of the clock, its last minute and its Mod+I card, as the m21 boards do (XX2P8V57); a colour left empty is the island's own text colour.
export function leaseLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const minutes = (ms) => {
    const s = Math.max(0, Math.ceil(ms / 1000));
    return `${Math.floor(s / 60)}:${pad2(s % 60)}`;
  };
  const time = (ms) => (voice === 'bracket' ? 'T−' : '') + minutes(ms);
  const text = (size, color, extra) => Object.assign({ font: t.ui, size, color, weight: 400, spacing: 0 }, extra);
  if (voice === 'plain') {
    const head = tokens ? ISLAND.plain.head : c.muted;
    return {
      voice,
      time,
      slot: {
        width: 264,
        height: 40,
        pad: 16,
        gap: 10,
        mark: { shape: 'dot', size: 8, color: tokens ? ISLAND.plain.bar : c.accent },
        label: Object.assign(text(13, ''), { text: '' }),
        who: Object.assign(text(13, tokens ? ISLAND.plain.body : c.ink, { weight: 500 }), { text: (who) => `Agent · ${line(who)}` }),
        time: text(13, tokens ? ISLAND.plain.summary : '', { weight: 500 }),
      },
      warning: { box: null, label: '', time: LEASE.artboardWarn, chip: LEASE.artboardChip, ring: LEASE.artboardChip, mark: LEASE.artboardWarn },
      card: {
        layout: 'card',
        width: 440,
        // The board draws the open card as a selected frame, named Island beside its corner.
        box: tokens ? { frame: { width: 1.5, color: c.accent }, handles: true, handleFill: c.surface } : null,
        label: 'Island',
        ink: tokens ? ISLAND.plain.summary : '',
        head: 'Agent · lease',
        headColor: head,
        who: line,
        unlocked: (hhmm) => `unlocked ${hhmm}`,
        unlockedColor: tokens ? ISLAND.plain.body : c.muted,
        left: 'left',
        tile: tokens ? ISLAND.plain.tile : c.muted,
        bar: 'round',
        barFill: tokens ? ISLAND.plain.bar : c.accent,
        keys: [['↵', 'lock now'], ['esc', 'close']],
      },
    };
  }
  if (voice === 'bracket') {
    return {
      voice,
      time,
      slot: {
        width: 320,
        height: 34,
        pad: 16,
        gap: 10,
        mark: null,
        label: Object.assign(text(12, c.muted, { font: t.mono, spacing: 1.68 }), { text: '[ AGENT ]' }),
        who: Object.assign(text(12, c.ink, { font: t.mono, weight: 700, spacing: 0.6 }), { text: (who) => upper(line(who)) }),
        time: text(12, c.accent, { font: t.mono, weight: 700, spacing: 0.6 }),
      },
      warning: { box: { frame: { width: 1, color: c.danger }, glow: c.danger }, label: '', time: c.danger, chip: '', ring: '', mark: '' },
      card: {
        layout: 'sheet',
        width: 420,
        box: null,
        label: '',
        title: (who) => `${upper(line(who))} HAS THE SESSION`,
        who: (who) => upper(line(who)),
        unlocked: (hhmm) => `UNLOCKED ${hhmm}`,
        bar: 'blocks',
        keys: [['[↵]', 'LOCK NOW'], ['[ESC]', 'CLOSE']],
      },
    };
  }
  return {
    voice,
    time,
    slot: {
      width: 300,
      height: 34,
      pad: 14,
      gap: 10,
      mark: { shape: 'square', size: 8, color: c.accent },
      label: Object.assign(text(10, tokens ? ISLAND.caps.body : c.muted, { spacing: 1.4 }), { text: 'AGENT' }),
      who: Object.assign(text(10, '', { weight: 500, spacing: 1.4 }), { text: (who) => upper(line(who)) }),
      time: text(20, '', { font: t.display }),
    },
    warning: { box: { fill: c.surface, text: c.ink, frame: { width: 1.5, color: c.danger } }, label: c.muted, time: c.danger, chip: '', ring: '', mark: '' },
    card: {
      layout: 'print',
      width: 420,
      box: tokens ? { frame: { width: 1.5, color: c.accent } } : null,
      label: '',
      headColor: tokens ? ISLAND.caps.head : c.muted,
      who: line,
      unlocked: (hhmm) => `unlocked ${hhmm}`,
      unlockedColor: tokens ? ISLAND.caps.body : c.muted,
      left: 'LEFT',
      bar: null,
      keys: [['↵', 'LOCK NOW'], ['ESC', 'CLOSE']],
    },
  };
}

// How the island draws a Taildrop send in place of the clock, as each m22 board does: a mark, the words in parts (the one naming the machine elides), the percent at the right and a bar along the bottom edge or after the words; a colour left empty is the island's own text colour.
export function sendingLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const files = (count) => `${count} ${count === 1 ? 'file' : 'files'}`;
  const text = (size, color, extra) => Object.assign({ font: t.ui, size, color, weight: 400, spacing: 0, name: false }, extra);
  if (voice === 'plain') {
    return {
      width: 380,
      height: 40,
      pad: 16,
      gap: 10,
      mark: { shape: 'upload', size: 16, color: '' },
      parts: [Object.assign(text(13, '', { weight: 500, name: true }), { text: (count, to, pct) => `Sending ${files(count)} to ${line(to)} · ${pct}%` })],
      pct: null,
      bar: { at: 'inline', height: 6, radius: 3, track: tokens ? ISLAND.plain.tile : c.muted, fill: tokens ? ISLAND.plain.bar : c.accent },
    };
  }
  if (voice === 'bracket') {
    return {
      width: 420,
      height: 34,
      pad: 16,
      gap: 10,
      mark: null,
      parts: [
        Object.assign(text(12, c.muted, { font: t.mono, spacing: 1.68 }), { text: () => '[ TAILDROP ]' }),
        Object.assign(text(12, c.ink, { font: t.mono, weight: 700, spacing: 0.6, name: true }), { text: (count, to) => `→ ${upper(line(to))}` }),
        Object.assign(text(10, c.muted, { font: t.mono, spacing: 1 }), { text: (count) => upper(files(count)) }),
      ],
      pct: Object.assign(text(12, c.accent, { font: t.mono, weight: 700, spacing: 0.6 }), { text: (p) => `${p}%` }),
      bar: { at: 'bottom', height: 3, radius: 0, track: c.line, fill: c.accent },
    };
  }
  return {
    width: 300,
    height: 34,
    pad: 14,
    gap: 10,
    mark: { shape: 'square', size: 8, color: c.accent },
    parts: [Object.assign(text(10, '', { spacing: 1.4, name: true }), { text: (count, to) => `SENDING ${upper(files(count))} TO ${upper(line(to))} ·` })],
    pct: Object.assign(text(20, '', { font: t.display }), { text: (p) => `${p}%` }),
    bar: { at: 'bottom', height: 4, radius: 0, track: c.paper, fill: c.accent },
  };
}

// C0 controls and DEL, which a file name from another machine may carry.
const CONTROLS = /[\u0000-\u001f\u007f]/g;

// How a file notification's chip draws in the toast, a centre row and the cursor row, its empty slot and the drag image, as the m22 boards do; every per-theme value sits here.
export function chipLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const label = (files) => line(chipLabel(files));
  const name = (files) => (files.length === 1 ? line(files[0].slice(files[0].lastIndexOf('/') + 1)).replace(CONTROLS, '') : label(files));
  const place = (fill, frame, text, grip, glyph, pad, radius) => ({ fill, frame, text, grip, glyph, pad, radius });
  if (voice === 'plain') {
    const row = place(ARTBOARD.tile, ARTBOARD.tile, c.muted, '#8A909B', c.muted, [5, 8, 5, 8], 8);
    return {
      label,
      name,
      font: t.ui,
      size: 11,
      spacing: 0,
      gap: 6,
      cut: 0,
      grip: { w: 8, h: 12, r: 1 },
      glyph: { w: 14, h: 14, stroke: 1.3, path: 'M3 1.5h5l3 3v8H3z M8 1.5v3h3' },
      toastPlace: 'column',
      rowPlace: 'afterAge',
      toast: place(ISLAND.plain.tile, ISLAND.plain.tile, ISLAND.plain.body, ISLAND.plain.head, ISLAND.plain.summary, [8, 10, 8, 10], 10),
      row,
      cursor: Object.assign({}, row, { fill: c.surface, frame: c.surface }),
      empty: { color: ISLAND.plain.bar, width: 1.5, content: false },
      frame: null,
      dragAge: '',
      drag: { fill: c.surface, frame: c.accent, frameWidth: 1.5, text: c.ink, grip: null, glyph: ARTBOARD.deep, shadow: null, pad: [9, 12, 9, 12], gap: 8, size: 12, weight: 500, spacing: 0, radius: 10, cut: 0 },
    };
  }
  if (voice === 'bracket') {
    const row = place(c.surface, c.accent, c.accent, c.muted, c.accent, [3, 10, 3, 6], 0);
    return {
      label,
      name,
      font: t.mono,
      size: 10,
      spacing: 1.2,
      gap: 6,
      cut: 7,
      grip: { w: 6, h: 10, r: 1 },
      glyph: { w: 9, h: 11, stroke: 1, path: 'M.5 .5h5l3 3v7h-8z' },
      toastPlace: 'body',
      rowPlace: 'underAge',
      toast: row,
      row,
      cursor: place(c.accent, c.surface, c.surface, c.surface, c.surface, [3, 10, 3, 6], 0),
      empty: { color: c.muted, width: 1, content: false },
      frame: null,
      dragAge: 'DRAGGING',
      drag: { fill: c.surface, frame: c.accent, frameWidth: 1, text: c.ink, grip: c.muted, glyph: c.accent, shadow: null, pad: [6, 14, 6, 9], gap: 8, size: 12, weight: 400, spacing: 0.72, radius: 0, cut: 9 },
    };
  }
  return {
    label,
    name,
    font: t.ui,
    size: 10,
    spacing: 1.4,
    gap: 7,
    cut: 0,
    grip: { w: 8, h: 12, r: 1.1 },
    glyph: { w: 12, h: 14, stroke: 1.2, path: 'M1.5 1.5h6l3 3v8h-9z M7.5 1.5v3h3' },
    toastPlace: 'body',
    rowPlace: 'beforeAge',
    toast: place(c.surface, c.surface, c.ink, c.ink, c.ink, [3, 9, 3, 7], 0),
    row: place(c.surface, c.ink, c.ink, c.ink, c.ink, [3, 9, 3, 7], 0),
    cursor: place(c.surface, c.surface, c.ink, c.ink, c.ink, [3, 9, 3, 7], 0),
    empty: { color: c.paper, width: 1, content: true },
    frame: { width: 1.5, color: c.accent },
    dragAge: '',
    drag: { fill: c.surface, frame: c.ink, frameWidth: 1, text: c.ink, grip: c.ink, glyph: c.ink, shadow: c.ink, pad: [6, 12, 6, 9], gap: 9, size: 12, weight: 500, spacing: 0, radius: 0, cut: 0 },
  };
}

// How the island draws the volume or brightness OSD: 20 bars, Blueprint's blocks or Artboard's one rounded bar.
export function osdLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const base = {
    voice,
    litCount: (v) => Math.round(Math.max(0, Math.min(100, v)) / 5),
    word: (kind) => (kind === 'brightness' ? 'BRT' : 'VOL'),
    valueText: (v) => String(v),
  };
  if (voice === 'plain') {
    return Object.assign(base, {
      width: 300,
      height: 40,
      word: () => '',
      bars: 'round',
      lit: { color: tokens ? ISLAND.plain.bar : c.accent },
      unlit: { color: tokens ? ISLAND.plain.tile : c.muted },
      value: { font: t.ui, size: 13, weight: 600, color: '' },
    });
  }
  if (voice === 'bracket') {
    return Object.assign(base, {
      width: 320,
      height: 34,
      bars: 'blocks',
      lit: { color: c.accent },
      unlit: { color: c.line },
      valueText: (v) => String(v).padStart(3, '0'),
      value: { font: t.mono, size: 12, weight: 700, color: c.accent },
      label: { font: t.mono, size: 12, spacing: 1.7, color: c.muted },
    });
  }
  return Object.assign(base, {
    width: 280,
    height: 34,
    bars: 'bars',
    lit: { color: c.accent },
    unlit: { color: c.muted },
    value: { font: t.display, size: 18, weight: 400, color: '' },
    label: { font: t.ui, size: 10, spacing: 1.4, color: '' },
  });
}

const MONDAY_FIRST = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

// How the calendar card's city column reads, as each m24 board draws it beside the month: home first and large with its mark (Paper's boxed HOME), then a rule above each city. place puts the offset beside the city's name, under it or at the row's right; the day word always sits under the name. A colour left empty is the island's own text colour.
export function clockLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const voice = t.voice;
  const text = (font, size, extra) => Object.assign({ font, size, weight: 400, spacing: 0, color: '' }, extra);
  if (voice === 'plain') {
    const head = ISLAND.plain.head;
    return {
      gridWidth: 224,
      gap: 22,
      head: '',
      homeLabel: text(t.ui, 12, { color: head }),
      mark: { text: ' · home', boxed: false },
      homeTime: text(t.ui, 26, { weight: 700 }),
      name: text(t.ui, 14, { weight: 500 }),
      time: text(t.ui, 17, { weight: 700 }),
      offset: text(t.ui, 12, { color: head }),
      place: 'under',
      offsetWidth: 0,
      city: same,
      offsetText: same,
      dayText: same,
      rule: { color: ISLAND.plain.tile, dashed: false },
      grid: {
        head: '',
        header: '',
        weekStart: 0,
        weekdays: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'],
        cell: 32,
        rowHeight: 28,
        weekHeight: 28,
        rowGap: 0,
        gap: 6,
        title: { place: 'line', parts: (g) => [`${g.month} ${g.year}`], left: text(t.ui, 15, { weight: 500 }), right: null },
        weekday: text(t.mono, 11, { color: ISLAND.plain.head }),
        day: text(t.mono, 12, { color: ISLAND.plain.body }),
        today: { w: 28, h: 24, radius: 8, inverted: true, fill: '', border: 0, borderColor: '', weight: 700 },
      },
    };
  }
  if (voice === 'bracket') {
    const small = text(t.mono, 10, { spacing: 1.6, color: c.muted });
    return {
      gridWidth: 224,
      gap: 20,
      head: '',
      homeLabel: small,
      mark: { text: ' · HOME', boxed: false },
      homeTime: text(t.mono, 15, { weight: 700, color: c.accent }),
      name: small,
      time: text(t.mono, 15, { weight: 700, color: c.ink }),
      offset: text(t.mono, 10, { spacing: 1.2, color: c.muted }),
      place: 'right',
      offsetWidth: 34,
      city: upper,
      offsetText: upper,
      dayText: upper,
      rule: { color: c.line, dashed: true },
      grid: {
        head: '',
        header: '[ CALENDAR ]',
        weekStart: 1,
        weekdays: MONDAY_FIRST,
        cell: 32,
        rowHeight: 26,
        weekHeight: 22,
        rowGap: 2,
        gap: 0,
        title: { place: 'header', parts: (g) => [`${g.abbr} ${g.year}`.toUpperCase()], left: small, right: null },
        weekday: text(t.mono, 10, { spacing: 0.8, color: c.muted }),
        day: text(t.mono, 12),
        today: { w: 32, h: 26, radius: 0, inverted: true, fill: c.accent, border: 0, borderColor: '', weight: 700 },
      },
    };
  }
  return {
    gridWidth: 238,
    gap: 20,
    head: 'WORLD CLOCK',
    homeLabel: text(t.display, 24),
    mark: { text: 'HOME', boxed: true },
    homeTime: text(t.display, 34),
    name: text(t.display, 20),
    time: text(t.display, 28),
    offset: text(t.ui, 10, { spacing: 1.4 }),
    place: 'name',
    offsetWidth: 0,
    city: same,
    offsetText: same,
    dayText: upper,
    rule: { color: '', dashed: false },
    grid: {
      head: 'CALENDAR',
      header: '',
      weekStart: 1,
      weekdays: MONDAY_FIRST,
      cell: 34,
      rowHeight: 26,
      weekHeight: 26,
      rowGap: 0,
      gap: 8,
      title: { place: 'split', parts: (g) => [g.month, String(g.year)], left: text(t.display, 24), right: text(t.display, 16, { italic: true }) },
      weekday: text(t.ui, 10, { spacing: 1 }),
      day: text(t.ui, 12),
      today: { w: 26, h: 22, radius: 0, inverted: false, fill: '', border: 1.5, borderColor: c.accent, weight: 700 },
    },
  };
}

// Control, the notification centre, the cheat sheet, polkit and the recorder draw as the launcher does: its cursor row, rules and legend.
export function listLook(tokens) {
  const l = launcherLook(tokens);
  const voice = l.voice;
  const keyText = (k) => (voice === 'bracket' ? `[${upper(k)}]` : voice === 'caps' ? upper(k) : same(k));
  const wordText = (w) => (voice === 'plain' ? same(w) : upper(w));
  const label = l.label;
  return Object.assign(l, {
    heading(name, section) {
      if (label.kind === 'header') return section ? `${upper(name)} // ${upper(section)}` : upper(name);
      return label.kind === 'pill' ? name.charAt(0).toUpperCase() + same(name.slice(1)) : upper(name);
    },
    tab: { fill: label.kind === 'header' ? l.cursor.fill : label.fill, text: label.kind === 'header' ? l.cursor.text : label.color, radius: label.kind === 'pill' ? 8 : 0 },
    tabText: wordText,
    keyText,
    keys: (pairs) => pairs.map(([k, w]) => ({ key: keyText(k), word: wordText(w) })),
    groupHead: (app, n) => (line(app || '') ? `${wordText(line(app))} · ${n}` : String(n)),
    // An age in whole units, floored; under a minute it is the island's word for arrival.
    ageText(ms) {
      const s = Math.floor(ms / 1000);
      const age = s < 60 ? (voice === 'bracket' ? '0S' : 'NOW') : s < 3600 ? `${Math.floor(s / 60)}M` : s < 86400 ? `${Math.floor(s / 3600)}H` : `${Math.floor(s / 86400)}D`;
      return voice === 'bracket' ? `T+${age}` : voice === 'plain' ? age.toLowerCase() : age;
    },
  });
}

// How the margins read under a token set: Paper's caps and dashes, Artboard's Page 03 and accent dot, Blueprint's brackets and ISO date.
export function marginLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const voice = (tokens || UNTHEMED).type.voice;
  const say = voice === 'plain' ? same : upper;
  const plain = voice === 'plain';
  const bracket = voice === 'bracket';
  const look = {
    voice,
    number: (idx) => (plain ? `Page ${pad2(idx)}` : bracket ? `[${pad2(idx)}]` : pad2(idx)),
    numberColor: bracket ? c.accent : c.ink,
    numberWeight: plain ? 600 : bracket ? 400 : 700,
    tail(view) {
      if (view.app === null && view.title === null) return '';
      const app = say(view.app ?? '');
      const title = say(view.title ?? '');
      return plain ? ` / ${app} — ${title}` : bracket ? ` ${app} — ${title}` : ` — ${app} · ${title}`;
    },
    goal(g) {
      if (!g) return '';
      const title = say(g.title);
      if (g.left === null) return title;
      if (bracket) return g.left === 'late' ? `${title} LATE` : `${title} T−${upper(g.left)}`;
      return `${title} · ${say(g.left)}`;
    },
    // Paper's accent bold, Artboard's ink medium after an accent dot, Blueprint's amber (its danger token).
    goalColor: bracket ? c.danger : plain ? c.ink : c.accent,
    goalWeight: bracket ? 400 : plain ? 500 : 700,
    dot: plain,
    dotColor: c.accent,
    // Unread mail is something to act on: ink in Paper (bold) and Artboard (medium), Blueprint's accent.
    mail: (n) => (n > 0 ? (plain ? `mail ${n}` : `MAIL ${n}`) : ''),
    mailColor: bracket ? c.accent : c.ink,
    mailWeight: bracket ? 400 : plain ? 500 : 700,
    word: (w) => (plain ? same(w).replace(/^wifi$/, 'Wi-Fi').replace(/^no wifi$/, 'No Wi-Fi') : upper(w)),
    date: (d) => (bracket ? `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}` : say(dateText(d))),
    sep: plain ? '' : bracket ? '·' : '—',
    spacing: plain ? 16 : 14,
  };
  // The words on screen, in order, for `qs ipc call margins state`.
  look.drawn = (view, now, right) => ({
    left: look.number(view.idx) + look.tail(view),
    right: [right.sync && look.word(right.sync), look.goal(right.goal), look.mail(right.mail), right.wifi && look.word(right.wifi), right.battery && look.word(right.battery), look.date(now)]
      .filter((p) => p)
      .join(look.sep ? ` ${look.sep} ` : ' '),
  });
  return look;
}

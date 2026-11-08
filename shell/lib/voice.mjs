// How the shell speaks under a token set, in its one plain voice: the launcher and the lists that share its idioms, the island's notification and OSD, and the margins.

import { dateText, pad2 } from './margins.mjs';
import { chipLabel } from './notifs.mjs';
import { captureText } from './island.mjs';
import { mix } from './notes-look.mjs';
import { contrast } from './theme.mjs';
import { slabText } from './surface.mjs';

export const MODES = ['apps', 'windows', 'clipboard', 'emoji', 'calculator', 'commands', 'reminder', 'colorschemes'];

// Each mode's prefix and the word the footer gives it.
const PREFIXES = [['w', 'windows'], ['v', 'clipboard'], [':', 'emoji'], ['=', 'calculator'], ['>', 'commands']];
// The keys a mode's rows take: reminder's delete, and clipboard's Shift+Enter, which copies a clip without pasting it.
const MODE_KEYS = { reminder: [['d', 'delete']], clipboard: [['⇧↵', 'copy']] };

// Artboard's board colours, which no token carries and no mix of its tokens lands on: the lit row's tint and its deep text, tiles, fields, thumbnails, rules, a meter's bar, the online and outline marks, the warning and its chip, strong text, a card, and the island's text and tile on its slab.
const ARTBOARD = {
  tint: '#EEF1FF', deep: '#2638C9', tile: '#F2F3F6', field: '#F6F7F9', thumb: '#E9ECF1', rule: '#E3E6EB', bar: '#6C83FF', online: '#1E8E5A', outline: '#8A909B', warn: '#B4380B', warnChip: '#FFF1E8', strong: '#2B2F36', card: '#FFFFFF', island: { head: '#A3A9B4', body: '#C9CED6', summary: '#FFFFFF', tile: '#2B2F36' },
};

// A colour moved toward another, a step at a time, until it reads at 4.5:1 on its ground; a scheme's ink always does on its surface, so the walk ends.
export function readable(fg, bg, toward) {
  for (let share = 0; share <= 1; share = Math.round((share + 0.05) * 100) / 100) {
    const c = share ? mix(fg, toward, share).toUpperCase() : fg;
    if (contrast(c, bg) >= 4.5) return c;
  }
  return toward;
}

// What words on the tint walk toward: the ink where it reads there at 4.5:1, else the ink moved on toward black or white until it does.
const tintInk = (c, mode, tint) => (contrast(c.ink, tint) >= 4.5 ? c.ink : readable(c.ink, tint, mode === 'dark' ? '#FFFFFF' : '#000000'));

// The same tones for any other scheme, mixed from its own tokens, so a dark scheme's lit row and island read in its colours, not Artboard's light ones.
function derived(c, mode) {
  const up = (h) => h.toUpperCase();
  // A tile or field ink text sits on: the surface mixed a little toward ink, backing toward the surface until ink reads there at 4.5:1; ink always reads on the surface.
  const ground = (share) => {
    while (share > 0 && contrast(c.ink, mix(c.surface, c.ink, share)) < 4.5) share = Math.round((share - 0.01) * 100) / 100;
    return up(share > 0 ? mix(c.surface, c.ink, share) : c.surface);
  };
  // The lit row keeps its tint, so it shows; words on it walk toward tintInk, the ink or, where ink only just reads on the surface, past it.
  const tint = up(mix(c.surface, c.accent, 0.14));
  // The island is an ink slab on a light scheme and the surface on a dark one, as surface.mjs draws it.
  const fill = mode === 'dark' ? c.surface : c.ink;
  const text = mode === 'dark' ? c.ink : slabText(c);
  return {
    tint,
    deep: readable(c.accent, tint, tintInk(c, mode, tint)),
    tile: ground(0.06),
    field: ground(0.04),
    thumb: up(mix(c.surface, c.ink, 0.09)),
    rule: up(mix(c.surface, c.ink, 0.12)),
    bar: up(mix(c.accent, c.surface, 0.2)),
    online: c.ok,
    outline: c.muted,
    warn: readable(c.danger, c.surface, c.ink),
    warnChip: up(mix(c.surface, c.danger, 0.1)),
    strong: c.ink,
    card: c.surface,
    island: { head: readable(up(mix(text, fill, 0.35)), fill, text), body: readable(up(mix(text, fill, 0.18)), fill, text), summary: text, tile: up(mix(fill, text, 0.14)) },
  };
}

// The board colours of a scheme: Artboard's own, before the tokens load too, else mixed from the scheme's.
export const plainTones = (tokens) => (!tokens || tokens.name === 'artboard' ? ARTBOARD : derived(tokens.color, tokens.mode));

// An open can come before the theme's tokens load; until then the shell draws the plain look in black and white.
const UNTHEMED = { color: { ink: 'white', muted: 'gray', line: 'gray', surface: 'black', accent: 'white' }, type: { display: '', ui: '', mono: '' } };

// Bidi marks, embeddings, overrides and isolates, which let an app's name redraw itself in another order.
const BIDI = /[‎‏؜‪-‮⁦-⁩]/g;
// Control characters other than tab, newline and return, which a font draws as tofu; they go, as the chip's do.
const CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/g;
const same = (s) => (s || '').replace(BIDI, '').replace(CONTROL, '');
// Text a sender wrote, drawn in the order it is spelt; its lines stay.
export const inOrder = same;
// A one-line label: newlines and tabs become single spaces, so a sender cannot stack lines.
export const line = (s) => same(s).replace(/\s+/g, ' ').trim();

export function launcherLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  // The pill word and the lit row's detail sit on the tint, so each moves toward the ink until it reads there.
  const tones = plainTones(tokens);
  const onTint = (fg) => (tokens ? readable(fg, tones.tint, tintInk(c, tokens.mode, tones.tint)) : fg);
  const legend = (mode) => ({
    keys: (mode === 'apps' ? PREFIXES : MODE_KEYS[mode] ?? []).map(([key, word]) => ({ key, word })),
    tail: 'j/k · ↵ · esc',
  });
  return {
    legend,
    legendLine(mode) {
      const l = legend(mode);
      return l.keys.map((k) => `${k.key} ${k.word}`).concat([l.tail]).join('  ');
    },
    title: same,
    detailText: same,
    // A row's global key, written as niri writes it.
    rowKey: (k) => k || '',
    rowDetail: (row) => same(row.detail),
    // The head over the pending reminders, with their count.
    pendingHead: (n) => ({ text: `Pending · ${n}`, right: '' }),
    prompt: { text: '', color: c.muted },
    query: { font: t.ui, size: 20 },
    label: { kind: 'pill', text: (m) => m.charAt(0).toUpperCase() + m.slice(1), fill: tones.tint, color: onTint(c.accent) },
    name: { font: t.ui, size: 15, weight: 500, spacing: 0, color: c.ink },
    detail: { font: t.ui, size: 12, italic: false, color: c.muted },
    cursor: { fill: tones.tint, text: tones.deep, detail: onTint(c.muted), radius: 10, weight: 600, badge: '↵' },
    small: { font: t.ui, size: 11, spacing: 0, color: c.muted },
    tile: { size: 32, radius: 9, fill: plainTones(tokens).tile },
    chip: { fill: 'transparent', key: c.muted },
    keyChip: { fill: plainTones(tokens).tile, text: c.muted, border: 0, borderColor: 'transparent', cursorFill: c.surface, cursorText: plainTones(tokens).deep, cursorBorder: 'transparent', radius: 6, size: 11, spacing: 0 },
  };
}

// How the island draws a notification and the media card's controls; every colour not named here is the island's own text colour.
export function islandLook(tokens) {
  const t = (tokens || UNTHEMED).type;
  return {
    appText: line,
    summaryText: line,
    bodyText: same,
    glyph: (app) => same(app).toUpperCase().charAt(0) || '•',
    width: 440,
    age: 'now',
    pad: { x: 16, top: 14, bottom: 14 },
    head: { font: t.ui, size: 12, spacing: 0, color: plainTones(tokens).island.head },
    summary: { font: t.ui, size: 15, weight: 600, spacing: 0, color: plainTones(tokens).island.summary },
    body: { font: t.ui, size: 13, color: plainTones(tokens).island.body },
    // The media card's previous, play/pause and next, in the body's tone, which every scheme keeps at 4.5:1 on the island.
    control: { color: plainTones(tokens).island.body },
    tile: { size: 40, radius: 12, fill: plainTones(tokens).island.tile },
  };
}

// What each capture card says under its result: the line names how it was read; niri's pick gives no place, so a colour says only that it was picked.
const CAPTURE_BODY = { ocr: 'eng + ben · from region', qr: 'from region', colour: 'colour picked' };

// How the island draws dots-capture's result: the notification card, fed a note from Capture with the result as its summary.
export function captureLook() {
  return { note: (r) => ({ swatch: r.swatch, icon: '', files: [], app: 'Capture', summary: captureText(r), body: CAPTURE_BODY[r.kind] }) };
}

// How the island draws an agent's lease in place of the clock, its last minute and its Mod+I card; a colour left empty is the island's own text colour.
export function leaseLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const time = (ms) => {
    const s = Math.max(0, Math.ceil(ms / 1000));
    return `${Math.floor(s / 60)}:${pad2(s % 60)}`;
  };
  const text = (size, color, extra) => Object.assign({ font: t.ui, size, color, weight: 400, spacing: 0 }, extra);
  return {
    time,
    slot: {
      width: 264,
      height: 40,
      pad: 16,
      gap: 10,
      mark: { shape: 'dot', size: 8, color: tokens ? plainTones(tokens).bar : c.accent },
      label: Object.assign(text(13, ''), { text: '' }),
      who: Object.assign(text(13, tokens ? plainTones(tokens).island.body : c.ink, { weight: 500 }), { text: (who) => `Agent · ${line(who)}` }),
      time: text(13, tokens ? plainTones(tokens).island.summary : '', { weight: 500 }),
    },
    warning: { label: '', time: plainTones(tokens).warn, chip: plainTones(tokens).warnChip, ring: plainTones(tokens).warnChip, mark: plainTones(tokens).warn },
    card: {
      width: 440,
      // The board draws the open card as a selected frame, named Island beside its corner.
      box: tokens ? { frame: { width: 1.5, color: c.accent } } : null,
      label: 'Island',
      ink: tokens ? plainTones(tokens).island.summary : '',
      head: 'Agent · lease',
      headColor: tokens ? plainTones(tokens).island.head : c.muted,
      who: line,
      unlocked: (hhmm) => `unlocked ${hhmm}`,
      unlockedColor: tokens ? plainTones(tokens).island.body : c.muted,
      left: 'left',
      tile: tokens ? plainTones(tokens).island.tile : c.muted,
      bar: 'round',
      barFill: tokens ? plainTones(tokens).bar : c.accent,
      keys: [['↵', 'lock now'], ['esc', 'close']],
    },
  };
}

// How the island draws a Taildrop send in place of the clock: an upload mark, the words with the percent in them (the machine's name elides) and a rounded bar after them; a colour left empty is the island's own text colour.
export function sendingLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const files = (count) => `${count} ${count === 1 ? 'file' : 'files'}`;
  return {
    width: 380,
    height: 40,
    pad: 16,
    gap: 10,
    mark: { shape: 'upload', size: 16, color: '' },
    parts: [{ font: t.ui, size: 13, color: '', weight: 500, spacing: 0, name: true, text: (count, to, pct) => `Sending ${files(count)} to ${line(to)} · ${pct}%` }],
    pct: null,
    bar: { at: 'inline', height: 6, radius: 3, track: tokens ? plainTones(tokens).island.tile : c.muted, fill: tokens ? plainTones(tokens).bar : c.accent },
  };
}

// How the island draws a YouTube download in place of the clock: a tile and the folder over a line and a bar; a failure keeps the box, drops the bar and shows a chip. A colour left empty is the island's own text colour.
export function downloadingLook(tokens) {
  const t = (tokens || UNTHEMED).type;
  const text = (size, color, extra) => Object.assign({ font: t.ui, size, color, weight: 400, spacing: 0 }, extra);
  const folders = { audio: '~/Music/YouTube', video: '~/Videos/YouTube' };
  return {
    width: 440,
    height: 76,
    pad: 16,
    gap: 6,
    tile: { size: 40, radius: 12, fill: plainTones(tokens).island.tile },
    head: Object.assign(text(12, plainTones(tokens).island.head), { left: 'YouTube', right: (kind) => folders[kind] ?? '' }),
    line: text(15, '', { weight: 700 }),
    bar: { height: 4, radius: 2, track: plainTones(tokens).island.tile, fill: plainTones(tokens).bar },
    chip: { fill: plainTones(tokens).warnChip, color: plainTones(tokens).warn, radius: 8, padX: 8, padY: 2 },
    failure: { mark: null, color: '', box: null },
  };
}

// C0 controls and DEL, which a file name from another machine may carry.
const CONTROLS = /[\u0000-\u001f\u007f]/g;

// How a file notification's chip draws in the toast, a centre row and the cursor row, its empty slot and the drag image.
export function chipLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  const label = (files) => line(chipLabel(files));
  const name = (files) => (files.length === 1 ? line(files[0].slice(files[0].lastIndexOf('/') + 1)).replace(CONTROLS, '') : label(files));
  const place = (fill, frame, text, grip, glyph, pad, radius) => ({ fill, frame, text, grip, glyph, pad, radius });
  const row = place(plainTones(tokens).tile, plainTones(tokens).tile, c.muted, plainTones(tokens).outline, c.muted, [5, 8, 5, 8], 8);
  return {
    label,
    name,
    font: t.ui,
    size: 11,
    spacing: 0,
    gap: 6,
    grip: { w: 8, h: 12, r: 1 },
    glyph: { w: 14, h: 14, stroke: 1.3, path: 'M3 1.5h5l3 3v8H3z M8 1.5v3h3' },
    // The toast's chip sits in a column beside the card.
    toastPlace: 'column',
    toast: place(plainTones(tokens).island.tile, plainTones(tokens).island.tile, plainTones(tokens).island.body, plainTones(tokens).island.head, plainTones(tokens).island.summary, [8, 10, 8, 10], 10),
    row,
    cursor: Object.assign({}, row, { fill: c.surface, frame: c.surface }),
    empty: { color: plainTones(tokens).bar, width: 1.5, content: false },
    drag: { fill: c.surface, frame: c.accent, frameWidth: 1.5, text: c.ink, grip: null, glyph: plainTones(tokens).deep, pad: [9, 12, 9, 12], gap: 8, size: 12, weight: 500, spacing: 0, radius: 10 },
  };
}

// How the island draws the volume or brightness OSD: one rounded bar of 20 steps and the value beside it.
export function osdLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  const t = (tokens || UNTHEMED).type;
  return {
    litCount: (v) => Math.round(Math.max(0, Math.min(100, v)) / 5),
    valueText: (v) => String(v),
    width: 300,
    height: 40,
    bars: 'round',
    lit: { color: tokens ? plainTones(tokens).bar : c.accent },
    unlit: { color: tokens ? plainTones(tokens).island.tile : c.muted },
    value: { font: t.ui, size: 13, weight: 600, color: '' },
  };
}

// How the calendar card's city column reads beside the month: home first and large with its mark, then each city, the offset and the day word under each name. A colour left empty is the island's own text colour.
export function clockLook(tokens) {
  const t = (tokens || UNTHEMED).type;
  const text = (font, size, extra) => Object.assign({ font, size, weight: 400, spacing: 0, color: '' }, extra);
  const head = plainTones(tokens).island.head;
  return {
    gridWidth: 224,
    gap: 22,
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
    grid: {
      weekStart: 0,
      weekdays: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'],
      cell: 32,
      rowHeight: 28,
      weekHeight: 28,
      rowGap: 0,
      gap: 6,
      title: { parts: (g) => [`${g.month} ${g.year}`], left: text(t.ui, 15, { weight: 500 }) },
      weekday: text(t.mono, 11, { color: plainTones(tokens).island.head }),
      day: text(t.mono, 12, { color: plainTones(tokens).island.body }),
      today: { w: 28, h: 24, radius: 8, inverted: true, fill: '', border: 0, borderColor: '', weight: 700 },
    },
  };
}

// Control, the notification centre, the cheat sheet, polkit and the recorder draw as the launcher does: its cursor row, rules and legend.
export function listLook(tokens) {
  const l = launcherLook(tokens);
  return Object.assign(l, {
    heading: (name) => name.charAt(0).toUpperCase() + same(name.slice(1)),
    tab: { fill: l.label.fill, text: l.label.color, radius: 8 },
    tabText: same,
    keyText: same,
    keys: (pairs) => pairs.map(([k, w]) => ({ key: same(k), word: same(w) })),
    groupHead: (app, n) => (line(app || '') ? `${line(app)} · ${n}` : String(n)),
    // An age in whole units, floored; under a minute it is the island's word for arrival.
    ageText(ms) {
      const s = Math.floor(ms / 1000);
      return s < 60 ? 'now' : s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`;
    },
  });
}

// How the margins read under a token set: Page 03, the app and title, an accent dot before the goal, and the date.
export function marginLook(tokens) {
  const c = (tokens || UNTHEMED).color;
  // A title is its file's name, which whoever sent the file chose; a control would draw as tofu, so it becomes a space.
  const words = (s) => line((s ?? '').replace(/[\u0000-\u001f\u007f-\u009f]/g, ' '));
  const look = {
    number: (idx) => `Page ${pad2(idx)}`,
    numberColor: c.ink,
    numberWeight: 600,
    // The focused column of its columns, two spaces after the number; a workspace of one column draws none.
    column: (pos) => (!pos || pos.of < 2 ? '' : `  ${pos.at} / ${pos.of}`),
    tail: (view) => (view.app === null && view.title === null ? '' : ` / ${words(view.app)} — ${words(view.title)}`),
    tailColor: c.muted,
    goal: (g) => (!g ? '' : g.left === null ? same(g.title) : `${same(g.title)} · ${same(g.left)}`),
    goalColor: c.ink,
    goalWeight: 500,
    dot: true,
    dotColor: c.accent,
    // Unread mail is something to act on, so it reads in ink.
    mail: (n) => (n > 0 ? `mail ${n}` : ''),
    mailColor: c.ink,
    mailWeight: 500,
    word: (w) => same(w).replace(/^wifi$/, 'Wi-Fi').replace(/^no wifi$/, 'No Wi-Fi'),
    date: (d) => same(dateText(d)),
    dateColor: c.muted,
    spacing: 16,
    // The urgent workspaces after the title, three spaces on: at most 3 accent dots before their ink numbers, then a count of the rest; each segment is drawn in its own colour.
    marks(idxs) {
      if (idxs.length === 0) return [];
      const rest = idxs.length - 3;
      const shown = idxs.slice(0, 3).reduce((segs, idx, i) => segs.concat([{ text: `${i ? '  ' : '   '}•`, color: c.accent }, { text: ` ${pad2(idx)}`, color: c.ink }]), []);
      return rest > 0 ? shown.concat([{ text: `  +${rest}`, color: c.ink }]) : shown;
    },
  };
  // The words on screen, in order, as the tests read them.
  look.drawn = (view, now, right) => ({
    left: look.number(view.idx) + look.tail(view),
    right: [right.sync && look.word(right.sync), look.goal(right.goal), look.mail(right.mail), right.wifi && look.word(right.wifi), right.battery && look.word(right.battery), look.date(now)]
      .filter((p) => p)
      .join(' '),
  });
  return look;
}

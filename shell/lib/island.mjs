// Pure pieces of the island, kept here so node can test them.

import { clockText } from './margins.mjs';

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

// The calendar and the sharing card are opened by hand, so only a question, or an agent's lease card, takes the island from them; LIVE gives way to a notification's 5 s and outranks the shell's own recording (7WVQMXDS), and an agent's lease slot, so a share shows while an agent holds the session (X1WV1TFF); a send can run for minutes, so a toast, the OSD or a notification (its own Sent among them) shows over it for its moment.
const PRIORITY = ['question', 'leaseCard', 'calendar', 'sharingCard', 'notification', 'sharing', 'lease', 'recording', 'osd', 'toast', 'capture', 'sending', 'playing'];

export const MAX_WIDTH = 560;

// Each slot is null when it has nothing to show.
export const pick = (slots) => PRIORITY.find((k) => slots[k]) ?? 'rest';

const pad = (n) => String(n).padStart(2, '0');

// mm:ss since a recording started; minutes run past 59 rather than adding hours.
export function recordingText(sinceMs, nowMs) {
  const s = Math.floor((nowMs - sinceMs) / 1000);
  return `${pad(Math.floor(s / 60))}:${pad(s % 60)}`;
}

const joined = (parts) => parts.filter((p) => p).join(' · ');
// C0 and C1 controls draw as tofu (U+0085 ends a line), and the bidi marks reorder what follows.
const oneLine = (s) =>
  String(s)
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ')
    .replace(/[\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
export const filesText = (count) => `${count} ${count === 1 ? 'file' : 'files'}`;

// What a share shows, as niri.mjs's shares give it: SCREEN, the window's app, or NOTHING while its target is cleared.
const seen = (s) => (s.target === 'screen' ? 'SCREEN' : s.target === 'nothing' ? 'NOTHING' : (oneLine(s.app ?? '') || 'window').toUpperCase());

// Two or more shares read as a count; one names its target, or PAUSED while niri holds it inactive (M5W7ZJ8V, SN5W2JY5).
export const liveText = (shares) => `LIVE ${shares.length > 1 ? `×${shares.length}` : shares[0].active ? seen(shares[0]) : 'PAUSED'}`;

// A card row: who watches a PipeWire share is a portal's client, and a screencopy one is its pid's process name, from names, until read its pid (MGX0WWS8).
export function shareRow(share, names) {
  const pipewire = share.kind === 'PipeWire';
  return { target: seen(share), watcher: pipewire ? 'portal share' : oneLine(names[share.pid] ?? '') || `pid ${share.pid}`, stop: pipewire };
}

export const shareRowText = (row) => [row.target, row.watcher, row.stop ? '↵ stop' : ''].filter((p) => p).join('  ');

// The reader prints each pid, a tab, its /proc comm (which ends in a newline) and a NUL; comm itself is the process's to name, so only that last newline goes.
export function commNames(text) {
  const names = {};
  for (const record of text.split('\0')) {
    const tab = record.indexOf('\t');
    const name = record.slice(tab + 1).replace(/\n$/, '');
    if (tab > 0 && name) names[record.slice(0, tab)] = name;
  }
  return names;
}

// niri stops a PipeWire share by its session, and a session can hold more than one stream (XPRY7NFD).
export const stopSessions = (shares) => [...new Set(shares.filter((s) => s.kind === 'PipeWire').map((s) => s.session))];

// dots-capture's result, from any caller of the IPC: its kind, a title (empty for a miss, which copied nothing) and a detail, each one line; a colour's detail is its hex, and a #RRGGBB one gives the swatch. No words or an unknown kind shows nothing.
export function captureOf(kind, title, detail) {
  const t = oneLine(title);
  const d = oneLine(detail);
  if (!['ocr', 'qr', 'colour'].includes(kind) || !(t || d)) return null;
  return { kind, title: t, detail: d, swatch: kind === 'colour' && /^#[0-9a-f]{6}$/i.test(d) ? d.toUpperCase() : null };
}

// A capture in one line, as `island state` and Artboard's card read it: Text copied · 214 characters, Copied #C8381E.
export const captureText = (c) => (c.kind === 'colour' ? [c.title, c.detail].filter((p) => p).join(' ') : joined([c.title, c.detail]));

// `qs ipc call island state` reports this text, whatever the theme draws.
export function islandText(mode, slots, now) {
  switch (mode) {
    case 'question':
      return [slots.question.text, ...slots.question.options.map((o, i) => `[${i + 1}] ${o}`)].join('  ');
    case 'notification':
      return joined([slots.notification.app, slots.notification.summary, slots.notification.body]);
    case 'sharing':
      return liveText(slots.sharing);
    case 'recording':
      return `REC ${slots.recording}`;
    case 'osd':
      return `${slots.osd.kind === 'volume' ? 'Volume' : 'Brightness'} ${slots.osd.value}%`;
    case 'calendar':
      return monthGrid(slots.calendar.year, slots.calendar.month).title;
    case 'toast':
      return slots.toast;
    case 'capture':
      return captureText(slots.capture);
    case 'sending':
      return `Sending ${filesText(slots.sending.count)} to ${oneLine(slots.sending.to)} · ${slots.sending.pct}%`;
    case 'playing':
      return `${[slots.playing.title, slots.playing.artist].filter((p) => p).join(' — ')}  ${clockText(now)}`;
    default:
      return slots.notice || clockText(now);
  }
}

export const boxWidth = (contentWidth) => Math.min(contentWidth, MAX_WIDTH);

// Weeks run Monday to Sunday unless a board starts them on weekStart (0 is Sunday); days outside the month are null.
export function monthGrid(year, month, weekStart = 1) {
  const lead = (new Date(year, month, 1).getDay() - weekStart + 7) % 7;
  const days = new Date(year, month + 1, 0).getDate();
  const cells = Array(lead).fill(null).concat(Array.from({ length: days }, (_, i) => i + 1));
  while (cells.length % 7) cells.push(null);
  const weeks = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return { title: `${MONTHS[month]} ${year}`, month: MONTHS[month], abbr: MONTHS[month].slice(0, 3), year, weeks, cells };
}

export function shiftMonth(year, month, by) {
  const d = new Date(year, month + by, 1);
  return { year: d.getFullYear(), month: d.getMonth() };
}

// The one-line modes the island closes into; the rest open it into a card.
export const isCompact = (mode) => ['rest', 'lease', 'sending', 'playing', 'sharing', 'recording', 'toast', 'capture'].includes(mode);

// Curves are 61 samples at even steps of time, which ease reads as CSS linear() does; Qt's BezierSpline crashed on a sampled curve.
const STEPS = 60;
const sampled = (at) => Array.from({ length: STEPS + 1 }, (_, i) => (i === 0 ? 0 : i === STEPS ? 1 : Math.round(at(i / STEPS) * 10000) / 10000));

// A unit-mass spring, as the approved prototype ran it; it ends within 1/within of rest, 0.2% unless told.
export function springCurve(stiffness, damping, within = 500) {
  const w0 = Math.sqrt(stiffness);
  const z = damping;
  const secs = z < 1 ? Math.log((1 + z / Math.sqrt(1 - z * z)) * within) / (z * w0) : 8.5 / w0;
  const at = (t) => {
    if (z >= 1) return 1 - Math.exp(-w0 * t) * (1 + w0 * t);
    const wd = w0 * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + ((z * w0) / wd) * Math.sin(wd * t));
  };
  return { ms: Math.round(secs * 1000), points: sampled((x) => at(x * secs)) };
}

// A CSS cubic-bezier(x1, y1, x2, y2), solved for its x by bisection.
function bezier(x1, y1, x2, y2) {
  const coord = (a, b, t) => 3 * a * t * (1 - t) ** 2 + 3 * b * t * t * (1 - t) + t ** 3;
  return sampled((x) => {
    let lo = 0;
    let hi = 1;
    for (let i = 0; i < 30; i++) {
      const mid = (lo + hi) / 2;
      if (coord(x1, x2, mid) < x) lo = mid;
      else hi = mid;
    }
    return coord(y1, y2, (lo + hi) / 2);
  });
}

// The value of a sampled curve at progress t, straight between samples.
export function ease(points, t) {
  if (t <= 0) return points[0];
  if (t >= 1) return points[STEPS];
  const i = Math.floor(t * STEPS);
  return points[i] + (points[i + 1] - points[i]) * (t * STEPS - i);
}

const LINEAR = sampled((x) => x);
// niri's curves for the same tokens, so the island moves as the windows do.
export const EASED = {
  snappy: { ms: 120, points: bezier(0.16, 1, 0.3, 1), swap: 'drop' },
  ease: { ms: 200, points: bezier(0.33, 1, 0.68, 1), swap: 'drop' },
  typewriter: { ms: 90, points: LINEAR, swap: 'scan' },
  linear: { ms: 150, points: LINEAR, swap: 'scan' },
};

// How the island morphs under a theme's motion token: the shape's open and close curves and how its content swaps; null before a theme loads.
export function islandMotion(motion) {
  if (motion === 'spring') {
    const open = springCurve(260, 0.7);
    return { open, close: springCurve(390, 0.78), swap: { kind: 'blur', inMs: Math.min(Math.max(Math.round(open.ms * 0.5), 180), 320), outMs: 130, delay: 60, blur: 6 } };
  }
  const e = EASED[motion];
  if (!e) return null;
  const swap = e.swap === 'drop' ? { kind: 'drop', inMs: Math.max(Math.round(e.ms * 0.8), 80), outMs: 60, delay: 20 } : { kind: 'scan', inMs: e.ms, outMs: 80, delay: 40 };
  return { open: { ms: e.ms, points: e.points }, close: { ms: Math.round(e.ms * 0.8), points: e.points }, swap };
}

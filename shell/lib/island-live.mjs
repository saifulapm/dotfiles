// Board 2's one-line states (2VC2VCJR): each is a 14 px filled icon, its short text, then the clock pinned right, 34 px tall.
import { clockText } from './margins.mjs';
import { deviceName } from './bt-pairing.mjs';
import { CONTROL, BIDI } from './clean.mjs';
import { liveText, filesText, captureText } from './island.mjs';

// Filled Material Design glyphs from the Symbols Nerd Font (the nerd-symbols pin), by their md- names.
export const ICONS = {
  music: '\u{F075A}',
  volume: '\u{F057E}',
  volumeOff: '\u{F0581}',
  brightness: '\u{F00DF}',
  mic: '\u{F036C}',
  cast: '\u{F0118}',
  record: '\u{F044A}',
  robot: '\u{F06A9}',
  upload: '\u{F0552}',
  download: '\u{F01DA}',
  headphones: '\u{F02CB}',
  eyedropper: '\u{F020A}',
  check: '\u{F012C}',
  alert: '\u{F0028}',
};

const oneLine = (s) =>
  String(s ?? '')
    .replace(CONTROL, ' ')
    .replace(BIDI, '')
    .replace(/\s+/g, ' ')
    .trim();

const pad2 = (n) => String(n).padStart(2, '0');
const left = (ms) => {
  const s = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(s / 60)}:${pad2(s % 60)}`;
};

const state = (icon, text, extra) => Object.assign({ icon, text: oneLine(text), tail: '', tone: 'normal', bar: null, swatch: '' }, extra);

function shape(mode, slots) {
  const s = slots[mode];
  switch (mode) {
    case 'playing':
      return state(ICONS.music, oneLine(s.title) || oneLine(s.artist));
    case 'osd':
      return state(s.kind === 'brightness' ? ICONS.brightness : s.value > 0 ? ICONS.volume : ICONS.volumeOff, `${s.value}%`, { bar: s.value });
    case 'mic':
      return state(ICONS.mic, `${s[0]}${s.length > 1 ? ` +${s.length - 1}` : ''}`, { tone: 'danger' });
    case 'sharing':
      return state(ICONS.cast, liveText(s), { tone: 'danger' });
    case 'recording':
      return state(ICONS.record, s, { tone: 'danger' });
    case 'lease':
      return state(ICONS.robot, s.who, { tail: left(s.left), tone: s.left <= 60000 ? 'danger' : 'normal' });
    case 'sending':
      return state(ICONS.upload, `${filesText(s.count)} to ${oneLine(s.to)}`, { bar: s.pct });
    case 'downloading':
      if (s.failure) return state(ICONS.alert, `${oneLine(s.failure.title)} · ${oneLine(s.failure.reason)}`, { tone: 'danger' });
      return state(ICONS.download, s.list ? `${s.n} / ${s.total}` : s.title, { tail: `${s.pct}%`, bar: s.pct });
    case 'btConnect':
      return state(ICONS.headphones, deviceName(s.name, s.address), { tail: s.battery === null ? '' : `${Math.round(s.battery * 100)}%` });
    case 'capture':
      return s.swatch ? state(ICONS.eyedropper, s.swatch, { swatch: s.swatch }) : state(ICONS.check, captureText(s));
    case 'toast':
      return state(ICONS.check, s);
    default:
      return slots.notice ? state(ICONS.alert, slots.notice, { tone: 'danger' }) : null;
  }
}

// What the one-line state of this mode draws, {icon, text, tail, tone, bar, swatch, clock}, or null for rest and the cards; tone is normal or danger, and bar is the pill's percent or null.
export function liveState(mode, slots, now) {
  const s = shape(mode, slots);
  return s && Object.assign(s, { clock: clockText(now) });
}

// The widest a one-line state grows; a longer text elides before the clock.
export const ONE_LINE_MAX = 560;
export const LIVE = { pad: 14, icon: 14, gap: 8, bar: 56, clockGap: 16, swatch: 14 };

// The box for drawn widths of its text, tail and clock, with or without a bar and a swatch.
export function liveWidth(w) {
  const L = LIVE;
  const parts = [L.icon, w.swatch ? L.swatch : 0, w.text, w.tail, w.bar ? L.bar : 0].filter((p) => p > 0);
  const row = parts.reduce((a, b) => a + b, 0) + L.gap * (parts.length - 1);
  return Math.min(ONE_LINE_MAX, Math.ceil(L.pad + row + L.clockGap + w.clock + L.pad));
}

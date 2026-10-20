// The theme picker's cursor, captions and specimens, from each theme's tokens alone, so a theme added later draws too; pure, so node tests what the shell imports.
import { marginLook, listLook, line } from './voice.mjs';
import { checkTokens } from './theme.mjs';
import { marginStyle } from './surface.mjs';
import { pad2 } from './margins.mjs';

export function step(names, name, by) {
  const i = Math.max(0, Math.min(names.length - 1, names.indexOf(name) + by));
  return names[i];
}

// themes.json is a file any process can write, so each entry passes the check shell.json passes, and one that fails gets no card.
export function cards(list) {
  if (!Array.isArray(list)) return [];
  const out = [];
  for (const t of list) {
    try {
      out.push(checkTokens(t));
    } catch (e) {
      continue;
    }
  }
  return out;
}

// A digit picks the card it numbers; a digit with no card leaves the cursor where it is.
export function jump(names, name, digit) {
  return names[digit - 1] ?? name;
}

// The card the cursor lands on plays its theme's desktop switch in miniature, as Paper.qml plays it full size.
export function previewSwitch(motion, slowdown) {
  const kind = { snappy: 'slide', spring: 'zoom', linear: 'scan' }[motion] ?? 'cut';
  return { kind, ms: kind === 'cut' ? 0 : 220 * slowdown };
}

const WORDS = { paper: { flat: 'flat', grain: 'grain', dots: 'dots', grid: 'grid', gradient: 'gradient' }, frame: { none: 'no frame' }, shadow: { 'hard-offset': 'hard', none: 'no' } };
const word = (kind, v) => WORDS[kind][v] ?? v;
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const COUNT = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
// An open can come before the theme's tokens load; until then the picker draws in black and white.
const UNTHEMED = { name: '', color: { paper: 'black', ink: 'white', muted: 'gray', line: 'gray', surface: 'black', accent: 'white' }, type: { display: '', ui: '', mono: '', voice: 'caps' } };
// Artboard's tiles, a board tint no token carries.
const TILE = '#F6F7F9';

// A card's name in its own theme's typeface and voice; the picker draws it in the current theme's ink, so it always reads.
export function cardName(t) {
  const name = line(t.name);
  if (t.type.voice === 'bracket') return { text: name.toUpperCase(), font: t.type.ui, size: 14, weight: 700, spacing: 1.12 };
  if (t.type.voice === 'plain') return { text: cap(name), font: t.type.ui, size: 16, weight: 700, spacing: -0.16 };
  return { text: cap(name), font: t.type.display, size: 26, weight: 400, spacing: 0 };
}

// Its primitives in a line, in its own voice: grain, ink, a hard shadow; Dots · soft shadow · round; GRID // GLOW // CUT.
export function tagline(t) {
  const p = t.primitive;
  if (t.type.voice === 'bracket') {
    return { text: [word('paper', p.paper), word('frame', p.frame), p.corner].join(' // ').toUpperCase(), font: t.type.ui, size: 9, italic: false, spacing: 1.26 };
  }
  if (t.type.voice === 'plain') {
    return { text: `${cap(word('paper', p.paper))} · ${word('shadow', p.shadow)} shadow · ${p.corner}`, font: t.type.ui, size: 11, italic: false, spacing: 0 };
  }
  return { text: `${word('paper', p.paper)}, ${word('frame', p.frame)}, a ${word('shadow', p.shadow)} shadow`, font: t.type.display, size: 15, italic: true, spacing: 0 };
}

// The panel as the current theme's Themes board dresses it: its header, tiles, cursor, tags and keys.
export function pickerLook(themed) {
  const tokens = themed || UNTHEMED;
  const l = listLook(themed);
  const c = tokens.color;
  const t = tokens.type;
  const voice = t.voice;
  const base = {
    voice,
    small: l.small,
    rule: l.rule,
    chips: voice === 'plain',
    chip: l.chip,
    legend: (n) => l.keys([['j/k', 'choose'], [n > 1 ? `1–${Math.min(n, 9)}` : '1', 'jump'], ['↵', 'apply']]),
    esc: l.keyText('esc'),
    number: () => '',
  };
  if (voice === 'plain') {
    return Object.assign(base, {
      header: (n) => ({ title: 'Themes', font: t.ui, size: 20, weight: 700, color: c.ink, sub: `${n} themes`, subFont: t.ui, subSize: 13, italic: false, right: '' }),
      tag: (current, cursor) => (current ? { text: 'Current', color: c.accent, fill: l.cursor.fill, border: 'transparent', radius: 6 } : cursor ? { text: '↵', color: l.cursor.text, fill: l.cursor.fill, border: 'transparent', radius: 6 } : null),
      tile: { fill: TILE, border: { width: 0, color: 'transparent' }, radius: 12, pad: 10 },
      cursor: { fill: c.surface, border: { width: 1.5, color: c.accent }, shadow: { kind: 'soft', x: 0, y: 8, blur: 20, spread: -10, color: c.accent, alpha: 0.45 }, radius: 12, ticks: false },
    });
  }
  if (voice === 'bracket') {
    return Object.assign(base, {
      header: (n, current) => ({ title: 'THEMES', font: t.mono, size: 11, weight: 700, color: c.accent, sub: ` // ${n} SHEETS`, subFont: t.mono, subSize: 11, italic: false, right: `ACTIVE: ${current.toUpperCase()}` }),
      tag: (current, cursor) => (current ? { text: '[ACTIVE]', color: c.accent, fill: 'transparent', border: 'transparent', radius: 0 } : cursor ? { text: '[↵]', color: c.accent, fill: 'transparent', border: 'transparent', radius: 0 } : null),
      number: (i) => pad2(i + 1),
      tile: { fill: 'transparent', border: { width: 1, color: c.line }, radius: 0, pad: 9 },
      cursor: { fill: c.surface, border: { width: 1, color: c.accent }, shadow: { kind: 'glow', x: 0, y: 0, blur: 14, spread: 0, color: c.accent, alpha: 0.3 }, ticks: true },
    });
  }
  return Object.assign(base, {
    header: (n, current) => ({ title: 'Themes', font: t.display, size: 34, weight: 400, color: c.ink, sub: `${COUNT[n] ?? n} on the shelf`, subFont: t.display, subSize: 18, italic: true, right: `${current.toUpperCase()} IN USE` }),
    tag: (current) => (current ? { text: 'IN USE', color: c.accent, fill: 'transparent', border: c.accent, radius: 0 } : null),
    tile: { fill: 'transparent', border: { width: 1, color: c.line }, radius: 0, pad: 8 },
    cursor: { fill: c.surface, border: { width: 2, color: c.accent }, shadow: { kind: 'hard', x: 4, y: 4, blur: 0, spread: 0, color: c.accent, alpha: 1 }, ticks: false },
  });
}

// One fixed moment, so every card reads the same scene in its own voice and no clock ticks for it.
const SCENE = { view: { idx: 3, app: 'foot', title: '~' }, goal: { title: 'Ship v2', left: '3d' }, date: new Date(2026, 9, 18), clock: '14:32' };

// niri writes #RRGGBBAA where Qt reads #AARRGGBB; alpha scales the alpha, and a colour with neither stays as written.
function qtColor(hex, alpha = 1) {
  if (hex.length === 7 && alpha === 1) return hex;
  const a = hex.length === 9 ? parseInt(hex.slice(7), 16) : 255;
  return '#' + Math.round(a * alpha).toString(16).padStart(2, '0') + hex.slice(1, 7);
}

// A window as niri frames it under these tokens, at half size: the border or focus ring, the shadow and the corner.
export function windowLook(tokens, focused) {
  const c = tokens.color;
  const n = tokens.niri;
  const border = tokens.primitive.frame !== 'none' && n.border > 0;
  const frame = border
    ? { width: 1, color: focused ? (tokens.primitive.frame === 'glow' ? c.accent : c.ink) : qtColor(n.border_inactive ?? c.muted) }
    : focused && n.ring_width ? { width: n.ring_width * 0.75, color: qtColor(n.ring_color ?? c.accent) } : { width: 0, color: 'transparent' };
  // An unfocused window without its own shadow colour gets niri's default, the focused colour at 0.75.
  const color = !n.shadow_color ? null : focused ? qtColor(n.shadow_color) : n.shadow_inactive ? qtColor(n.shadow_inactive) : qtColor(n.shadow_color, 0.75);
  const [ox, oy] = n.shadow_offset ?? [0, 0];
  const shadow = color ? { x: Math.round(ox / 2), y: Math.round(oy / 2), blur: Math.round((n.shadow_softness ?? 30) / 2), color } : null;
  return { fill: c.surface, frame, shadow, radius: tokens.primitive.corner === 'round' ? 6 : 0 };
}

// A name in the terminal line keeps what fits its window: blueprint, nine letters, is the longest whole.
const short = (n) => (n.length > 9 ? n.slice(0, 8) + '…' : n);

// Four lines of a shell session in the theme's ANSI colours: blue paths, a red prompt, a green pass, yellow hashes.
export function terminalLines(tokens) {
  const a = tokens.color.ansi;
  const ink = tokens.color.ink;
  const prompt = (cmd) => [{ text: '~/S/g/dotfiles ', color: a[4] }, { text: '❯ ', color: a[1] }, { text: cmd, color: ink }];
  return [
    prompt('just test'),
    [{ text: '✓ 42 passed', color: a[2] }, { text: ' · 0.9 s', color: tokens.color.muted }],
    prompt('git log -1'),
    [{ text: 'a1e9e71 ', color: a[3] }, { text: `${short(line(tokens.name))} on the shelf`, color: ink }],
  ];
}

// The palette strip: ink, ANSI 1 to 6, then the paper.
export const swatches = (tokens) => [tokens.color.ink, ...tokens.color.ansi.slice(1, 7), tokens.color.paper];

// The specimen's margins as the theme's margins would read the scene, and its island's clock.
export function specimenMargins(tokens) {
  const look = marginLook(tokens);
  const style = marginStyle(tokens);
  return {
    number: look.number(SCENE.view.idx),
    numberColor: look.numberColor,
    tail: look.tail(SCENE.view),
    goal: look.goal(SCENE.goal),
    goalColor: look.goalColor,
    date: (look.sep ? ` ${look.sep} ` : '  ') + look.date(SCENE.date),
    font: style.font,
    rules: style.rules,
    tracking: style.tracking / 2,
    clock: SCENE.clock,
  };
}

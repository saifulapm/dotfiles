// The theme picker's cursor, captions and specimens, from each theme's tokens alone, so a theme added later draws too; pure, so node tests what the shell imports.
import { marginLook, listLook, line, plainTones } from './voice.mjs';
import { checkTokens } from './theme.mjs';
import { marginStyle } from './surface.mjs';
import { SWITCH } from './switch.mjs';

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

// The card the cursor lands on plays the desktop's crossfade in miniature, as Paper.qml plays it full size.
export const previewSwitch = (slowdown) => ({ kind: SWITCH.kind, ms: SWITCH.ms * slowdown });

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
// An open can come before the theme's tokens load; until then the picker draws in black and white.
const UNTHEMED = { name: '', color: { paper: 'black', ink: 'white', muted: 'gray', line: 'gray', surface: 'black', accent: 'white' }, type: { display: '', ui: '', mono: '', voice: 'plain' } };

// A card's name in the picker's type; the picker draws it in the current scheme's ink, so it always reads.
export function cardName(t) {
  return { text: cap(line(t.name)), font: t.type.ui, size: 16, weight: 700, spacing: -0.16 };
}

// Whether the scheme is light or dark; every scheme wears the one design, so its primitives say nothing.
export function tagline(t) {
  return { text: cap(t.mode), font: t.type.ui, size: 11, italic: false, spacing: 0 };
}

// The panel as the current theme's Themes board dresses it: its header, tiles, cursor, tags and keys.
export function pickerLook(themed) {
  const tokens = themed || UNTHEMED;
  const l = listLook(themed);
  const c = tokens.color;
  const t = tokens.type;
  return {
    small: l.small,
    rule: l.rule,
    chip: l.chip,
    legend: (n) => l.keys([['j/k', 'choose'], [n > 1 ? `1–${Math.min(n, 9)}` : '1', 'jump'], ['↵', 'apply']]),
    esc: l.keyText('esc'),
    header: (n) => ({ title: 'Themes', font: t.ui, size: 20, weight: 700, color: c.ink, sub: `${n} themes`, subFont: t.ui, subSize: 13, italic: false, right: '' }),
    tag: (current, cursor) => (current ? { text: 'Current', color: l.label.color, fill: l.cursor.fill, border: 'transparent', radius: 6 } : cursor ? { text: '↵', color: l.cursor.text, fill: l.cursor.fill, border: 'transparent', radius: 6 } : null),
    tile: { fill: plainTones(themed).field, border: { width: 0, color: 'transparent' }, radius: 12, pad: 10 },
    cursor: { fill: c.surface, border: { width: 1.5, color: c.accent }, radius: 12 },
  };
}

// One fixed moment, so every card reads the same scene in its own voice and no clock ticks for it.
const SCENE = { view: { idx: 3, app: 'foot', title: '~' }, goal: { title: 'Ship v2', left: '3d' }, date: new Date(2026, 9, 18), clock: '14:32' };

// niri writes #RRGGBBAA where Qt reads #AARRGGBB; alpha scales the alpha, and a colour with neither stays as written.
function qtColor(hex, alpha = 1) {
  if (hex.length === 7 && alpha === 1) return hex;
  const a = hex.length === 9 ? parseInt(hex.slice(7), 16) : 255;
  return '#' + Math.round(a * alpha).toString(16).padStart(2, '0') + hex.slice(1, 7);
}

// A window as niri frames it, at half size: a 1 px frame in ink when focused and in the inactive colour when not, square, no shadow.
export function windowLook(tokens, focused) {
  const c = tokens.color;
  return { fill: c.surface, frame: { width: 1, color: focused ? c.ink : qtColor(tokens.niri.border_inactive ?? c.line) }, radius: 0 };
}

// A name in the terminal line keeps what fits its window: nine letters whole, a longer one cut.
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

// The panel holds up to four cards at 326 px between 22 px sides and 16 px gaps; a fifth card shrinks them instead of widening it, and a screen too narrow for that leaves a 24 px gutter on each side.
export function panelWidth(n, screenWidth) {
  const held = Math.min(Math.max(1, n), 4);
  return Math.min(44 + held * 326 + (held - 1) * 16, screenWidth - 48);
}

export function cardWidth(n, screenWidth) {
  const count = Math.max(1, n);
  return (panelWidth(n, screenWidth) - 44 - (count - 1) * 16) / count;
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
    date: '  ' + look.date(SCENE.date),
    font: style.font,
    rules: style.rules,
    tracking: style.tracking / 2,
    clock: SCENE.clock,
  };
}

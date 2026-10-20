// The theme picker's cursor, captions and specimens, from each theme's tokens alone, so a theme added later draws too; pure, so node tests what the shell imports.
import { marginLook } from './voice.mjs';
import { marginStyle } from './surface.mjs';

export function step(names, name, by) {
  const i = Math.max(0, Math.min(names.length - 1, names.indexOf(name) + by));
  return names[i];
}

export function summary(t) {
  const frame = t.primitive.frame === 'none' ? 'no frame' : t.primitive.frame;
  const shadow = t.primitive.shadow === 'hard-offset' ? 'hard' : t.primitive.shadow === 'none' ? 'no' : t.primitive.shadow;
  return `${t.mode} · ${frame} · ${shadow} shadow`;
}

// One fixed moment, so every card reads the same scene in its own voice and no clock ticks for it.
const SCENE = { view: { idx: 3, app: 'foot', title: '~' }, goal: { title: 'Ship v2', left: '3d' }, date: new Date(2026, 9, 18), clock: '14:32' };

// niri writes #RRGGBBAA where Qt reads #AARRGGBB; alpha scales the alpha.
function qtColor(hex, alpha = 1) {
  const a = hex.length === 9 ? parseInt(hex.slice(7), 16) : 255;
  return '#' + Math.round(a * alpha).toString(16).padStart(2, '0') + hex.slice(1, 7);
}

// A window as niri frames it under these tokens, at half size: the border or focus ring, the shadow and the corner.
export function windowLook(tokens, focused) {
  const c = tokens.color;
  const n = tokens.niri;
  const border = tokens.primitive.frame !== 'none' && n.border > 0;
  const frame = border
    ? { width: 1, color: focused ? (tokens.primitive.frame === 'glow' ? c.accent : c.ink) : (n.border_inactive ?? c.muted) }
    : focused && n.ring_width ? { width: n.ring_width * 0.75, color: n.ring_color ?? c.accent } : { width: 0, color: 'transparent' };
  // An unfocused window without its own shadow colour gets niri's default, the focused colour at 0.75.
  const color = !n.shadow_color ? null : focused ? qtColor(n.shadow_color) : n.shadow_inactive ? qtColor(n.shadow_inactive) : qtColor(n.shadow_color, 0.75);
  const [ox, oy] = n.shadow_offset ?? [0, 0];
  const shadow = color ? { x: Math.round(ox / 2), y: Math.round(oy / 2), blur: Math.round((n.shadow_softness ?? 30) / 2), color } : null;
  return { fill: c.surface, frame, shadow, radius: tokens.primitive.corner === 'round' ? 6 : 0 };
}

// Four lines of a shell session in the theme's ANSI colours: blue paths, a red prompt, a green pass, yellow hashes.
export function terminalLines(tokens) {
  const a = tokens.color.ansi;
  const ink = tokens.color.ink;
  const prompt = (cmd) => [{ text: '~/S/g/dotfiles ', color: a[4] }, { text: '❯ ', color: a[1] }, { text: cmd, color: ink }];
  return [
    prompt('just test'),
    [{ text: '✓ 42 passed', color: a[2] }, { text: ' · 0.9 s', color: tokens.color.muted }],
    prompt('git log -1'),
    [{ text: 'a1e9e71 ', color: a[3] }, { text: `${tokens.name} on the shelf`, color: ink }],
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

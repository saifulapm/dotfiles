// A colorscheme holds colour only; every scheme wears the one design below, which the renderers take as a theme.
import { contrast, validateTheme } from './theme.mjs';
import { mix } from './notes-look.mjs';

export const DEFAULT = 'artboard';

const KEYS = {
  meta: ['name', 'title', 'family', 'variant', 'source', 'licence'],
  color: ['paper', 'surface', 'ink', 'muted', 'line', 'accent', 'danger', 'ok', 'ansi'],
  syntax: ['keyword', 'function', 'string', 'type', 'value', 'variable', 'attribute', 'meta', 'builtin', 'comment'],
};
const HEX = /^#[0-9A-Fa-f]{6}$/;

export function validateColorscheme(doc) {
  const fail = (msg) => { throw new Error(`colorscheme: ${msg}`); };
  for (const section of Object.keys(doc)) {
    if (!(section in KEYS)) fail(`[${section}]: ${section} is no colorscheme key; a colorscheme holds colour only`);
    for (const k of Object.keys(doc[section])) if (!KEYS[section].includes(k)) fail(`${section}.${k} is no colorscheme key`);
  }
  for (const section of Object.keys(KEYS)) if (!doc[section]) fail(`missing [${section}]`);
  const { meta, color, syntax } = doc;
  for (const k of KEYS.meta) if (typeof meta[k] !== 'string' || !meta[k]) fail(`meta.${k} is missing`);
  if (meta.variant !== 'light' && meta.variant !== 'dark') fail(`meta.variant: "${meta.variant}" is not light or dark`);
  for (const k of KEYS.color) if (k !== 'ansi' && !HEX.test(color[k] ?? '')) fail(`color.${k}: "${color[k]}" is not #RRGGBB`);
  if (!Array.isArray(color.ansi) || color.ansi.length !== 16 || !color.ansi.every((c) => HEX.test(c))) fail('color.ansi must hold 16 #RRGGBB colours');
  for (const k of KEYS.syntax) if (!HEX.test(syntax[k] ?? '')) fail(`syntax.${k}: "${syntax[k]}" is not #RRGGBB`);
  const ratio = contrast(color.ink, color.surface);
  if (ratio < 4.5) fail(`contrast of ink on surface is ${ratio.toFixed(2)}:1, under 4.5:1`);
  // Every colour drawn as text reads on the surface: words at 4.5:1, a comment and the ANSI hues at 3:1; ink reads on line too, the selection's ground.
  const floor = (what, hex, ground, min) => { const r = contrast(hex, ground); if (r < min) fail(`${what}: contrast ${r.toFixed(2)}:1 on ${ground === color.line ? 'line' : 'surface'}, under ${min}:1`); };
  floor('ink on line', color.ink, color.line, 4.5);
  for (const k of ['muted', 'accent', 'danger', 'ok']) floor(`color.${k}`, color[k], color.surface, 4.5);
  for (const k of KEYS.syntax) floor(`syntax.${k}`, syntax[k], color.surface, k === 'comment' ? 3 : 4.5);
  // Slots 0, 7, 8 and 15 are black, white and their bright pair, which some schemes draw as grounds.
  color.ansi.forEach((hex, i) => { if (![0, 7, 8, 15].includes(i)) floor(`color.ansi ${i}`, hex, color.surface, 3); });
  return Object.assign({}, meta, { color: Object.assign({}, color, { ansi: [...color.ansi] }), syntax: Object.assign({}, syntax) });
}

// The frame: the line, moved toward ink until it shows at 1.4:1 on the surface, so no scheme's floating windows and cards go frameless.
function frameOf(c) {
  let share = 0;
  while (share < 1 && contrast(mix(c.line, c.ink, share), c.surface) < 1.4) share = Math.round((share + 0.02) * 100) / 100;
  return share ? mix(c.line, c.ink, share).toUpperCase() : c.line;
}

// The field, in the scheme's own colours: one diagonal grade from its paper into a soft wash of its accent, which the desk draws and every clear window shows.
function fieldOf(c, mode) {
  const share = mode === 'dark' ? 0.2 : 0.14;
  return { grade: { from: c.paper, to: mix(c.paper, c.accent, share).toUpperCase() } };
}

// A floating window's edge: the accent fading into the paper, and a dimmer run of the same when it is not focused.
function edgeOf(c) {
  const wash = (share) => mix(c.paper, c.accent, share).toUpperCase();
  return { from: c.accent, to: wash(0.35), dimFrom: wash(0.45), dimTo: wash(0.15) };
}

// The design system: Artboard's dots, geometry and spring, square, a quiet 1 px line frame on every window and surface, no shadow, Maple Mono in the plain voice.
export function designOf(s) {
  const doc = {
    meta: { name: s.name, mode: s.variant },
    color: s.color,
    syntax: s.syntax,
    primitive: { paper: 'dots', frame: 'line', shadow: 'none', corner: 'square', motion: 'spring' },
    paper: Object.assign({ spacing: 16, dot: s.color.line }, fieldOf(s.color, s.variant)),
    type: { display: 'Maple Mono', ui: 'Maple Mono', mono: 'Maple Mono', voice: 'plain', scale: 1 },
    niri: {
      gaps: 0, border: 1, border_inactive: frameOf(s.color), edge: edgeOf(s.color),
      tab_position: 'top', tab_width: 4, tab_gap: 8, tab_length: 0.3, tab_gaps: 8,
    },
  };
  return Object.assign(validateTheme(doc), { title: s.title, family: s.family });
}

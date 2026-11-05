// A colorscheme holds colour only; every scheme wears the one design below, which the renderers take as a theme.
import { contrast, validateTheme } from './theme.mjs';

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
  return Object.assign({}, meta, { color: Object.assign({}, color, { ansi: [...color.ansi] }), syntax: Object.assign({}, syntax) });
}

// The design system: Artboard's dots, geometry and spring, square, a quiet 1 px line frame on every window and surface, no shadow, Maple Mono in the plain voice.
export function designOf(s) {
  const doc = {
    meta: { name: s.name, mode: s.variant },
    color: s.color,
    syntax: s.syntax,
    primitive: { paper: 'dots', frame: 'line', shadow: 'none', corner: 'square', motion: 'spring' },
    paper: { spacing: 16, dot: s.color.line },
    type: { display: 'Maple Mono', ui: 'Maple Mono', mono: 'Maple Mono', voice: 'plain', scale: 1 },
    niri: {
      gaps: 28, border: 1, border_inactive: s.color.line,
      tab_position: 'top', tab_width: 4, tab_gap: 8, tab_length: 0.3, tab_gaps: 8,
    },
  };
  return Object.assign(validateTheme(doc), { title: s.title, family: s.family });
}

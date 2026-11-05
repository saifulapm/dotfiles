// How a surface looks under a token set, on the one design: the scheme's surface in a 1 px ink frame, square, with no shadow.
import { contrast } from './theme.mjs';

// A light scheme's text on its ink slab: the paper where it reads at 4.5:1 there, else the surface, which ink always reads on.
export const slabText = (c) => (contrast(c.paper, c.ink) >= 4.5 ? c.paper : c.surface);

// A chip is the island drawn small, inside a theme picker's specimen.
const islandish = (role) => role === 'island' || role === 'chip';

export function surfaceStyle(tokens, role) {
  if (!tokens) return { fill: 'transparent', text: 'transparent', frame: { width: 0, color: 'transparent' }, wash: 0 };
  const c = tokens.color;
  // A light scheme's island is an ink slab its light text reads on; a dark scheme's ink is light, so its island is its surface.
  const slab = islandish(role) && tokens.mode !== 'dark';
  return {
    fill: slab ? c.ink : c.surface,
    text: slab ? slabText(c) : c.ink,
    frame: { width: islandish(role) ? 0 : 1, color: c.ink },
    wash: 0.72,
  };
}

// The margins' type: the ui face at 12 px, in sentence case, ruled in ink.
export function marginStyle(tokens) {
  return { font: tokens ? tokens.type.ui : '', size: 12, caps: false, tracking: 0 };
}

// A surface's look with some parts swapped, as the island's lease draws its last minute: fill, text and frame.
export function restyled(style, swap) {
  if (!swap) return style;
  return Object.assign({}, style, { fill: swap.fill ?? style.fill, text: swap.text ?? style.text, frame: swap.frame ?? style.frame });
}

// How a surface looks under a token set, from its primitives only, so any mix of the menus draws.
import { glass as hifiGlass } from './hifi.mjs';

const SOFT = {
  island: { y: 12, blur: 32, spread: -6, alpha: 0.45 },
  card: { y: 32, blur: 64, spread: -12, alpha: 0.28 },
  chip: { y: 4, blur: 10, spread: -3, alpha: 0.4 },
};
const GLOW = { island: { blur: 8, alpha: 0.35 }, card: { blur: 14, alpha: 0.28 }, chip: { blur: 4, alpha: 0.35 } };
const HARD = { island: 3, card: 6, chip: 2 };
const ROUND = { island: 17, card: 14, chip: 8 };
// The token note's 12 px chamfer on full surfaces; the 34 px island uses the designs' 10, and a specimen's 16 px chip 5.
const CHAMFER = { island: 10, card: 12, chip: 5 };
// Shadows keep the designs' CSS box-shadow numbers; Surface.qml converts the blur for Qt.
const NO_SHADOW ={ kind: 'none', x: 0, y: 0, blur: 0, spread: 0, color: 'transparent', alpha: 0 };

// A chip is the island drawn small, inside a theme picker's specimen.
const islandish = (role) => role === 'island' || role === 'chip';

function frameOf(p, c, role) {
  if (islandish(role)) return { width: p.frame === 'glow' ? 1 : 0, color: p.frame === 'glow' ? c.accent : c.ink };
  if (p.frame === 'glow') return { width: 1, color: c.accent };
  // With no frame the focused card shows a 1.5 px accent selection outline instead.
  if (p.frame === 'none') return { width: role === 'card' ? 1.5 : 0, color: c.accent };
  // Frost's hairline is its 1 px frost-white edge, which carries its own alpha.
  if (p.frame === 'hairline' && c.edge) return { width: 1, color: c.edge };
  const width = p.frame === 'double' ? 3 : role === 'card' ? 1.5 : 1;
  return { width, color: p.frame === 'hairline' ? c.line : c.ink };
}

function shadowOf(p, c, role) {
  if (p.shadow === 'hard-offset') {
    const d = HARD[role];
    return { kind: 'hard', x: d, y: d, blur: 0, spread: 0, color: islandish(role) ? c.accent : c.ink, alpha: 1 };
  }
  if (p.shadow === 'soft') {
    const s = SOFT[role];
    return { kind: 'soft', x: 0, y: s.y, blur: s.blur, spread: s.spread, color: c.ink, alpha: s.alpha };
  }
  if (p.frame === 'glow') return { kind: 'glow', x: 0, y: 0, blur: GLOW[role].blur, spread: 0, color: c.accent, alpha: GLOW[role].alpha };
  return NO_SHADOW;
}

export function surfaceStyle(tokens, role) {
  if (!tokens) {
    return {
      fill: 'transparent',
      text: 'transparent',
      frame: { width: 0, color: 'transparent' },
      corner: { radius: 0, chamfer: 0 },
      shadow: NO_SHADOW,
      wash: 0,
      misregistered: false,
      handles: false,
      ticks: false,
    };
  }
  const p = tokens.primitive;
  const c = tokens.color;
  // Hi-Fi's island is a dark glass display in a 1 px line frame, so Blueprint's layout reads on it as on Blueprint's dark island.
  const glass = islandish(role) && tokens.type.engraved === true;
  // A dark theme's ink is light, so its island is its surface instead, and the island's light text reads on it.
  const inkIsland = islandish(role) && p.frame !== 'glow' && !glass && tokens.mode !== 'dark';
  // A theme that blurs (Frost) draws every panel and its island as glass in the frost-white edge, over the 62 % wash of its launcher board.
  const blurred = tokens.niri?.blur === true;
  const style = {
    fill: glass || blurred ? c.glass : inkIsland ? c.ink : c.surface,
    text: inkIsland ? c.paper : c.ink,
    frame: glass ? { width: 1, color: c.line } : blurred && c.edge ? { width: 1, color: c.edge } : frameOf(p, c, role),
    // A card rounds like the theme's windows when niri names their radius, and so does a blurred island.
    corner: { radius: p.corner === 'round' ? ((role === 'card' || (blurred && role === 'island')) && tokens.niri?.radius) || ROUND[role] : 0, chamfer: p.corner === 'cut' ? CHAMFER[role] : 0 },
    shadow: shadowOf(p, c, role),
    wash: p.frame === 'none' || blurred ? 0.62 : 0.72,
    misregistered: islandish(role) && p.shadow === 'hard-offset',
    handles: role === 'card' && p.frame === 'none',
    ticks: role === 'card' && p.corner === 'cut',
  };
  // The glass catches light along its top edge in every island mode; only glass has the key, so Surface draws no line for the other themes.
  if (glass) style.highlight = hifiGlass(tokens).highlight;
  // A Hi-Fi panel is lit like the focused window, whose niri border and shadow are the same amber hairline and #FABD2F38 glow over 24 px.
  if (tokens.type.engraved === true && role === 'card') {
    style.frame = { width: 1, color: c.accent };
    style.shadow = { kind: 'glow', x: 0, y: 0, blur: 24, spread: 0, color: c.accent, alpha: 0.22 };
    style.highlight = hifiGlass(tokens).highlight;
  }
  return style;
}

// Monospace labels read as drafting captions, so they go uppercase and tracked like the designs.
export function marginStyle(tokens) {
  if (!tokens) return { font: '', size: 11, caps: true, tracking: 1.32, rules: false };
  const mono = tokens.type.voice !== 'plain';
  return {
    font: tokens.type.ui,
    size: mono ? 11 : 12,
    caps: mono,
    tracking: mono ? 1.32 : 0,
    rules: ['ink', 'hairline', 'double'].includes(tokens.primitive.frame),
  };
}

// A surface's look with some parts swapped, as the island's lease draws its last minute and Artboard's selected card: fill, text, frame, glow or hard-shadow colour, and handles.
export function restyled(style, swap) {
  if (!swap) return style;
  return Object.assign({}, style, {
    fill: swap.fill ?? style.fill,
    text: swap.text ?? style.text,
    frame: swap.frame ?? style.frame,
    shadow: swap.glow ? Object.assign({}, style.shadow, { color: swap.glow }) : style.shadow,
    handles: swap.handles ?? style.handles,
    handleFill: swap.handleFill ?? style.handleFill,
  });
}

// Hi-Fi's own parts as its boards draw them: pilot lamps, glass and the tuning scale. They key on voice engraved (ruling HYZ253HJ), so any engraved token set draws them.
export const isHifi = (tokens) => tokens?.type.engraved === true;

// The board colours no token carries (ruling E77FYW02): an unlit lamp, the launcher's lit row, the groove under the bar, the lock's walnut cheeks.
export const HIFI = { unlit: '#3C3836', lit: '#32302F', groove: '#0E0F10', walnut: '#3A2A1F' };

// A colour at an alpha, as Qt's #AARRGGBB.
const alpha = (hex, a) => `#${Math.round(a * 255).toString(16).padStart(2, '0').toUpperCase()}${hex.slice(1)}`;

// A round pilot lamp, 6 px in the bar and 7 px in the launcher: lit is amber with a glow, red marks a deadline, green the theme in use.
export function lamp(tokens, state, size = 6) {
  const c = tokens.color;
  const color = { lit: c.accent, red: c.danger, green: c.ok }[state] ?? HIFI.unlit;
  return { size, color, glow: color === HIFI.unlit ? 'transparent' : color };
}

// A glass display: the glass token in a 1 px line frame, under a 1 px highlight of ink at 6 %.
export function glass(tokens) {
  const c = tokens.color;
  return { fill: c.glass, border: c.line, borderWidth: 1, highlight: alpha(c.ink, 0.06) };
}

// A tuning scale along a glass display's bottom edge: amber ticks every 8 px at 28 %, every 40 px at 50 %, and a 2 px red pointer at a fraction of the width.
export function tuningScale(tokens, width, at) {
  const c = tokens.color;
  const ticks = [];
  for (let x = 0; x < width; x += 8) ticks.push({ x, major: x % 40 === 0, color: alpha(c.accent, x % 40 === 0 ? 0.5 : 0.28) });
  const x = Math.max(0, Math.min(width - 2, Math.round(at * width) - 1));
  return { ticks, pointer: { x, width: 2, color: c.danger } };
}

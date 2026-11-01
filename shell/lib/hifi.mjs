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

// The paper switch: Hi-Fi's dial sweep whenever Hi-Fi is either side, so every other pair keeps the outgoing theme's own motion.
export function switchKind(outgoing, incoming) {
  if (outgoing.primitive.motion === 'dial' || incoming.primitive.motion === 'dial') return 'sweep';
  return { snappy: 'slide', spring: 'zoom', linear: 'scan' }[outgoing.primitive.motion] ?? 'cut';
}

// The sweep at a fraction t of its 220 ms: the pointer eases in and out like a flywheel dial, and the lamps warm over the last 60 ms.
export function sweepAt(t) {
  const pointer = t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2;
  const warmth = Math.max(0, Math.min(1, (t * 220 - 160) / 60));
  return { pointer, warmth };
}

const channels = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));

// A lamp warming up: its colour blends from unlit by warmth, 0 to 1, so a lamp never pops on.
export function warmLamp(tokens, state, size = 6, warmth = 1) {
  const l = lamp(tokens, state, size);
  if (warmth >= 1) return l;
  const from = channels(HIFI.unlit);
  const to = channels(l.color);
  const color = `#${from.map((f, i) => Math.round(f + (to[i] - f) * warmth).toString(16).padStart(2, '0')).join('').toUpperCase()}`;
  return { size, color, glow: l.glow };
}

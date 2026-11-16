// The island's fill and its four tones: each tone is lifted in OKLCH lightness, keeping its hue, until it reads at 4.5:1 on the fill.
import { contrast } from './theme.mjs';

const ROLES = ['muted', 'accent', 'danger', 'ok'];
const FLOOR = 4.5;
const STEP = 0.005;

const toLinear = (v) => (v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
const fromLinear = (v) => (v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055);

// Hex to OKLCH, with hue in radians.
function toOklch(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => toLinear(parseInt(hex.slice(i, i + 2), 16) / 255));
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return { L: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, C: Math.hypot(a, bb), h: Math.atan2(bb, a) };
}

// OKLCH to linear sRGB channels, which may fall outside 0..1.
function toLinearRgb(L, C, h) {
  const a = C * Math.cos(h);
  const b = C * Math.sin(h);
  const l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
  const m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
  const s = Math.pow(L - 0.0894841775 * a - 1.291485548 * b, 3);
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

const inGamut = (rgb) => rgb.every((v) => v >= -1e-6 && v <= 1 + 1e-6);

function toHex(rgb) {
  const part = (v) => Math.round(fromLinear(Math.min(1, Math.max(0, v))) * 255).toString(16).padStart(2, '0');
  return `#${rgb.map(part).join('')}`.toUpperCase();
}

// The colour at lightness L and hue h with as much of chroma C as sRGB can hold there.
function fitted(L, C, h) {
  if (inGamut(toLinearRgb(L, C, h))) return toHex(toLinearRgb(L, C, h));
  let lo = 0;
  let hi = C;
  for (let i = 0; i < 24; i++) {
    const mid = (lo + hi) / 2;
    if (inGamut(toLinearRgb(L, mid, h))) lo = mid;
    else hi = mid;
  }
  return toHex(toLinearRgb(L, lo, h));
}

// A light scheme's island is its ink and a dark scheme's is its surface; both fills are dark.
export function islandFill(tokens) {
  return (tokens.mode !== 'dark' ? tokens.color.ink : tokens.color.surface).toUpperCase();
}

// A tone that reads at 4.5:1 on the fill stays as it is, else it rises in lightness one step at a time until it does.
function lifted(hex, fill) {
  const own = hex.toUpperCase();
  if (contrast(own, fill) >= FLOOR) return own;
  const { L, C, h } = toOklch(own);
  for (let next = L + STEP; next <= 1 + STEP; next += STEP) {
    const out = fitted(Math.min(next, 1), C, h);
    if (contrast(out, fill) >= FLOOR) return out;
  }
  return '#FFFFFF';
}

export function islandTones(tokens) {
  const fill = islandFill(tokens);
  const out = {};
  for (const role of ROLES) out[role] = lifted(tokens.color[role], fill);
  return out;
}

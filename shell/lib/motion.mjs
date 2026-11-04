// How a surface opens and closes under its theme's motion token (agent #PQC9EDND); the island morphs by island.mjs.
import { springCurve, ease, EASED } from './island.mjs';

const KIND = { snappy: 'drop', ease: 'fade', spring: 'spring', linear: 'plot', typewriter: 'plot', dial: 'warm' };
// The island's spring, ended within 1/30 of its travel: under half a pixel at the edge of a 640 px card from 96% (#MV819JVT).
const SPRING = springCurve(260, 0.7, 30);
// The outline is plotted in the first 160 ms, then the fill in the last 80.
const PLOT = { ms: 240, outline: 160 };
// Hi-Fi lights its glass in the first 120 ms, then the text and lamps in the last 80.
const WARM = { ms: 200, glass: 120 };
// Frost's glass fades in on a cubic ease-out while the content rises 4 px; the card stays put, so the glass stays on its blur region.
const FADE = { ms: 160, curve: 'ease-out', rise: 4 };

// The motion a token gives a surface, its times stretched by the dev slowdown; null before a theme loads.
export function surfaceMotion(token, slowdown = 1) {
  const kind = KIND[token];
  if (!kind) return null;
  const curve = kind === 'spring' ? SPRING : kind === 'plot' ? { ms: PLOT.ms, points: null } : kind === 'warm' ? { ms: WARM.ms, points: null } : kind === 'fade' ? { ms: FADE.ms, points: null } : EASED[token];
  const openMs = Math.round(curve.ms * slowdown);
  const fade = kind === 'fade';
  return { kind, openMs, closeMs: Math.round(openMs * 0.8), points: curve.points, curve: fade ? FADE.curve : null, rise: fade ? FADE.rise : 0 };
}

const clamp = (v) => Math.min(Math.max(v, 0), 1);

// Where the card is drawn at progress p of its open; a close runs p back from where it is to 0.
export function surfacePose(m, p) {
  if (m.kind === 'plot') {
    const ms = p * PLOT.ms;
    const fill = clamp((ms - PLOT.outline) / (PLOT.ms - PLOT.outline));
    return { lift: 0, scale: 1, outline: clamp(ms / PLOT.outline), fill, text: fill, rise: 0 };
  }
  if (m.kind === 'warm') {
    const ms = p * WARM.ms;
    return { lift: 0, scale: 1, outline: 1, fill: 1 - (1 - clamp(ms / WARM.glass)) ** 3, text: clamp((ms - WARM.glass) / (WARM.ms - WARM.glass)), rise: 0 };
  }
  if (m.kind === 'fade') {
    const e = 1 - (1 - clamp(p)) ** 3;
    return { lift: 0, scale: 1, outline: 1, fill: e, text: e, rise: m.rise * (1 - e) };
  }
  const e = ease(m.points, p);
  if (m.kind === 'spring') return { lift: 8 * (1 - e), scale: 0.96 + 0.04 * e, outline: 1, fill: 1, text: 1, rise: 0 };
  return { lift: 6 * (e - 1), scale: 1, outline: 1, fill: 1, text: 1, rise: 0 };
}

// DOTS_MOTION_SLOWDOWN as bin/dots-dev passes it; the live unit never sets it, so the live shell runs at 1.
export function slowdownOf(value) {
  const n = Number(value);
  return value && Number.isFinite(n) && n > 0 ? n : 1;
}

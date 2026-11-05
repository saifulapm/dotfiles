// How a surface opens and closes on the one motion, Artboard's spring; the island morphs by island.mjs.
import { springCurve, ease } from './island.mjs';

// The island's spring, ended within 1/30 of its travel: under half a pixel at the edge of a 640 px card from 96%.
const SPRING = springCurve(260, 0.7, 30);

// The spring a surface opens on, and the short close that feels instant, their times stretched by the dev slowdown.
export function surfaceMotion(slowdown = 1) {
  const openMs = Math.round(SPRING.ms * slowdown);
  return { kind: 'spring', openMs, closeMs: Math.round(120 * slowdown), points: SPRING.points };
}

// Where the card is drawn at progress p of its open: it rises 8 px from 96%, opaque the whole way.
export function surfacePose(m, p) {
  const e = ease(m.points, p);
  return { lift: 8 * (1 - e), scale: 0.96 + 0.04 * e, opacity: 1 };
}

// A close begun at open progress `from`, f running 1 to 0 over closeMs: it fades on an ease-out, so it is leaving from the first frame, and shrinks 4% from the pose it was in.
export function closePose(m, from, f) {
  const at = surfacePose(m, from);
  const k = f * f;
  return { lift: at.lift, scale: at.scale * (0.96 + 0.04 * k), opacity: k };
}

// DOTS_MOTION_SLOWDOWN as bin/dots-dev passes it; the live unit never sets it, so the live shell runs at 1.
export function slowdownOf(value) {
  const n = Number(value);
  return value && Number.isFinite(n) && n > 0 ? n : 1;
}

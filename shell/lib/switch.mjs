// A colorscheme switch: the paper and open surfaces crossfade from the old colours to the new.
import { springCurve, ease } from './island.mjs';

// 260 ms, a frame inside the 280 ms budget, as the shell's own stamps add one (lesson 2026-11-04).
export const SWITCH = { kind: 'fade', ms: 260 };

// Every pair crossfades; the same scheme again replaces the paper with no transition, which Paper.qml decides before asking.
export const switchKind = (outgoing, incoming) => SWITCH.kind;

// The surfaces' spring, cut at its first reach of 1: the whole spring overshoots and is 95% done at half time, which a fade would show as its end.
const spring = springCurve(260, 0.7, 30).points;
const CURVE = spring.slice(0, spring.findIndex((v) => v >= 1) + 1);

// How far the fade is at a fraction t of its time, 0 to 1.
export function fadeAt(t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  const x = t * (CURVE.length - 1);
  const i = Math.floor(x);
  return Math.min(1, CURVE[i] + (CURVE[i + 1] - CURVE[i]) * (x - i));
}

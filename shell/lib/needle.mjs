// How Hi-Fi's VU needle swings to a new volume: 300 ms, one overshoot past the target, then rest exactly on it.

export const SWING_MS = 300;
const OVERSHOOT = 0.06;

// The swing's shape is y(u) = 1 - (1 - u)^2 (1 - c u) for u from 0 to 1. It starts at 0, ends at 1 with no speed, and passes 1 once; its furthest point is 4 (c - 1)^3 / (27 c^2) past 1.
const pastOne = (c) => (4 * (c - 1) ** 3) / (27 * c * c);

// The c whose overshoot is 6 % of the travel, bisected from above so the peak is never a hair short of it.
const C = (() => {
  let lo = 1;
  let hi = 4;
  for (let i = 0; i < 80; i++) {
    const mid = (lo + hi) / 2;
    if (pastOne(mid) < OVERSHOOT) lo = mid;
    else hi = mid;
  }
  return hi;
})();

const shape = (u) => 1 - (1 - u) ** 2 * (1 - C * u);

// The value drawn ms after a swing from `from` to `to` began; it rests on `to` from `total` ms on.
export function needleAt(from, to, ms, total = SWING_MS) {
  if (ms >= total) return to;
  return from + (to - from) * shape(Math.max(0, ms) / total);
}

// The furthest value a swing from `from` to `to` draws, past `to` on the side it travels towards.
export function needlePeak(from, to) {
  return to + (to - from) * pastOne(C);
}

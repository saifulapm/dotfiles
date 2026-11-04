// Frost's theme switch: frost grows in from the edges until it covers the screen, the new theme swaps in under it, and it melts from the centre back to the edges. The melt takes 100 ms, not the board's 120, so the last frame lands inside the 300 ms the switch is allowed: a 300 ms animation read 305 to 315 ms by the shell's own stamps.
export const FROST_SWITCH = { coverMs: 180, ms: 280 };

// The switch at a fraction t of its 280 ms: reach is how far in from the edges the frost has grown, 0 none and 1 the whole screen; swapped is true once the new theme is under it.
export function frostAt(t) {
  const ms = Math.max(0, Math.min(1, t)) * FROST_SWITCH.ms;
  const { coverMs } = FROST_SWITCH;
  if (ms < coverMs) return { reach: (ms / coverMs) ** 2, swapped: false };
  const melt = (ms - coverMs) / (FROST_SWITCH.ms - coverMs);
  return { reach: (1 - melt) ** 3, swapped: true };
}

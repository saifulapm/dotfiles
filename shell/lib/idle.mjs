// Pure pieces of the idle steps: dim, lock, then monitors off, each in seconds of no input.
export const TIMES = [240, 300, 360];

// Test times must be whole seconds that rise step by step, or the real ones stay.
export function validTimes(t) {
  return t.length === 3 && t.every((s) => Number.isInteger(s) && s > 0) && t[0] < t[1] && t[1] < t[2];
}

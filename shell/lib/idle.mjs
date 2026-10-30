// Pure pieces of the idle steps: dim, lock, then monitors off, each in seconds of no input.

import { clockText } from './margins.mjs';
export const TIMES = [240, 300, 360];

// Test times must be whole seconds that rise step by step, or the real ones stay.
export function validTimes(t) {
  return t.length === 3 && t.every((s) => Number.isInteger(s) && s > 0) && t[0] < t[1] && t[1] < t[2];
}

// Stay awake holds the steps off until a time, in ms since the epoch; 0 is off. `dots awake 60` asks for minutes, and anything but a positive whole number of at most a day turns it off.
export function awakeMinutes(text) {
  const s = String(text ?? '').trim();
  return /^[1-9][0-9]{0,3}$/.test(s) && Number(s) <= 1440 ? Number(s) : 0;
}

export const awakeEnd = (now, minutes) => (minutes > 0 ? now + minutes * 60000 : 0);

// Control's row steps off, 30 min, 1 h, 2 h, off: each press takes the first step longer than what is left.
export const AWAKE_STEPS = [30, 60, 120];

export function nextAwake(now, until) {
  const left = until > now ? (until - now) / 60000 : 0;
  const next = left > 0 ? AWAKE_STEPS.find((m) => m > Math.ceil(left)) : AWAKE_STEPS[0];
  return awakeEnd(now, next ?? 0);
}

// The margin's word and Control's detail; until is ms since the epoch.
export const awakeWord = (until) => (until > 0 ? `awake ${clockText(new Date(until))}` : '');
export const awakeDetail = (until) => (until > 0 ? `until ${clockText(new Date(until))}` : 'off');

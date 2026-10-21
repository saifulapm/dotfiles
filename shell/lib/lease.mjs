// Pure pieces of an agent's lease on the unlocked session (MBFQCTFH, RJA7QN1K).

import { line } from './voice.mjs';

export const DEFAULT_MIN = 15;
// No lease ends later than this after its unlock, however often it is renewed.
export const MAX_MS = 120 * 60000;

// Every IPC argument arrives as a string and the call cannot leave one out, so anything but a positive number means the default.
export function minutesOf(s) {
  const n = Number(s);
  return isFinite(n) && n > 0 ? n : DEFAULT_MIN;
}

export const leaseEnd = (unlockedAt, now, minutes) => Math.min(now + minutes * 60000, unlockedAt + MAX_MS);

// C0, DEL and C1 controls draw as tofu, blob the journal and replay on a terminal, and U+0085 ends a line; the bidi marks reorder what follows.
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const MARK = /[\u200e\u200f\u061c]/g;

// The name any caller gave, as one line of plain text; an empty one still holds a lease.
export const holder = (who) => line((who || '').replace(CONTROL, ' ').replace(MARK, '')) || 'agent';

export const unlockLine = (who, minutes) => `lock: agent unlock by ${who} for ${minutes} min`;

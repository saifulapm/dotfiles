// The island as the one host of the shell's surfaces: its approved motion (38G8XV1J), its resting shape and which arrivals take it from an open surface.
import { springCurve, pick } from './island.mjs';

export const REST = { width: 176, height: 34 };
// The concave corner that joins the island to the top edge on each side.
export const CONCAVE = 12;

// 61 samples at even steps of time, as island.mjs samples a spring, so ease reads both alike.
const easeOut = Array.from({ length: 61 }, (_, i) => Math.round((1 - (1 - i / 60) ** 3) * 10000) / 10000);

// Open and switch on the spring, ended within 1/30 of its travel; close on a short ease-out; the outgoing content fades over outMs, and an island part comes in by swap, rising as it fades, or on a close by closeSwap, over the close itself.
export function hostMotion() {
  return {
    open: springCurve(260, 0.7, 30),
    close: { ms: 120, points: easeOut },
    outMs: 80,
    swap: { kind: 'rise', inMs: 200, outMs: 80, delay: 60, rise: 6 },
    closeSwap: { kind: 'rise', inMs: 120, outMs: 80, delay: 0, rise: 0 },
  };
}

// When row n of the incoming content starts to fade in, how long it takes and how far it rises; rows past the tenth come in with it (496AQ7DS).
export const rowFade = (n) => ({ delay: 60 + 18 * Math.min(n, 9), ms: 200, rise: 6 });

const radiusAt = (height) => (height > REST.height ? 20 : 14);

// The bottom corners' radius for a box this tall, or mid-morph from one height to another at eased progress e.
export function bottomRadius(from, to, e) {
  if (to === undefined) return radiusAt(from);
  return radiusAt(from) + (radiusAt(to) - radiusAt(from)) * e;
}

// What the island shows: an open surface outranks every slot (PCGX7JPJ), else the slots' own order.
export const modeOf = (surface, slots) => (surface ? 'surface' : pick(slots));

// The notification the island may show: none while a screen is shared, so a share never shows one (61SHXHG7); it still goes to the centre's history.
export const shownNotification = (current, sharing) => (sharing ? null : current);

// What arrives while a surface is open waits behind the dot (7E95CSV2); until m106 a pairing request, which arrives in the question slot, still closes the surface (PCGX7JPJ).
export function surfaceYields(before, after) {
  const now = after.question;
  return !!now?.pairing && now.id !== before.question?.id;
}

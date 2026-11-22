// The island's waiting queue: what arrives behind an open surface waits here, and after the close it shows one at a time. Every function takes now in ms, so none reads a clock.

// When a notification that arrived at at runs out, or null when it stays until dismissed (a hold of 0).
export const expiry = (at, holdMs) => (holdMs > 0 ? at + holdMs : null);

// The queue with item added at the end; an item whose key is already queued takes that one's place, arrival time and expiry, with the new entry, since its time runs from when it first arrived (3WG2NHE3).
export function arrive(queue, item) {
  const i = queue.findIndex((q) => q.key === item.key);
  if (i < 0) return [...queue, item];
  const out = [...queue];
  out[i] = Object.assign({}, item, { at: queue[i].at, expires: queue[i].expires });
  return out;
}

const lapsed = (item, now) => item.kind === 'notification' && item.expires !== null && item.expires <= now;

// The next item to show (the first question, else the first notification still alive), the expired notifications, and the queue without both.
export function take(queue, now) {
  const expired = queue.filter((q) => lapsed(q, now));
  const alive = queue.filter((q) => !lapsed(q, now));
  const next = alive.find((q) => q.kind === 'question') ?? alive[0] ?? null;
  return { next, rest: alive.filter((q) => q !== next), expired };
}

// The queue without the item of that key, when its app closed it or the question was answered elsewhere.
export const drop = (queue, key) => queue.filter((q) => q.key !== key);

// How many items wait.
export const count = (queue) => queue.length;

// The island's stack of notifications: how many it holds in all, how many of them are from the shown one's app, and how many other apps wait in it.
export function pile(current, waiting, queue) {
  if (!current) return { count: 0, app: '', same: 0, others: 0 };
  const seen = new Map([[current.key, current]]);
  for (const e of [...waiting, ...queue.filter((q) => q.kind === 'notification').map((q) => q.entry)]) if (!seen.has(e.key)) seen.set(e.key, e);
  const all = [...seen.values()];
  const same = all.filter((e) => e.app === current.app).length;
  return { count: all.length, app: current.app, same, others: new Set(all.filter((e) => e.app !== current.app).map((e) => e.app)).size };
}

import { LocalStorage } from "@vicinae/api";
import type { Result } from "./youtube";

/** A result plus when it was put here. */
export type Saved = Result & { savedAt: number };

export type ListKey = "history" | "starred";

// Enough to scroll back through a few weeks of watching. The cap exists
// because this list is rewritten whole on every play, and an unbounded one
// would eventually make pressing Enter slow.
const HISTORY_CAP = 100;

async function read(key: ListKey): Promise<Saved[]> {
  const raw = await LocalStorage.getItem<string>(key);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as Saved[]) : [];
  } catch {
    // Storage is inspectable and editable from vicinae's own Local Storage
    // command, so malformed JSON is reachable. An empty library beats a
    // command that will not open.
    return [];
  }
}

async function write(key: ListKey, items: Saved[]): Promise<void> {
  await LocalStorage.setItem(key, JSON.stringify(items));
}

export const getList = read;

/** Most recent first, and only once: replaying moves an entry rather than
 *  filling the list with copies of whatever is on repeat. */
export async function recordPlay(result: Result): Promise<void> {
  const items = await read("history");
  const next = [
    { ...result, savedAt: Date.now() },
    ...items.filter((i) => i.id !== result.id),
  ].slice(0, HISTORY_CAP);
  await write("history", next);
}

/** Returns the new state: true when it is now saved. */
export async function toggleStar(result: Result): Promise<boolean> {
  const items = await read("starred");
  const starred = items.some((i) => i.id === result.id);
  await write(
    "starred",
    starred
      ? items.filter((i) => i.id !== result.id)
      : [{ ...result, savedAt: Date.now() }, ...items],
  );
  return !starred;
}

export async function remove(key: ListKey, id: string): Promise<void> {
  const items = await read(key);
  await write(
    key,
    items.filter((i) => i.id !== id),
  );
}

export async function clear(key: ListKey): Promise<void> {
  await LocalStorage.removeItem(key);
}

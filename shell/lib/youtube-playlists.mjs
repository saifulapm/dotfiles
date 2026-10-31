// The YouTube App's Playlists store, ~/.local/share/dots/youtube/<machine>.json: Playlists by id, each item keyed by its video id so a video is in a Playlist at most once; Saved is the fixed id saved. Kept pure so node can test it.

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

// An item holds what a row draws, so no view needs the network to draw it.
const FIELDS = ['id', 'title', 'channel', 'duration', 'thumb'];

const num = (v) => (typeof v === 'number' ? v : 0);

// A missing deleted is false: the file written before Playlists could be made has none. Two machines can each add a video at one position, so the id settles their order alike on both.
const live = (list) =>
  Object.values(list.items)
    .filter((it) => !it.deleted)
    .sort((a, b) => num(a.pos) - num(b.pos) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

const saved = () => ({ id: 'saved', name: 'Saved', updatedAt: 0, items: {} });

export const emptyStore = () => ({ version: 1, playlists: { saved: saved() } });

// Every view and the sync merge read a Playlist's items and name, so a Playlist without them is no store at all.
const wellFormed = (l) => isObject(l) && isObject(l.items) && (l.name === undefined || typeof l.name === 'string') && Object.values(l.items).every(isObject);

// No file yet is a new store; a file that is broken or the wrong shape is null, so nothing ever saves over the Playlists it holds.
export function parse(text) {
  if (String(text).trim() === '') return emptyStore();
  let s;
  try {
    s = JSON.parse(text);
  } catch (e) {
    return null;
  }
  if (!isObject(s) || !isObject(s.playlists) || !Object.values(s.playlists).every(wellFormed)) return null;
  return s.playlists.saved ? s : Object.assign({}, s, { playlists: Object.assign({}, s.playlists, { saved: saved() }) });
}

// dots-sync-merge reads every unit's store by this name.
export const parseStore = parse;

export const serialize = (store) => JSON.stringify(store, null, 1) + '\n';

const put = (store, id, list) => Object.assign({}, store, { playlists: Object.assign({}, store.playlists, { [id]: list }) });

// A name is trimmed, and Saved is never made, renamed or deleted.
export function create(store, id, name, now) {
  const n = String(name).trim();
  if (n === '' || id === 'saved' || store.playlists[id]) return store;
  return put(store, id, { id, name: n, createdAt: now, updatedAt: now, deleted: false, items: {} });
}

export function rename(store, id, name, now) {
  const list = store.playlists[id];
  const n = String(name).trim();
  if (n === '' || id === 'saved' || !list || list.deleted) return store;
  return put(store, id, Object.assign({}, list, { name: n, nameAt: now, updatedAt: now }));
}

// A removed Playlist stays as a tombstone so a later sync can tell it was deleted, not never made.
export function remove(store, id, now) {
  const list = store.playlists[id];
  if (id === 'saved' || !list) return store;
  return put(store, id, Object.assign({}, list, { deleted: true, updatedAt: now }));
}

const make = (video, pos, now) => {
  const item = Object.assign({}, ...FIELDS.map((f) => ({ [f]: video[f] })), { pos, addedAt: now, updatedAt: now, deleted: false });
  if (typeof video.unavailable === 'string' && video.unavailable !== '') item.unavailable = video.unavailable;
  return item;
};

// Each item sits at a position after the last, so a later move can land between two without renumbering. A tombstoned video comes back at the end.
export const add = (store, playlistId, video, now) => addMany(store, playlistId, [video], now);

// One copy of the items for the whole batch, so five thousand videos cost one pass.
export function addMany(store, playlistId, videos, now) {
  const list = store.playlists[playlistId];
  if (!list || list.deleted) return store;
  const items = Object.assign({}, list.items);
  let last = Object.values(items).reduce((max, it) => Math.max(max, it.pos), 0);
  let changed = false;
  for (const v of videos) {
    if (items[v.id] && !items[v.id].deleted) continue;
    items[v.id] = make(v, ++last, now);
    changed = true;
  }
  return changed ? put(store, playlistId, Object.assign({}, list, { updatedAt: now, items })) : store;
}

export function removeItem(store, playlistId, videoId, now) {
  const list = store.playlists[playlistId];
  const it = list && list.items[videoId];
  if (!it || it.deleted) return store;
  const gone = Object.assign({}, it, { deleted: true, updatedAt: now });
  return put(store, playlistId, Object.assign({}, list, { items: Object.assign({}, list.items, { [videoId]: gone }) }));
}

// The item lands between its new neighbours, so only its own position changes and a sync has one item to merge.
export function move(store, playlistId, videoId, step, now) {
  const list = store.playlists[playlistId];
  if (!list || list.deleted) return store;
  const order = live(list);
  const at = order.findIndex((it) => it.id === videoId);
  const over = order[at + step];
  if (at < 0 || !over) return store;
  const beyond = order[at + 2 * step];
  const pos = beyond ? (over.pos + beyond.pos) / 2 : over.pos + step;
  const moved = Object.assign({}, order[at], { pos, updatedAt: now });
  return put(store, playlistId, Object.assign({}, list, { items: Object.assign({}, list.items, { [videoId]: moved }) }));
}

// A Playlist's videos in their order, each as its five fields, and the reason a video is unavailable when it has one.
export function items(store, playlistId) {
  const list = store && store.playlists[playlistId];
  if (!list) return [];
  return live(list).map((it) => {
    const out = Object.assign({}, ...FIELDS.map((f) => ({ [f]: it[f] })));
    if (it.unavailable) out.unavailable = it.unavailable;
    return out;
  });
}

export const holds = (store, playlistId, videoId) => {
  const list = store.playlists[playlistId];
  return !!list && !!list.items[videoId] && !list.items[videoId].deleted;
};

// The Playlists a person made, oldest first; Saved has its own view.
export function playlists(store) {
  return Object.values(store.playlists)
    .filter((l) => l.id !== 'saved' && !l.deleted)
    .sort((a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((l) => {
      const its = live(l);
      return { id: l.id, name: l.name, count: its.length, secs: its.reduce((sum, it) => sum + (typeof it.duration === 'number' ? it.duration : 0), 0) };
    });
}

// The newer of two copies of one record; at the same stamp the larger text wins, so both machines pick alike.
function later(a, b, stamp) {
  const d = stamp(a) - stamp(b);
  if (d) return d > 0 ? a : b;
  return JSON.stringify(a) >= JSON.stringify(b) ? a : b;
}

// a's keys first, then b's new ones, so merging a store with itself writes the same bytes.
function mergeById(a, b, fn) {
  const out = {};
  for (const k of Object.keys(a)) out[k] = k in b ? fn(a[k], b[k]) : a[k];
  for (const k of Object.keys(b)) if (!(k in a)) out[k] = b[k];
  return out;
}

const nameAt = (l) => num(l.nameAt !== undefined ? l.nameAt : l.createdAt);

// An item is taken whole from its newer copy, a removal included; a name from the copy that set it last. A Playlist deleted anywhere stays deleted, as nothing makes it again under its id; Saved is never renamed or deleted.
function mergeList(a, b) {
  const items = mergeById(a.items, b.items, (x, y) => later(x, y, (it) => num(it.updatedAt)));
  const out = Object.assign({}, a, { updatedAt: Math.max(num(a.updatedAt), num(b.updatedAt)), items });
  if (a.id === 'saved') {
    if (out.name !== 'Saved') out.name = 'Saved';
    if (out.deleted) delete out.deleted;
    return out;
  }
  const named = later(a, b, nameAt);
  out.name = named.name;
  if (a.nameAt !== undefined || b.nameAt !== undefined) out.nameAt = nameAt(named);
  if (a.deleted || b.deleted) out.deleted = true;
  return out;
}

// The sync merge: per Playlist and per item by id, so a video added on one machine and another removed on a second both survive.
export const mergeStores = (a, b) => Object.assign({}, a, { playlists: mergeById(a.playlists, b.playlists, mergeList) });

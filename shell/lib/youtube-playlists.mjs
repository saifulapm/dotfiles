// The YouTube App's Playlists store, ~/.local/share/dots/youtube/<machine>.json: Playlists by id, each item keyed by its video id so a video is in a Playlist at most once; Saved is the fixed id saved. Kept pure so node can test it.

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

// An item holds what a row draws, so no view needs the network to draw it.
const FIELDS = ['id', 'title', 'channel', 'duration', 'thumb'];

const saved = () => ({ id: 'saved', name: 'Saved', updatedAt: 0, items: {} });

export const emptyStore = () => ({ version: 1, playlists: { saved: saved() } });

// No file yet is a new store; a file that is broken or the wrong shape is null, so nothing ever saves over the Playlists it holds.
export function parse(text) {
  if (String(text).trim() === '') return emptyStore();
  let s;
  try {
    s = JSON.parse(text);
  } catch (e) {
    return null;
  }
  if (!isObject(s) || !isObject(s.playlists)) return null;
  return s.playlists.saved ? s : Object.assign({}, s, { playlists: Object.assign({}, s.playlists, { saved: saved() }) });
}

export const serialize = (store) => JSON.stringify(store, null, 1) + '\n';

// Each item sits at a position after the last, so a later move can land between two without renumbering.
export function add(store, playlistId, video, now) {
  const list = store.playlists[playlistId];
  if (!list || list.items[video.id]) return store;
  const last = Object.values(list.items).reduce((max, it) => Math.max(max, it.pos), 0);
  const item = Object.assign({}, ...FIELDS.map((f) => ({ [f]: video[f] })), { pos: last + 1, updatedAt: now });
  const next = Object.assign({}, list, { updatedAt: now, items: Object.assign({}, list.items, { [video.id]: item }) });
  return Object.assign({}, store, { playlists: Object.assign({}, store.playlists, { [playlistId]: next }) });
}

// A Playlist's videos in their order, each as its five fields.
export function items(store, playlistId) {
  const list = store && store.playlists[playlistId];
  if (!list) return [];
  return Object.values(list.items)
    .sort((a, b) => a.pos - b.pos)
    .map((it) => Object.assign({}, ...FIELDS.map((f) => ({ [f]: it[f] }))));
}

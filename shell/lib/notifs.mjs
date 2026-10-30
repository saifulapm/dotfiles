// Pure pieces of the notification history, kept here so node can test them.

export const LIMIT = 200;

// How long an entry holds the island in ms, 0 until dismissed: its app's expireTimeout, where -1 asks for the default, 5 s or until dismissed for a critical.
export const holdMs = (entry) => (entry.timeout >= 0 ? entry.timeout : entry.critical ? 0 : 5000);

// The undismissed criticals waiting to take the island back, newest first: the one leaving joins them when it stays until dismissed, and the one arriving leaves them.
export function setAside(waiting, leaving, arriving) {
  const kept = waiting.filter((e) => e.key !== arriving);
  if (leaving && leaving.key !== arriving && leaving.critical && holdMs(leaving) === 0) kept.push(leaving);
  return kept.sort((a, b) => b.time - a.time);
}

// A hold paused under the pointer or Mod+I gets back what it had left, but never less than 1.5 s to read it once let go.
export const resumeMs = (left) => Math.max(left, 1500);

export const addEntry = (history, entry) => [entry].concat(history).slice(0, LIMIT);

const isEntry = (e) =>
  e !== null && typeof e === 'object' && typeof e.key === 'string' && typeof e.app === 'string' && typeof e.summary === 'string' && typeof e.body === 'string' && typeof e.time === 'number';

// The store is written by the shell alone, but a hand edit or a cut-off write must not stop it loading.
export function parseStore(text) {
  let data = null;
  try {
    data = JSON.parse(text);
  } catch (e) {
    data = null;
  }
  if (data === null || typeof data !== 'object' || !Array.isArray(data.history)) return { dnd: false, history: [] };
  const seen = {};
  const unique = data.history
    .filter(isEntry)
    .filter((e) => (seen[e.key] ? false : (seen[e.key] = true)))
    .map((e) => {
      if (!('files' in e) || validFiles(e.files)) return e;
      const kept = Object.assign({}, e);
      delete kept.files;
      return kept;
    });
  return { dnd: data.dnd === true, history: unique.slice(0, LIMIT) };
}

export const storeText = (store) => JSON.stringify({ dnd: store.dnd, history: store.history });

// The entries a search shows: its text in the app, summary or body, ignoring case.
export function visible(history, query) {
  const q = query.toLowerCase();
  return history.filter((e) => (e.app + '\n' + e.summary + '\n' + e.body).toLowerCase().includes(q));
}

// One group per app, the app with the newest entry first, each group newest first.
export function group(entries) {
  const groups = [];
  const byApp = {};
  for (const e of entries.slice().sort((a, b) => b.time - a.time)) {
    if (!byApp[e.app]) {
      byApp[e.app] = { app: e.app, entries: [] };
      groups.push(byApp[e.app]);
    }
    byApp[e.app].entries.push(e);
  }
  return groups;
}

export const clampSelected = (selected, length) => Math.max(0, Math.min(length - 1, selected));

// A notification is about files when our own senders list them, or niri's screenshot names one in image-path.
const isPath = (p) => typeof p === 'string' && p.startsWith('/');
const validFiles = (f) => Array.isArray(f) && f.every(isPath);

// Temp files and icon theme images are never the file a notification is about; ".." could walk out of a folder checked by prefix.
function userFile(path, home) {
  if (!isPath(path) || path.split('/').includes('..') || path.startsWith('/tmp/')) return false;
  return !['/usr/share/icons/', '/usr/share/pixmaps/', home + '/.local/share/icons/', home + '/.icons/'].some((d) => path.startsWith(d));
}

function hintPath(value) {
  if (typeof value !== 'string') return '';
  if (!value.startsWith('file://')) return value;
  try {
    return decodeURIComponent(value.slice(7));
  } catch (e) {
    return '';
  }
}

export function filesOf(hints, home) {
  const listed = typeof hints['x-dots-files'] === 'string' ? hints['x-dots-files'].split('\n').filter((l) => userFile(l, home)) : [];
  if (listed.length > 0) return listed;
  const image = hintPath(hints['image-path'] || hints['image_path']);
  return userFile(image, home) ? [image] : [];
}

export const fileUri = (path) => 'file://' + path.split('/').map(encodeURIComponent).join('/');

// RFC 2483: each URI ends with CRLF.
export const uriList = (files) => files.map((f) => fileUri(f) + '\r\n').join('');

export function chipLabel(files) {
  if (files.length !== 1) return files.length + ' FILES';
  const name = files[0].slice(files[0].lastIndexOf('/') + 1);
  const dot = name.lastIndexOf('.');
  return dot > 0 && dot < name.length - 1 ? name.slice(dot + 1).toUpperCase() : 'FILE';
}

export const dragPayload = (entry) =>
  entry.files && entry.files.length > 0 ? { mime: 'text/uri-list', data: uriList(entry.files) } : { mime: 'text/plain', data: entry.body };

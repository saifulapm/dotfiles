// The notes store and its rules, shared by the Notes window and, later, the sync merge; kept pure so node can test them.

export const CAPTURE_MAX = 10000;

const set = (o, fields) => Object.assign({}, o, fields);

export const emptyStore = () => ({ version: 1, activeSection: 'inbox', sections: [{ name: 'inbox', order: 0 }], notes: [] });

export function parseStore(text) {
  let data = null;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return emptyStore();
  }
  if (data === null || typeof data !== 'object' || !Array.isArray(data.sections) || !Array.isArray(data.notes) || !data.sections.length) return emptyStore();
  return data;
}

// The id names the store file, so anything that is not a plain name falls through to the next source.
const plainName = (s) => (/^[A-Za-z0-9._-]+$/.test(s) && !s.startsWith('.') ? s : '');

export function machineId(env, chezmoiToml, hostname) {
  const fromToml = (chezmoiToml.match(/^\s*machine\s*=\s*"([^"]*)"/m) ?? [])[1] ?? '';
  return plainName(env ?? '') || plainName(fromToml) || plainName((hostname ?? '').trim()) || 'unknown';
}

export function sectionCommand(text) {
  const m = text.trim().match(/^# (.+)$/);
  return m && !m[1].includes('\n') && m[1].trim() ? m[1].trim() : null;
}

export function useSection(store, name) {
  if (store.sections.some((s) => s.name === name)) return set(store, { activeSection: name });
  const order = Math.max.apply(null, store.sections.map((s) => s.order)) + 1;
  return set(store, { activeSection: name, sections: store.sections.concat([{ name, order }]) });
}

function addNote(store, text, now, id) {
  const note = { id, section: store.activeSection, text, attachments: [], todo: false, done: false, tags: [], createdAt: now, updatedAt: now };
  return set(store, { notes: store.notes.concat([note]) });
}

// What Enter in the composer does with its text.
export function compose(store, text, now, id) {
  const name = sectionCommand(text);
  if (name) return useSection(store, name);
  return text.trim() ? addNote(store, text, now, id) : store;
}

const newest = (a, b) => b.createdAt - a.createdAt;

// A Wayland primary selection never expires, so a capture equal to the last one makes no note.
export function capture(store, selection, last, now, id) {
  if (!selection.trim()) return { store, toast: 'Nothing selected', last };
  const text = selection.slice(0, CAPTURE_MAX);
  if (text === last) return { store, toast: 'Already captured', last };
  return { store: addNote(store, text, now, id), toast: 'Captured', last: text };
}

export function lastCapture(store) {
  const live = store.notes.filter((n) => !n.deleted).sort(newest);
  return live.length ? live[0].text : '';
}

export const sectionNotes = (store, section) => store.notes.filter((n) => n.section === section && !n.deleted).sort(newest);

export const TAGS = ['red', 'orange', 'yellow', 'green', 'blue', 'purple'];
export const ATTACH_MAX = 25 * 1024 * 1024;

const change = (store, ids, fn, now) => set(store, { notes: store.notes.map((n) => (ids.indexOf(n.id) >= 0 ? set(fn(n), { updatedAt: now }) : n)) });

const tombstone = (n) => set(n, { text: '', attachments: [], tags: [], todo: false, done: false, deleted: true });

export function toggleTag(store, id, key, now) {
  if (!/^[1-6]$/.test(key)) return store;
  const tag = TAGS[Number(key) - 1];
  const flip = (n) => ({ tags: TAGS.filter((t) => (t === tag ? n.tags.indexOf(t) < 0 :n.tags.indexOf(t) >= 0)) });
  return change(store, [id], (n) => set(n, flip(n)), now);
}

export const deleteNotes = (store, ids, now) => change(store, ids, tombstone, now);

export function merge(store, ids, now) {
  const live = [];
  ids.forEach((id) => {
    const n = store.notes.find((x) => x.id === id && !x.deleted);
    if (n && live.indexOf(n) < 0) live.push(n);
  });
  if (live.length < 2) return store;
  const attachments = [];
  live.forEach((n) => n.attachments.forEach((a) => attachments.some((b) => b.sha256 === a.sha256) || attachments.push(a)));
  const todos = live.filter((n) => n.todo);
  const merged = {
    text: live.map((n) => n.text).join('\n\n'),
    attachments,
    tags: TAGS.filter((t) => live.some((n) => n.tags.indexOf(t) >= 0)),
    todo: todos.length > 0,
    done: todos.length > 0 && todos.every((n) => n.done),
    updatedAt: now,
  };
  const rest = live.slice(1).map((n) => n.id);
  return set(store, { notes: store.notes.map((n) => (n === live[0] ? set(n, merged) : rest.indexOf(n.id) >= 0 ? set(tombstone(n), { updatedAt: now }) : n)) });
}

export function moveNotes(store, ids, section, now) {
  const known = store.sections.some((s) => s.name === section);
  const order = Math.max.apply(null, store.sections.map((s) => s.order)) + 1;
  const moved = change(store, ids, (n) => set(n, { section }), now);
  return known ? moved : set(moved, { sections: store.sections.concat([{ name: section, order }]) });
}

export const toggleDone = (store, id, now) => change(store, [id], (n) => (n.todo ? set(n, { done: !n.done }) : set(n, { todo: true, done: false })), now);

export const editNote = (store, id, text, now) => (text.trim() ? change(store, [id], (n) => set(n, { text }), now) : store);

export function search(store, query) {
  const q = query.toLowerCase();
  return q ? store.notes.filter((n) => !n.deleted && n.text.toLowerCase().indexOf(q) >= 0).sort(newest) : [];
}

export const sectionNames = (store) => store.sections.slice().sort((a, b) => a.order - b.order).map((s) => s.name);

export function sectionList(store, section) {
  const item = (n) => (n.todo ? (n.done ? '- [x] ' : '- [ ] ') : '- ') + n.text.split('\n').join('\n  ');
  return sectionNotes(store, section).map(item).join('\n');
}

export const attachRefusal = (size) => (size > ATTACH_MAX ? 'Attachment over 25 MB' : null);

export const attach = (store, id, attachment, now) =>
  change(store, [id], (n) => (n.attachments.some((a) => a.sha256 === attachment.sha256) ? n : set(n, { attachments: n.attachments.concat([attachment]) })), now);

export function attachmentFile(attachment) {
  const fromName = (attachment.name.match(/\.([A-Za-z0-9]+)$/) ?? [])[1];
  const fromMime = { 'image/png': 'png', 'image/jpeg': 'jpg' }[attachment.mime];
  return attachment.sha256 + '.' + ((fromName ? fromName.toLowerCase() : '') || fromMime || 'bin');
}

export const dragOffer = (note) => ({ 'text/plain': note.text });

export const chipOffer = (attachment, dir) => ({ 'text/uri-list': 'file://' + dir + '/' + attachmentFile(attachment) });

export function attachTo(store, id, attachments, now, newId) {
  if (!attachments.length) return store;
  const base = id ? store : addNote(store, '', now, newId);
  return attachments.reduce((s, a) => attach(s, id || newId, a, now), base);
}

export const firstImage = (note) => note.attachments.find((a) => a.mime.indexOf('image/') === 0) ?? null;

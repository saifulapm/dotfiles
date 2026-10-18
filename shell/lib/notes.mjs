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

function useSection(store, name) {
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

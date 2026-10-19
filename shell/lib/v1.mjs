// dots cutover's import: v1's notes.json and goals.json as v2 stores, which dots-sync-merge then merges by id; pure, so the same file always gives the same store.

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const ms = (iso) => Date.parse(iso) || 0;

function parse(text, key) {
  let data = null;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return null;
  }
  return isObject(data) && Array.isArray(data[key]) ? data[key].filter((x) => isObject(x) && typeof x.id === 'string') : null;
}

// A v1 id starts with its creation time as 9 base36 digits.
const createdAt = (n) => (/^[0-9a-z]{9}-/.test(n.id) ? parseInt(n.id.slice(0, 9), 36) : ms(n.updatedAt));

// attachmentOf(path) names the copied file as { sha256, name, mime, size }, or null when v1's file is gone.
export function notesFromV1(text, attachmentOf) {
  const v1 = parse(text, 'notes');
  if (!v1) return null;
  const note = (n) => {
    const base = { id: n.id, section: 'inbox', text: '', attachments: [], todo: false, done: false, tags: [] };
    if (n.deletedAt) return Object.assign(base, { deleted: true, createdAt: createdAt(n), updatedAt: ms(n.deletedAt) });
    const attachment = n.path ? attachmentOf(n.path) : null;
    // A file v1 left where it was dropped may not be on this machine; then its path is the text, as v1 showed its name.
    return Object.assign(base, { text: String(n.text ?? '') || (attachment ? '' : String(n.path ?? '')), attachments: attachment ? [attachment] : [], todo: n.done === true, done: n.done === true, createdAt: createdAt(n), updatedAt: ms(n.updatedAt) });
  };
  return { version: 1, activeSection: 'inbox', sections: [{ name: 'inbox', order: 0 }], notes: v1.map(note) };
}

export function goalsFromV1(text) {
  const v1 = parse(text, 'goals');
  if (!v1) return null;
  const task = (t, i) => ({ id: t.id, text: String(t.text ?? ''), done: t.done === true, order: i, updatedAt: ms(t.updatedAt), deleted: false });
  const goal = (g, i) => {
    if (g.deletedAt) return { id: g.id, title: '', deadline: null, order: i, done: false, doneAt: null, updatedAt: ms(g.deletedAt), deleted: true, tasks: [] };
    const shipped = g.state === 'shipped';
    const tasks = (Array.isArray(g.tasks) ? g.tasks : []).filter((t) => isObject(t) && typeof t.id === 'string');
    return {
      id: g.id,
      title: String(g.name ?? ''),
      deadline: ms(g.due) || null,
      order: i,
      done: shipped,
      doneAt: shipped ? ms(g.shippedAt) || ms(g.updatedAt) : null,
      updatedAt: ms(g.updatedAt),
      deleted: false,
      tasks: tasks.map(task),
    };
  };
  return { version: 1, goals: v1.map(goal) };
}

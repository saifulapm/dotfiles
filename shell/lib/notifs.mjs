// Pure pieces of the notification history, kept here so node can test them.

export const LIMIT = 200;

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
  return { dnd: data.dnd === true, history: data.history.filter(isEntry).slice(0, LIMIT) };
}

export const storeText = (store) => JSON.stringify({ dnd: store.dnd, history: store.history });

// Pure pieces of the launcher, kept here so node can test them.
import { calc, format } from './calc.mjs';

// Lower is better: exact name, name prefix, word prefix, substring, then a keyword match.
function tier(entry, q) {
  const name = entry.name.toLowerCase();
  if (name === q) return 0;
  if (name.startsWith(q)) return 1;
  if (name.split(/\s+/).some((w) => w.startsWith(q))) return 2;
  if (name.includes(q)) return 3;
  if (entry.keywords.some((k) => k.toLowerCase().includes(q))) return 4;
  return -1;
}

// Entries are plain {id, name, genericName, keywords}; ties go by name.
export function rank(entries, query) {
  const q = query.trim().toLowerCase();
  return entries
    .map((e) => ({ e, t: q ? tier(e, q) : 0, key: e.name.toLowerCase() }))
    .filter((x) => x.t >= 0)
    .sort((a, b) => a.t - b.t || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
    .map((x) => x.e);
}

const PREFIXES = { 'w ': 'windows', 'v ': 'clipboard', ': ': 'emoji', '= ': 'calculator', '> ': 'commands' };

// The apps footer: each prefix with its mode, as the designs end the card, then the moving keys.
export const LEGEND = [['w', 'windows'], ['v', 'clipboard'], [':', 'emoji'], ['=', 'calc'], ['>', 'commands'], ['j/k', 'move'], ['↵', 'open'], ['esc', 'close']];

export function parseQuery(text) {
  const mode = PREFIXES[text.slice(0, 2)];
  return mode ? { mode, q: text.slice(2) } : { mode: 'apps', q: text };
}

// A row is {title, detail, exec?: argv run detached, copy?: text for wl-copy}; a mode adds one function returning rows.
const rows = (entries, q) => rank(entries, q).map((e) => e.row);

// Matches on the window title, then its app_id as a keyword.
export function windowRows(windows, q) {
  return rows(
    windows.map((w) => ({
      name: w.title || '',
      keywords: [w.app_id || ''],
      row: {
        title: w.title || '',
        detail: w.app_id || '',
        id: w.id,
        exec: ['niri', 'msg', 'action', 'focus-window', '--id', String(w.id)],
      },
    })),
    q,
  );
}

const COMMANDS = [
  { title: 'lock', detail: 'Lock the screen', exec: ['qs', 'ipc', 'call', 'lock', 'lock'] },
  { title: 'theme', detail: 'Switch theme', exec: ['qs', 'ipc', 'call', 'themes', 'open'] },
  { title: 'record', detail: 'Start or stop recording', exec: ['qs', 'ipc', 'call', 'record', 'toggle'] },
  { title: 'sync', detail: 'Sync dotfiles', exec: ['dots', 'sync'] },
];

export function commandRows(q) {
  return rows(COMMANDS.map((c) => ({ name: c.title, keywords: [], row: c })), q);
}

export function calcRows(q) {
  const v = calc(q);
  if (v === null) return [];
  const text = format(v);
  return [{ title: text, detail: q.trim(), copy: text }];
}

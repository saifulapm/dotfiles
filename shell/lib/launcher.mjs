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

const PREFIXES = { 'w ': 'windows', 'v ': 'clipboard', ': ': 'emoji', '= ': 'calculator', '> ': 'commands', 'r ': 'reminder' };

export function parseQuery(text) {
  const mode = PREFIXES[text.slice(0, 2)];
  return mode ? { mode, q: text.slice(2) } : { mode: 'apps', q: text };
}

// A row is {title, detail, exec?: argv run detached, copy?: text for wl-copy, icon?, glyph?}; a mode adds one function returning rows.
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
        icon: w.icon,
        id: w.id,
        exec: ['niri', 'msg', 'action', 'focus-window', '--id', String(w.id)],
      },
    })),
    q,
  );
}

// The capture rows come first, as the m24 boards list them; `key` is the global key a row also has, and `tool` the word Paper shows for it.
const COMMANDS = [
  { title: 'Annotate region', detail: 'satty on a region of the screen', tool: 'satty', key: 'Mod+Shift+7', exec: ['dots-capture', 'annotate'] },
  { title: 'Annotate clipboard image', detail: 'satty on the image in the clipboard', tool: 'satty', exec: ['dots-capture', 'annotate-clip'] },
  { title: 'Copy text from region (OCR)', detail: 'tesseract eng+ben, text to the clipboard', tool: 'tesseract', key: 'Mod+Shift+6', exec: ['dots-capture', 'ocr'] },
  { title: 'Read QR code from region', detail: 'zbarimg, copied as sensitive', tool: 'zbarimg', exec: ['dots-capture', 'qr'] },
  { title: 'Pick colour', detail: 'hex to the clipboard', tool: 'niri', exec: ['dots-capture', 'colour'] },
  { title: 'lock', detail: 'Lock the screen', exec: ['qs', 'ipc', 'call', 'lock', 'lock'] },
  { title: 'theme', detail: 'Switch theme', exec: ['qs', 'ipc', 'call', 'themes', 'open'] },
  { title: 'record', detail: 'Start or stop recording', exec: ['qs', 'ipc', 'call', 'record', 'toggle'] },
  { title: 'sync', detail: 'Sync dotfiles', exec: ['dots', 'sync'] },
];

// The user manager's PATH lacks the repo's bin/, so a dots script runs from bin, the one beside the shell.
const fromBin = (c, bin) => (bin && /^dots(-|$)/.test(c.exec[0]) ? Object.assign({}, c, { exec: [`${bin}/${c.exec[0]}`].concat(c.exec.slice(1)) }) : c);

export function commandRows(q, bin) {
  const entries = COMMANDS.map((c) => ({ name: c.title, keywords: [], row: Object.assign({ glyph: '>' }, fromBin(c, bin)) }));
  return q.trim() ? rows(entries, q) : entries.map((e) => e.row);
}

export function calcRows(q) {
  const v = calc(q);
  if (v === null) return [];
  const text = format(v);
  return [{ title: text, detail: q.trim(), copy: text, glyph: '=' }];
}

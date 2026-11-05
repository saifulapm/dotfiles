// Pure pieces of the launcher, kept here so node can test them.
import { calc, format } from './calc.mjs';
import { convert } from './worldclock.mjs';
import { checkTokens } from './theme.mjs';
import { line } from './voice.mjs';

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

const PREFIXES = { 'w ': 'windows', 'v ': 'clipboard', ': ': 'emoji', '= ': 'calculator', '> ': 'commands', 'r ': 'reminder', 'c ': 'colorschemes' };

export function parseQuery(text) {
  const mode = PREFIXES[text.slice(0, 2)];
  return mode ? { mode, q: text.slice(2) } : { mode: 'apps', q: text };
}

// The character a key opens the launcher with from niri's overview: one printable key with no Ctrl, Alt or Mod, else "".
export function overviewChar(text, { ctrl, alt, meta }) {
  if (ctrl || alt || meta || [...text].length !== 1 || /[\u0000-\u001f\u007f]/.test(text)) return '';
  return text;
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
  { title: 'theme', detail: 'Switch colorscheme', exec: ['dots-call', 'launcher', 'mode', 'colorschemes'] },
  { title: 'record', detail: 'Start or stop recording', exec: ['qs', 'ipc', 'call', 'record', 'toggle'] },
  { title: 'sync', detail: 'Sync dotfiles', exec: ['dots', 'sync'] },
];

// The user manager's PATH lacks the repo's bin/, so a dots script runs from bin, the one beside the shell.
const fromBin = (c, bin) => (bin && /^dots(-|$)/.test(c.exec[0]) ? Object.assign({}, c, { exec: [`${bin}/${c.exec[0]}`].concat(c.exec.slice(1)) }) : c);

// Each machine's tailnet name by its machine id; a Remote row opens every one but this machine, so an id outside the map lists all three.
const REMOTES = { 'mac-mini-m2': 'mini', nuc: 'nuc', 'macbook-m2': 'macbook' };

export function commandRows(q, bin, machine) {
  const remotes = Object.keys(REMOTES)
    .filter((id) => id !== machine)
    .map((id) => ({ title: `Remote: ${REMOTES[id]}`, detail: `Show ${REMOTES[id]}'s screen`, exec: ['dots-vnc', REMOTES[id]] }));
  const entries = COMMANDS.concat(remotes).map((c) => ({ name: c.title, keywords: [], row: Object.assign({ glyph: '>' }, fromBin(c, bin)) }));
  return q.trim() ? rows(entries, q) : entries.map((e) => e.row);
}

export function calcRows(q) {
  const v = calc(q);
  if (v === null) return [];
  const text = format(v);
  return [{ title: text, detail: q.trim(), copy: text, glyph: '=' }];
}

// `= 17:00 nyc`: a time and a city read as a conversion to home, once the calculator finds no sum; zones is what bin/dots-zones prints.
export function convertRows(q, now, zones) {
  const c = zones ? convert(q, now, zones) : null;
  return c ? [{ title: `${c.from} = ${c.to}`, detail: c.day || c.utc, copy: c.time, glyph: '=' }] : [];
}

// Accents folded and case dropped, so `rose` finds Rosé Pine.
const fold = (s) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

// themes.json's schemes by title, matched on the title, then the family as a keyword; each row draws paper, surface, accent and ANSI 1, 2, 3 and 5.
export function schemeRows(schemes, q, current, bin) {
  const entries = schemes.map((s) => ({
    name: fold(s.title),
    keywords: [fold(s.family)],
    row: {
      title: s.title,
      detail: s.mode,
      name: s.name,
      current: s.name === current,
      swatches: [s.color.paper, s.color.surface, s.color.accent].concat([1, 2, 3, 5].map((i) => s.color.ansi[i])),
      exec: [bin ? `${bin}/dots` : 'dots', 'colorscheme', s.name],
      stamp: true,
    },
  }));
  return rows(entries, fold(q));
}

// A stamped row's command runs under the key press time, which dots colorscheme times its switch from.
export const stampedExec = (row, now) => (row.stamp ? ['env', `DOTS_SWITCH_T0=${now}`].concat(row.exec) : row.exec);

// themes.json is a file any process can write: each entry passes the check shell.json passes, and its title and family draw as one line of text.
export function schemeList(list) {
  if (!Array.isArray(list)) return [];
  const out = [];
  for (const t of list) {
    try {
      const s = checkTokens(t);
      out.push(Object.assign(s, { title: typeof t.title === 'string' ? line(t.title) : s.name, family: typeof t.family === 'string' ? line(t.family) : '' }));
    } catch (e) {
      continue;
    }
  }
  return out;
}

// The selection moves over every row found, and the window of size rows follows it; selected counts from the window's top.
export function scroll(top, selected, by, total, size) {
  const at = Math.max(0, Math.min(total - 1, top + selected + by));
  const next = at < top ? at : at >= top + size ? at - size + 1 : top;
  return { top: next, selected: at - next };
}

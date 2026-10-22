// What bin/dots-portal and the shell's file picker say to each other, one JSON line each way, and how the picker writes its rows in each theme's voice.
import { line } from './voice.mjs';
import { pad2 } from './margins.mjs';

const MODES = ['open', 'save', 'folder'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
// C0, DEL and C1 controls draw as tofu or end a line, and these marks reorder what follows; line() drops the bidi embeddings.
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const MARK = /[‎‏؜]/g;

const str = (v) => (typeof v === 'string' ? v : '');

// The backend's request, every field kept for the modes that use it, or null for a line that is not one.
export function parseRequest(text) {
  let r;
  try {
    r = JSON.parse(String(text));
  } catch (e) {
    return null;
  }
  if (!r || typeof r !== 'object' || Array.isArray(r) || MODES.indexOf(r.mode) < 0) return null;
  return {
    mode: r.mode,
    multiple: r.multiple === true,
    title: str(r.title),
    app: str(r.app),
    folder: str(r.folder),
    name: str(r.name),
    filters: Array.isArray(r.filters) ? r.filters : [],
    filter: Number.isInteger(r.filter) ? r.filter : 0,
    accept: str(r.accept),
  };
}

// 0 chosen, 1 cancelled, 2 a request the shell could not read.
export const answerLine = (response, paths) => JSON.stringify({ response: response, paths: paths }) + '\n';

// A file name, an app id or a title, as one line of plain text.
export const oneLine = (s) => line(str(s).replace(CONTROL, ' ').replace(MARK, ''));

// The app by its desktop entry, found as the launcher finds a window's, else its id.
export function appName(apps, id) {
  const a = id ? apps.find((e) => e.id.toLowerCase() === id.toLowerCase()) : null;
  return a ? a.name : id;
}

// Folders first, then files, each by name with case ignored, as every board lists them.
export function sortRows(rows) {
  const key = (r) => r.name.toLowerCase();
  return rows.slice().sort((a, b) => (a.dir !== b.dir ? (a.dir ? -1 : 1) : key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : a.name < b.name ? -1 : 1));
}

// Decimal units: whole kilobytes, and one decimal under 10 of a bigger unit.
export function sizeText(row) {
  if (row.dir) return `${row.count} ${row.count === 1 ? 'item' : 'items'}`;
  const n = row.size;
  if (n < 1000) return `${n} B`;
  if (n < 1e6) return `${Math.round(n / 1e3)} KB`;
  const [v, unit] = n < 1e9 ? [n / 1e6, 'MB'] : [n / 1e9, 'GB'];
  return v < 10 ? `${v.toFixed(1)} ${unit}` : `${Math.round(v)} ${unit}`;
}

// Paper gives today's rows their time, Artboard pads the day, Blueprint writes ISO; another year is named.
export function dateText(voice, ms, now) {
  const d = new Date(ms);
  const n = new Date(now);
  const time = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  if (voice === 'bracket') return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${time}`;
  const day = `${voice === 'plain' ? pad2(d.getDate()) : d.getDate()} ${MONTHS[d.getMonth()]}`;
  if (d.getFullYear() !== n.getFullYear()) return `${day} ${d.getFullYear()}`;
  const today = d.getMonth() === n.getMonth() && d.getDate() === n.getDate();
  return voice === 'caps' && today ? `${day} ${time}` : day;
}

export function headingText(voice, app) {
  const head = voice === 'plain' ? 'Open file' : 'OPEN FILE';
  if (!app) return head;
  return voice === 'plain' ? `${head} · ${app}` : `${head}${voice === 'bracket' ? ' // ' : ' · '}${app.toUpperCase()}`;
}

// Artboard spells the keys out; Paper and Blueprint draw ctrl as ⌃ and space as ␣.
export function pickerKeys(voice) {
  const pairs = [['↵', 'open'], ['tab', 'places'], ['ctrl+l', 'path'], ['ctrl+h', 'hidden'], ['ctrl+space', 'select'], ['esc', '']];
  if (voice === 'plain') return pairs.map(([k, w]) => ({ key: k, word: w }));
  const key = (k) => k.replace('ctrl+space', '⌃␣').replace('ctrl+', '⌃').toUpperCase();
  return pairs.map(([k, w]) => ({ key: voice === 'bracket' ? `[${key(k)}]` : key(k), word: w.toUpperCase() }));
}

// ~/.config/gtk-3.0/bookmarks: one "file:///percent/encoded Optional Label" a line; other schemes are not folders here.
export function parseBookmarks(text) {
  const pins = [];
  for (const l of String(text).split('\n')) {
    const m = l.match(/^file:\/\/(\/\S*)(?: (.*))?$/);
    if (!m) continue;
    let path;
    try {
      path = decodeURIComponent(m[1]);
    } catch (e) {
      continue;
    }
    pins.push({ path: path, label: m[2] ? m[2] : path.split('/').pop() });
  }
  return pins;
}

// The places whose names begin with the query, case ignored, and how many letters matched.
export function placeMatches(places, query) {
  if (!query) return [];
  const q = query.toLowerCase();
  const found = [];
  places.forEach((p, i) => {
    if (p.label.toLowerCase().indexOf(q) === 0) found.push({ index: i, length: q.length });
  });
  return found;
}

// A glob as a whole-name pattern: * and ? are wild, [..] a set, every other character itself.
function globRe(glob) {
  let re = '';
  for (const ch of glob) re += ch === '*' ? '.*' : ch === '?' ? '.' : ch === '[' || ch === ']' ? ch : ch.replace(/[\\^$.|+(){}]/g, '\\$&');
  return new RegExp('^' + re + '$', 'i');
}

function mimeHit(mime, want) {
  if (!mime) return false;
  return want.slice(-2) === '/*' ? mime.indexOf(want.slice(0, -1)) === 0 : mime === want;
}

// An app's filter passes a file a glob or a mime type names; folders always pass, to walk into.
function allows(filter, row) {
  if (!filter || row.dir) return true;
  const globs = Array.isArray(filter.globs) ? filter.globs : [];
  const mimes = Array.isArray(filter.mimes) ? filter.mimes : [];
  return globs.some((g) => globRe(String(g)).test(row.name)) || mimes.some((m) => mimeHit(row.mime, String(m)));
}

// The folder's entries as the list draws them: dotfiles when shown, the app's filter, the typed query anywhere in a name.
export function shownRows(entries, opts) {
  const q = (opts.query || '').toLowerCase();
  return sortRows(entries.filter((e) => (opts.hidden || e.name.charAt(0) !== '.') && allows(opts.filter, e) && (!q || e.name.toLowerCase().indexOf(q) >= 0)));
}

// "~/Codes/la" is the folder ~/Codes to list and "la" begun in it; a path without / or ~ starts at the folder shown.
export function splitPath(text, home, folder) {
  let p = text === '~' || text.indexOf('~/') === 0 ? home + text.slice(1) : text;
  if (p.charAt(0) !== '/') p = (folder === '/' ? '' : folder) + '/' + p;
  if (text === '~') p += '/';
  const cut = p.lastIndexOf('/');
  return { parent: p.slice(0, cut).replace(/\/+$/, '') || '/', tail: p.slice(cut + 1) };
}

// Folders whose names start with the tail, the latest changed first; dot folders only when the tail begins with a dot.
export function completions(entries, tail) {
  return entries
    .filter((e) => e.dir && e.name.indexOf(tail) === 0 && (tail.charAt(0) === '.' || e.name.charAt(0) !== '.'))
    .sort((a, b) => b.mtime - a.mtime);
}

const html = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// Styled text with `length` letters from `from` underlined, everything else escaped.
export function marked(text, from, length) {
  if (!length) return html(text);
  return html(text.slice(0, from)) + '<u>' + html(text.slice(from, from + length)) + '</u>' + html(text.slice(from + length));
}

const counted = (n, one, many) => `${n} ${n === 1 ? one : many}`;

// Beside the query: how many places it matched, or how many folders the typed path completes to.
export function matchText(voice, kind, n, label) {
  if (kind === 'path') return voice === 'plain' ? '' : counted(n, 'MATCH', 'MATCHES');
  if (voice === 'plain') return n === 1 ? `→ ${label}` : counted(n, 'place', 'places');
  return counted(n, 'PLACE', 'PLACES');
}

export function countText(voice, n, filterName, hidden) {
  const parts = [counted(n, 'item', 'items')].concat(filterName ? [filterName] : [], [hidden ? 'hidden on' : 'hidden off']);
  const text = parts.join(' · ');
  return voice === 'plain' ? text : text.toUpperCase();
}

// Above the completions; the folder is a path, so it keeps its case.
export function completionHead(voice, n, parent, tail) {
  if (voice === 'plain') return `${counted(n, 'folder', 'folders')} in ${parent} ${n === 1 ? 'starts' : 'start'} with ${tail}`;
  return voice === 'bracket' ? `COMPLETING IN ${parent}` : 'FOLDERS';
}

// Artboard's strip leads with tab and calls the way back the filter; Paper and Blueprint lead with ↵.
export function pathKeys(voice) {
  if (voice === 'plain') return [['tab', 'complete'], ['↵', 'go'], ['ctrl+l', 'filter'], ['esc', '']].map(([k, w]) => ({ key: k, word: w }));
  const pairs = [['↵', 'GO'], ['TAB', 'COMPLETE'], ['⌃L', 'BACK TO LIST'], ['ESC', '']];
  return pairs.map(([k, w]) => ({ key: voice === 'bracket' ? `[${k}]` : k, word: w }));
}

// The decoded picture's size, when there is one, then the file's size and kind from its extension.
export function previewText(voice, row, width, height) {
  const ext = row.name.indexOf('.') > 0 ? row.name.slice(row.name.lastIndexOf('.') + 1).toUpperCase() : '';
  const kind = (ext ? ext + ' ' : '') + (String(row.mime || '').indexOf('image/') === 0 ? 'image' : 'file');
  return { dims: width > 0 ? `${width} × ${height}${voice === 'plain' ? ' px' : ''}` : '', detail: `${sizeText(row)} · ${kind}` };
}

// The preview's full date: Paper's dot, Artboard's comma, Blueprint's ISO.
export function stampText(voice, ms) {
  const d = new Date(ms);
  const time = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  if (voice === 'bracket') return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${time}`;
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}${voice === 'plain' ? ',' : ' ·'} ${time}`;
}

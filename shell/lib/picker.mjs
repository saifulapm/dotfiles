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

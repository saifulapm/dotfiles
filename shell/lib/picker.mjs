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

export function headingText(voice, app, mode, multiple) {
  const word = mode === 'save' ? 'Save as' : mode === 'folder' ? 'Choose folder' : multiple ? 'Open files' : 'Open file';
  const head = voice === 'plain' ? word : word.toUpperCase();
  if (!app) return head;
  return voice === 'plain' ? `${head} · ${app}` : `${head}${voice === 'bracket' ? ' // ' : ' · '}${app.toUpperCase()}`;
}

// Artboard spells the keys out; Paper and Blueprint draw ctrl as ⌃ and space as ␣. Paper's several-files strip calls ctrl+space MARK.
export function pickerKeys(voice, mode, multiple) {
  const space = multiple && voice === 'caps' ? 'mark' : 'select';
  const pairs = mode === 'save' ? [['↵', 'save'], ['tab', 'places'], ['ctrl+l', 'path'], ['ctrl+h', 'hidden'], ['esc', '']] : mode === 'folder' ? [['↵', 'enter folder'], ['ctrl+↵', 'choose this folder'], ['esc', '']] : [['↵', 'open'], ['tab', 'places'], ['ctrl+l', 'path'], ['ctrl+h', 'hidden'], ['ctrl+space', space], ['esc', '']];
  if (voice === 'plain') return pairs.map(([k, w]) => ({ key: k, word: w }));
  const key = (k) => k.replace('ctrl+space', '⌃␣').replace('ctrl+', '⌃').toUpperCase();
  return pairs.map(([k, w]) => ({ key: voice === 'bracket' ? `[${key(k)}]` : key(k), word: w.toUpperCase() }));
}

// Why a name cannot be saved as it is, or "exists" when saving it replaces a file; checked against every entry, as a hidden file is replaced all the same.
export function saveProblem(name, entries) {
  if (name === '') return 'empty';
  if (name.indexOf('/') >= 0) return 'slash';
  if (name === '.' || name === '..') return 'dots';
  const found = entries.find((e) => e.name === name);
  return found ? (found.dir ? 'folder' : 'exists') : '';
}

// The line that takes the key strip's place: the replace question with its two keys, or why the name was refused.
export function saveNotice(voice, tag, name) {
  const SAY = { exists: `${name} exists`, empty: 'type a name to save as', slash: 'a name cannot hold /', dots: `${name} is not a file name`, folder: `${name} is a folder` };
  const say = SAY[tag] || '';
  const keys = tag === 'exists' ? [['↵', 'replace'], ['esc', 'keep']] : [];
  if (voice === 'plain') return { say: say, keys: keys.map(([k, w]) => ({ key: k, word: w })) };
  // Blueprint's error line is caps after a bang, but the name is the file's own and keeps its case.
  const lead = tag === 'exists' || tag === 'dots' || tag === 'folder' ? name : '';
  const text = voice === 'bracket' ? '! ' + lead + say.slice(lead.length).toUpperCase() : say;
  return { say: text, keys: keys.map(([k, w]) => ({ key: voice === 'bracket' ? `[${k.toUpperCase()}]` : k.toUpperCase(), word: w.toUpperCase() })) };
}

// A name as typed into the save field: controls and bidi marks dropped, spaces kept, so "notes " can grow into "notes 2".
export const nameText = (s) => str(s).replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]/g, '');

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

// The folder's entries as the list draws them: dotfiles when shown, only folders when a folder is asked for, the app's filter, the typed query anywhere in a name.
export function shownRows(entries, opts) {
  const q = (opts.query || '').toLowerCase();
  return sortRows(entries.filter((e) => (opts.hidden || e.name.charAt(0) !== '.') && (!opts.folders || e.dir) && allows(opts.filter, e) && (!q || e.name.toLowerCase().indexOf(q) >= 0)));
}

// ctrl+space marks the cursor file or unmarks it; a folder is walked into, never marked, and an undecodable name's path would name another file.
export function toggleMark(marked, row) {
  if (!row || row.dir || row.undecodable) return marked;
  return marked.indexOf(row.name) >= 0 ? marked.filter((n) => n !== row.name) : marked.concat([row.name]);
}

// What ctrl+Enter answers: every marked file in the folder, in the list's order, whatever the query hides.
export function markedPaths(entries, marked, folder) {
  const base = folder === '/' ? '' : folder;
  return sortRows(entries.filter((e) => !e.dir && marked.indexOf(e.name) >= 0)).map((e) => base + '/' + e.name);
}

// The line above the key strip: how many files ctrl+Enter opens, or the folder it chooses, which is a path and keeps its case.
export function footText(voice, mode, n, here) {
  if (mode === 'folder') return voice === 'plain' ? `ctrl+↵ chooses ${here}, the folder you are in` : `THIS FOLDER ${here}`;
  if (n === 0) return '';
  if (voice === 'plain') return `${n} selected · ctrl+↵ open all`;
  return `${n} SELECTED · ${voice === 'bracket' ? '[⌃↵]' : '⌃↵'} OPEN ALL`;
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

const counted = (n, one, many) => `${n} ${n === 1 ? one : many}`;

// Beside the query: how many places it matched, or how many folders the typed path completes to.
export function matchText(voice, kind, n, label) {
  if (kind === 'path') return voice === 'plain' ? '' : counted(n, 'MATCH', 'MATCHES');
  if (voice === 'plain') return n === 1 ? `→ ${label}` : counted(n, 'place', 'places');
  return counted(n, 'PLACE', 'PLACES');
}

// A folder request counts the folders and says files are hidden; a save counts what the folder holds, as the save boards draw it.
export function countText(voice, n, filterName, hidden, mode) {
  const parts = mode === 'folder' ? [counted(n, 'folder', 'folders'), 'files hidden'] : mode === 'save' ? [counted(n, 'item', 'items')] : [counted(n, 'item', 'items')].concat(filterName ? [filterName] : [], [hidden ? 'hidden on' : 'hidden off']);
  const text = parts.join(' · ');
  return voice === 'plain' ? text : text.toUpperCase();
}

// Beside the query: how many files are marked, or that a folder request lists folders only.
export function chipText(voice, mode, marked) {
  const text = mode === 'folder' ? 'folders only' : marked > 0 ? `${marked} marked` : '';
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

// Prints one JSON array of a folder's entries: names as they are spelt, dotfiles too, a folder with how many visible entries it holds, a file with its guessed mime type for the app's filters. A name that is not UTF-8 would stop the print, so it shows with U+FFFD and is marked undecodable; a dangling link lists as itself, so a save over it still asks.
export const LIST_SCRIPT = [
  'import json, mimetypes, os, sys',
  'out = []',
  'for e in os.scandir(sys.argv[1]):',
  '    try:',
  '        try:',
  '            st = e.stat()',
  '        except OSError:',
  '            st = e.stat(follow_symlinks=False)',
  "        name = os.fsencode(e.name).decode('utf-8', 'replace')",
  '        d = e.is_dir()',
  '        n = 0',
  '        if d:',
  '            try:',
  "                n = sum(1 for x in os.scandir(e.path) if not x.name.startswith('.'))",
  '            except OSError:',
  '                pass',
  "        m = '' if d else (mimetypes.guess_type(e.name)[0] or '')",
  "        out.append({'name': name, 'undecodable': name != e.name, 'dir': d, 'size': st.st_size, 'mtime': st.st_mtime * 1000, 'count': n, 'mime': m})",
  '    except OSError:',
  '        pass',
  'print(json.dumps(out, ensure_ascii=False))',
  '',
].join('\n');

// Prints an image's "width height" from its header: PNG's IHDR, GIF's screen, WebP's VP8, VP8L or VP8X chunk, JPEG's frame header past the segments before it. Qt's Image reports the bounded size it decoded, so the picker runs this instead; any other file prints nothing.
export const SIZE_SCRIPT = [
  'import struct, sys',
  "f = open(sys.argv[1], 'rb')",
  'h = f.read(32)',
  's = None',
  "if h[:8] == bytes([137, 80, 78, 71, 13, 10, 26, 10]) and h[12:16] == b'IHDR' and len(h) >= 24:",
  "    s = struct.unpack('>II', h[16:24])",
  "elif h[:6] in (b'GIF87a', b'GIF89a') and len(h) >= 10:",
  "    s = struct.unpack('<HH', h[6:10])",
  "elif h[:4] == b'RIFF' and h[8:12] == b'WEBP' and len(h) >= 25:",
  "    if h[12:16] == b'VP8 ' and len(h) >= 30:",
  "        w, v = struct.unpack('<HH', h[26:30])",
  '        s = (w & 0x3fff, v & 0x3fff)',
  "    elif h[12:16] == b'VP8L':",
  "        b = struct.unpack('<I', h[21:25])[0]",
  '        s = ((b & 0x3fff) + 1, ((b >> 14) & 0x3fff) + 1)',
  "    elif h[12:16] == b'VP8X' and len(h) >= 30:",
  "        s = (int.from_bytes(h[24:27], 'little') + 1, int.from_bytes(h[27:30], 'little') + 1)",
  'elif h[:2] == bytes([255, 216]):',
  '    f.seek(2)',
  '    while True:',
  '        m = f.read(4)',
  '        if len(m) < 4 or m[0] != 255 or m[1] in (216, 217, 218):',
  '            break',
  '        if 192 <= m[1] <= 207 and m[1] not in (196, 200, 204):',
  '            d = f.read(5)',
  '            if len(d) == 5:',
  "                v, w = struct.unpack('>HH', d[1:5])",
  '                s = (w, v)',
  '            break',
  "        f.seek(struct.unpack('>H', m[2:4])[0] - 2, 1)",
  'if s and s[0] > 0 and s[1] > 0:',
  '    print(s[0], s[1])',
  '',
].join('\n');

// The cursor file's meta lines: the size read from its header when there is one, the file's size, its date. Paper and Blueprint label each line, Blueprint heads the pane with the file's kind, Artboard badges the extension.
export function previewText(voice, row, width, height) {
  const ext = row.name.indexOf('.') > 0 ? row.name.slice(row.name.lastIndexOf('.') + 1).toUpperCase() : '';
  const image = String(row.mime || '').indexOf('image/') === 0;
  const lines = (width > 0 ? [['DIMENSIONS', `${width} × ${height}${voice === 'plain' ? ' px' : ''}`]] : []).concat([['SIZE', sizeText(row)], ['MODIFIED', stampText(voice, row.mtime)]]);
  return {
    head: voice === 'bracket' ? 'PREVIEW' : '',
    kind: voice === 'bracket' ? (image ? 'IMAGE' : 'FILE') : '',
    badge: voice === 'plain' ? ext : '',
    lines: lines.map(([label, value]) => ({ label: voice === 'plain' ? '' : label, value: value })),
  };
}

// The preview's full date: Paper's dot, Artboard's comma, Blueprint's ISO.
export function stampText(voice, ms) {
  const d = new Date(ms);
  const time = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  if (voice === 'bracket') return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${time}`;
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}${voice === 'plain' ? ',' : ' ·'} ${time}`;
}

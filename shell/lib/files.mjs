// What Files writes, in each theme's voice; its listing, sizes and preview come from picker.mjs.
import { oneLine, sizeText as pickerSize, sortRows } from './picker.mjs';
import { pad2 } from './margins.mjs';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const counted = (n, one, many) => `${n} ${n === 1 ? one : many}`;
// Blueprint writes its small text in caps; a name is a file's own and is never passed through this.
const say = (voice, text) => (voice === 'bracket' ? text.toUpperCase() : text);

// The folder's own name: the window's title, which the margin draws beside the app id.
export function folderName(home, folder) {
  if (folder === home) return 'Home';
  if (folder === '/') return '/';
  return oneLine(folder.slice(folder.lastIndexOf('/') + 1));
}

// Paper's caps label and ink chip, Artboard's Files and Mod+Y, Blueprint's bracketed key.
export function headText(voice, home, folder) {
  const folderText = folderName(home, folder);
  if (voice === 'caps') return { label: 'FILES', folder: folderText, chip: 'MOD Y' };
  return { label: 'Files', folder: folderText, chip: voice === 'bracket' ? '[MOD+Y]' : 'Mod+Y' };
}

export const places = (home) => ['Home', 'Downloads', 'Codes', 'Pictures', 'Documents'].map((label) => ({ label, path: label === 'Home' ? home : `${home}/${label}` }));

// Every board writes a row's day, month and time; a row from another year names the year instead.
export function dateText(voice, ms, now) {
  const d = new Date(ms);
  const tail = d.getFullYear() === new Date(now).getFullYear() ? `${pad2(d.getHours())}:${pad2(d.getMinutes())}` : String(d.getFullYear());
  return say(voice, `${d.getDate()} ${MONTHS[d.getMonth()]} ${tail}`);
}

export const sizeText = (voice, row) => say(voice, pickerSize(row));

export const countText = (voice, n, hidden) => say(voice, `${counted(n, 'item', 'items')} · hidden ${hidden ? 'on' : 'off'}`);

// The status line's counts, and the cursor's place in the list, which an empty folder leaves blank.
export function statusText(voice, rows, marked, at) {
  const folders = rows.filter((r) => r.dir).length;
  const counts = [counted(rows.length, 'item', 'items'), counted(folders, 'folder', 'folders'), counted(rows.length - folders, 'file', 'files'), `${marked.length} marked`].join(' · ');
  return { counts: say(voice, counts), at: rows.length ? say(voice, `${at + 1} of ${rows.length}`) : '' };
}

// Space marks any row, a folder too, to copy, move or trash it; an undecodable name's path would name another file.
export function toggleMark(marked, row) {
  if (!row || row.undecodable) return marked;
  return marked.indexOf(row.name) >= 0 ? marked.filter((n) => n !== row.name) : marked.concat([row.name]);
}

// What y, x, d, o and s act on: the marked rows in the list's order, or the cursor row when nothing is marked (#Q4T3GECS).
export function targets(rows, marked, folder, cursor) {
  const base = folder === '/' ? '' : folder;
  const picked = marked.length ? sortRows(rows.filter((r) => marked.indexOf(r.name) >= 0)) : cursor ? [cursor] : [];
  return picked.map((r) => `${base}/${r.name}`);
}

// A drag that starts on a marked row carries every marked row, as the marked board draws it; on any other row, only that row.
export function dragPaths(rows, marked, folder, pressed) {
  return targets(rows, marked.indexOf(pressed.name) >= 0 ? marked : [], folder, pressed);
}

const fileUri = (path) => 'file://' + path.split('/').map(encodeURIComponent).join('/');

// text/uri-list as foot and Chromium read it: one encoded URI a line, each ended by CRLF.
export const uriList = (paths) => paths.map((p) => fileUri(p) + '\r\n').join('');

export const chipText = (voice, n) => say(voice, counted(n, 'file', 'files'));

// While a drag runs, the status line counts what it carries and says so.
export const dragText = (voice, rows) => ({ counts: say(voice, `${rows.length} marked · ${pickerSize({ dir: false, size: rows.reduce((n, r) => n + (r.dir ? 0 : r.size), 0) })}`), at: say(voice, 'dragging') });

const DRAG_KEYS = [['space', 'mark'], ['drag', 'drop on a window or a folder row'], ['e', 'eject drive'], ['esc', 'close']];

// The Share list's head: what goes and where it can go; Paper and Blueprint write the label in caps.
export function shareHead(voice, n, bytes) {
  return { label: voice === 'plain' ? 'Share' : 'SHARE', count: say(voice, `${counted(n, 'file', 'files')} · ${pickerSize({ size: bytes })}`), tag: say(voice, 'tailnet') };
}

// What s sends: the rows y and x act on, with their bytes; a folder has no bytes of its own to count.
export function shareSet(rows, marked, folder, cursor) {
  const names = marked.length ? marked : cursor ? [cursor.name] : [];
  const bytes = rows.filter((r) => names.indexOf(r.name) >= 0 && !r.dir).reduce((sum, r) => sum + r.size, 0);
  return { paths: targets(rows, marked, folder, cursor), bytes };
}

// A tailnet machine as the Share list draws it: its address while online, when it was last seen once offline.
export function shareRow(voice, machine) {
  const detail = machine.online ? machine.ip : machine.age ? `offline, seen ${machine.age} ago` : 'offline';
  return { name: oneLine(machine.name), detail: say(voice, detail), status: say(voice, machine.online ? 'online' : 'offline') };
}

// The preview's three lines: the image's size from its header, the file's size and kind, its full date.
export function previewMeta(voice, row, width, height) {
  const d = new Date(row.mtime);
  const dot = row.name.lastIndexOf('.');
  const ext = dot > 0 ? row.name.slice(dot + 1).toUpperCase() : '';
  // An image is named by its type, as the board's JPEG image is a .jpg; any other file by its extension.
  const mime = String(row.mime || '');
  const kind = row.dir ? 'folder' : mime.indexOf('image/') === 0 ? `${mime.slice(6).split('+')[0].toUpperCase()} image` : ext ? `${ext} file` : 'file';
  const time = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  const date = voice === 'bracket' ? `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} · ${time}` : `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()} · ${time}`;
  return { dims: width > 0 ? `${width} × ${height}` : '', kind: say(voice, `${pickerSize(row)} · ${kind}`), date };
}

// The place a find query opens: the only one whose name starts with it, or -1 (#NYNGZ3NC).
export function findPlace(places, query) {
  const q = query.toLowerCase();
  const hits = q ? places.map((p, i) => (p.label.toLowerCase().indexOf(q) === 0 ? i : -1)).filter((i) => i >= 0) : [];
  return hits.length === 1 ? hits[0] : -1;
}

export const findText = (voice, query) => `/ ${oneLine(query)}`;

// How much of a name r selects: up to its last dot, so a rename keeps the extension; a folder or a dotfile whole.
export function stemLength(row) {
  const dot = row.name.lastIndexOf('.');
  return row.dir || dot <= 0 ? row.name.length : dot;
}

// Why a typed name cannot be made, or "" when it can; a taken name is refused, never overwritten (#GMXENA6Y).
export function nameProblem(name, entries) {
  if (name === '') return 'empty';
  if (name.indexOf('/') >= 0) return 'slash';
  if (name === '.' || name === '..') return 'dots';
  return entries.some((e) => e.name === name) ? 'exists' : '';
}

// Blueprint's error line is caps after a bang, but the name is the file's own and keeps its case.
export function noticeText(voice, tag, name) {
  const shown = oneLine(name);
  const SAY = { exists: [shown, ' exists'], empty: ['', 'type a name'], slash: ['', 'a name cannot hold /'], dots: [shown, ' is not a name'], failed: ['', 'could not do that'] };
  const [lead, rest] = SAY[tag] || ['', tag];
  return voice === 'bracket' ? `! ${lead}${rest.toUpperCase()}` : lead + rest;
}

const keyPair = (voice, [k, w]) => (voice === 'bracket' ? { key: `[${k.toUpperCase()}]`, word: w.toUpperCase() } : { key: k, word: w });

export const promptText = (voice, pairs) => pairs.map((p) => keyPair(voice, p)).map((p) => `${p.key} ${p.word}`).join(' · ');

// d asks first, in the bar above the keys.
export const trashAsk = (voice, n) => ({ say: say(voice, `trash ${counted(n, 'file', 'files')} ·`), keys: [keyPair(voice, ['↵', 'trash ·']), keyPair(voice, ['esc', 'keep'])] });

// Renames argv[1] to argv[2] with RENAME_NOREPLACE, so a name taken since it was checked is never overwritten; prints why it failed.
export const RENAME_SCRIPT = [
  'import ctypes, os, sys',
  'libc = ctypes.CDLL(None, use_errno=True)',
  'if libc.renameat2(-100, os.fsencode(sys.argv[1]), -100, os.fsencode(sys.argv[2]), 1) != 0:',
  '    sys.exit(os.strerror(ctypes.get_errno()))',
  '',
].join('\n');

export const tilde = (home, path) => (path === home ? '~' : path.indexOf(home + '/') === 0 ? '~' + path.slice(home.length) : path);

const KEYS = [['j/k', 'move'], ['h/l', 'up / in'], ['space', 'mark'], ['y x p', 'copy cut paste'], ['r', 'rename'], ['a', 'new folder'], ['d', 'trash'], ['o', 'open with'], ['s', 'share'], ['e', 'eject drive'], ['/', 'find'], ['tab', 'places'], ['esc', 'close']];

// Paper and Artboard write keys as typed, Blueprint brackets them and every word in caps.
const strip = (voice, pairs) => pairs.map(([k, w]) => (voice === 'bracket' ? { key: `[${k.toUpperCase()}]`, word: w.toUpperCase() } : { key: k, word: w }));
export const keyStrip = (voice) => strip(voice, KEYS);
export const dragKeys = (voice) => strip(voice, DRAG_KEYS);

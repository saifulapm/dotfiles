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

export const tilde = (home, path) => (path === home ? '~' : path.indexOf(home + '/') === 0 ? '~' + path.slice(home.length) : path);

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
  // An undecodable name's path would name another file, as toggleMark refuses it.
  const picked = marked.length ? sortRows(rows.filter((r) => marked.indexOf(r.name) >= 0)) : cursor && !cursor.undecodable ? [cursor] : [];
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
  const SAY = { exists: [shown, ' exists'], empty: ['', 'type a name'], slash: ['', 'a name cannot hold /'], dots: [shown, ' is not a name'], failed: ['', 'could not do that'], itself: [shown, ' cannot go into itself'], missing: [shown, ' is gone'], busy: ['', 'a copy is running; wait for it to finish'], unreadable: [shown, ' cannot be read'] };
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

// The drives udiskie mounted, from findmnt --list --json -b -o TARGET,LABEL,SIZE: a drive is named by its label, else its folder.
export function drives(voice, text, user) {
  let found = [];
  try {
    found = JSON.parse(text).filesystems;
  } catch (e) {
    return [];
  }
  const root = `/run/media/${user}/`;
  return found
    .filter((m) => m.target.indexOf(root) === 0)
    .map((m) => ({ label: oneLine(m.label || m.target.slice(root.length)), path: m.target, size: sizeText(voice, { size: m.size }), group: 'drives' }));
}

// Every board heads the drives DRIVES but Artboard, and Blueprint writes the eject key in caps.
export const driveText = (voice) => ({ head: voice === 'plain' ? 'Drives' : 'DRIVES', badge: voice === 'bracket' ? 'E' : 'e' });

// A drop's local files; a web URL or an undecodable one is not a file Files can copy.
export function dropPaths(urls) {
  const paths = [];
  for (const u of urls) {
    const m = String(u).match(/^file:\/\/(\/.*)$/);
    if (!m) continue;
    let path;
    try {
      path = decodeURIComponent(m[1]);
    } catch (e) {
      continue;
    }
    // A NUL would end the argument there and name the folder above it.
    if (path.indexOf('\0') < 0) paths.push(path);
  }
  return paths;
}

// What a hovering drop will do; a drop always copies. The folder's name keeps its case in Blueprint's caps.
export function dropText(voice, paths, folder) {
  const what = say(voice, `copy ${counted(paths.length, 'file', 'files')} into `) + oneLine(folder) + '/';
  return { counts: what, at: paths.length === 1 ? oneLine(paths[0].slice(paths[0].lastIndexOf('/') + 1)) : say(voice, counted(paths.length, 'file', 'files')) };
}

export const dropHere = (voice) => (voice === 'bracket' ? '[DROP HERE]' : 'drop here');

const DROP_KEYS = [['drop', 'copy into the folder under the pointer'], ['esc', 'cancel the drag']];

// Bytes in another size's unit, so the progress reads "41 of 96 MB".
function inUnitOf(n, total) {
  const unit = total < 1e6 ? 1e3 : total < 1e9 ? 1e6 : 1e9;
  const v = n / unit;
  return v === 0 ? '0' : v < 10 ? v.toFixed(1) : String(Math.round(v));
}

// The line above the status line while a copy or move runs; the folder it comes from is a path and keeps its case.
export function opLine(voice, home, op) {
  const verb = op.mode === 'move' ? 'moving' : 'copying';
  const pct = op.total > 0 ? (op.done >= op.total ? 100 : Math.min(99, Math.round((op.done * 100) / op.total))) : 0;
  const parts = [`${pct}%`, `${inUnitOf(op.done, op.total)} of ${pickerSize({ size: op.total })}`].concat(op.rate > 0 ? [`${pickerSize({ size: op.rate })}/s`] : []);
  return {
    say: say(voice, `${verb} ${counted(op.items.length, 'file', 'files')} from `) + oneLine(tilde(home, op.from)),
    // Until the op has summed its sources there is no size to give.
    progress: op.total > 0 ? say(voice, parts.join(' · ')) : '',
    keys: voice === 'bracket' ? '[CTRL+C] CANCELS' : 'ctrl+c cancels',
  };
}

// The copy-failure card: the error, then each source as copied, stopped (its partial copy removed) or not started.
export function failText(voice, op) {
  const f = op.failed;
  const full = f.error === 'No space left on device';
  const names = op.items.map((i) => oneLine(i.name));
  // A dropped file's size is not known here, nor a folder's.
  const size = (i) => (i.dir || i.size == null ? '' : ` · ${pickerSize({ size: i.size })}`);
  const rows = op.items.map((item, i) => ({
    name: names[i],
    state: say(voice, f.copied.indexOf(i) >= 0 ? `copied${size(item)}` : i === f.index ? 'stopped · partial removed' : `not started${size(item)}`),
    stopped: i === f.index,
  }));
  const left = op.items.length - f.copied.length;
  const why = `${full ? `No space left on ${oneLine(op.to)}` : oneLine(f.error)}. ${f.copied.length} of ${counted(op.items.length, 'file', 'files')} ${f.copied.length === 1 ? 'was' : 'were'} copied; ${left} ${left === 1 ? 'was' : 'were'} not.`;
  return {
    head: say(voice, op.mode === 'move' ? 'Move failed' : 'Copy failed'),
    title: say(voice, full ? `${oneLine(op.to)} is full` : oneLine(f.error)),
    why,
    rows,
    foot: say(voice, 'Nothing half-written is left: the partial ') + (f.file ? oneLine(f.file.slice(f.file.lastIndexOf('/') + 1)) : names[f.index]) + say(voice, ` was deleted, and the ${f.copied.length} copied ${f.copied.length === 1 ? 'file is' : 'files are'} whole.`),
    keys: promptText(voice, [['r', 'retry'], ['s', 'skip this file'], ['esc', 'cancel the rest']]),
  };
}

export const stoppedText = (voice, to, copied, n) => ({ counts: say(voice, `copy to ${oneLine(to)} stopped`), at: say(voice, `${copied} of ${n} copied`) });

// Open with's head: "3 JPEG images" from the type's own description, or files when the targets' types differ.
export function openWithHead(voice, n, description, apps) {
  const title = description ? `${n} ${description}${n === 1 ? '' : 's'}` : counted(n, 'file', 'files');
  return { title: say(voice, title), count: say(voice, counted(apps, 'app', 'apps')) };
}

// An app's row: its name, then its kind and command, which keeps its case as a name does; a desktop entry may hold any text.
export function appText(voice, app) {
  const kind = app.generic ? say(voice, oneLine(app.generic)) + ' · ' : '';
  return { name: oneLine(app.name), sub: kind + oneLine(app.exec), badge: app.default ? (voice === 'bracket' ? '[DEFAULT]' : 'default') : '' };
}


const KEYS = [['j/k', 'move'], ['h/l', 'up / in'], ['space', 'mark'], ['y x p', 'copy cut paste'], ['r', 'rename'], ['a', 'new folder'], ['d', 'trash'], ['o', 'open with'], ['s', 'share'], ['e', 'eject drive'], ['/', 'find'], ['tab', 'places'], ['esc', 'close']];

// Paper and Artboard write keys as typed, Blueprint brackets them and every word in caps.
const strip = (voice, pairs) => pairs.map(([k, w]) => (voice === 'bracket' ? { key: `[${k.toUpperCase()}]`, word: w.toUpperCase() } : { key: k, word: w }));
export const keyStrip = (voice) => strip(voice, KEYS);
export const dragKeys = (voice) => strip(voice, DRAG_KEYS);
export const dropKeys = (voice) => strip(voice, DROP_KEYS);

// Every board draws a file row with the page icon, an image too; only a folder differs.
export const rowIcon = (row) => (row.dir ? 'folder' : 'file');

const PLACE_ICONS = { Home: 'home', Downloads: 'download', Codes: 'code', Pictures: 'picture', Documents: 'document' };
export const placeIcon = (place) => (place.group === 'places' ? PLACE_ICONS[place.label] : { pinned: 'bookmark', drives: 'drive', trash: 'trash' }[place.group]);

// The boards' 16 px line icons; a tick is in its own box, 16 for Paper's mark and 9 for Artboard's circle.
const ICONS = {
  folder: 'M1.8 4.2h4l1.4 1.6h7v6.6H1.8z',
  file: 'M3.5 1.8h6l3 3v9.4h-9z M9.5 1.8v3h3',
  home: 'M2 7.5L8 2.5l6 5M3.8 6.8v6.4h8.4V6.8',
  download: 'M8 2.5v8M4.8 7.5L8 10.7l3.2-3.2M3 13.5h10',
  code: 'M5.5 4.5L2 8l3.5 3.5M10.5 4.5L14 8l-3.5 3.5',
  picture: 'M2 3.2h12v9.6H2z M2 11l3.6-3.4 3 3 2-1.8L14 11',
  document: 'M3.5 1.8h9v12.4h-9z M5.5 5h5 M5.5 8h5 M5.5 11h3',
  bookmark: 'M4.5 2.5h7v11L8 10.8l-3.5 2.7z',
  drive: 'M3 6.5h10v6H3z M5.5 6.5v-3h5v3 M6.5 9.5h.01 M9.5 9.5h.01',
  trash: 'M3 4.5h10 M6 4.5V2.8h4v1.7 M4.2 4.5l.6 9h6.4l.6-9',
  tick: 'M3.5 8.5l3 3 6-7',
};
const ROUND_ICONS = Object.assign({}, ICONS, {
  folder: 'M2 4.5A1.5 1.5 0 0 1 3.5 3H6l1.5 1.8h5A1.5 1.5 0 0 1 14 6.3v5.2a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 11.5z',
  file: 'M4 1.8h5l3 3V13a1.2 1.2 0 0 1-1.2 1.2H4A1.2 1.2 0 0 1 2.8 13V3A1.2 1.2 0 0 1 4 1.8zM9 1.8V5h3',
  home: 'M2.2 7.6L8 2.6l5.8 5M3.8 6.8V13h8.4V6.8',
  download: 'M8 2.5v8M4.8 7.6L8 10.8l3.2-3.2M3 13.5h10',
  code: 'M5.6 4.4L2 8l3.6 3.6M10.4 4.4L14 8l-3.6 3.6',
  // The board's rect and filled dot as one stroked path: a dot of radius .4 under a 1.5 stroke is 2.3 px across, the board's is 2.2.
  picture: 'M4 2.5h8a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z M3 11.5l3.2-3.4 2.6 2.6 1.8-1.8 2.4 2.6 M10.1 5.6a.4 .4 0 1 0 .8 0a.4 .4 0 1 0-.8 0',
  document: 'M4 1.8h5l3 3V13a1.2 1.2 0 0 1-1.2 1.2H4A1.2 1.2 0 0 1 2.8 13V3A1.2 1.2 0 0 1 4 1.8zM9 1.8V5h3M5 8.5h5M5 11h3',
  bookmark: 'M9.6 2l4.4 4.4-2.2.5-2.1 2.9.2 2.2L8.2 11 4 14.2 5 10 3 7.8l2.2.2L8.1 5.9z',
  tick: 'M1.5 4.6l2 2L7.5 2.4',
});
export const iconPath = (voice, kind) => (voice === 'plain' ? ROUND_ICONS : ICONS)[kind] || '';

// The path line: "~/" muted, then the folder's own name; home and the root are one part.
export function pathParts(home, folder) {
  const path = tilde(home, folder);
  const cut = path.lastIndexOf('/') + 1;
  return path === '/' || cut === 0 ? { lead: '', name: oneLine(path) } : { lead: oneLine(path.slice(0, cut)), name: oneLine(path.slice(cut)) };
}

// What differs between the three Files boards beyond the tokens: the mark, the row, the date's face, the header and the key strip.
const LOOKS = {
  caps: { mark: 'box', stroke: 1.3, row: 32, tile: false, date: { face: 'display', italic: true, size: 17 }, head: { face: 'display', size: 18, weight: 400 }, strip: { caps: true, size: 10, spacing: 1, keyWeight: 700, chip: false } },
  plain: { mark: 'circle', stroke: 1.5, row: 38, tile: true, date: { face: 'mono', italic: false, size: 12 }, head: { face: 'ui', size: 14, weight: 700 }, strip: { caps: false, size: 11, spacing: 0, keyWeight: 500, chip: true } },
  bracket: { mark: 'bracket', stroke: 1.3, row: 32, tile: false, date: { face: 'mono', italic: false, size: 12 }, head: { face: 'mono', size: 12, weight: 700 }, strip: { caps: false, size: 11, spacing: 1.5, keyWeight: 700, chip: false } },
};
export const filesLook = (voice) => LOOKS[voice] || LOOKS.caps;

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as F from './files.mjs';

test('the header names Files and the folder, with Mod+Y in each theme\'s key idiom', () => {
  assert.deepEqual(F.headText('caps', '/home/s', '/home/s/Downloads'), { label: 'FILES', folder: 'Downloads', chip: 'MOD Y' });
  assert.deepEqual(F.headText('plain', '/home/s', '/home/s/Downloads'), { label: 'Files', folder: 'Downloads', chip: 'Mod+Y' });
  assert.deepEqual(F.headText('bracket', '/home/s', '/home/s/Downloads'), { label: 'Files', folder: 'Downloads', chip: '[MOD+Y]' });
});

test('the window title is the folder\'s name, Home for the home folder and / for the root', () => {
  assert.equal(F.folderName('/home/s', '/home/s/Downloads'), 'Downloads');
  assert.equal(F.folderName('/home/s', '/home/s'), 'Home');
  assert.equal(F.folderName('/home/s', '/'), '/');
});

test('a folder name with a newline or U+202E is one plain line', () => {
  assert.equal(F.folderName('/home/s', '/home/s/a\nb‮c'), 'a bc');
});

test('the places are Home, Downloads, Codes, Pictures and Documents under the home folder', () => {
  assert.deepEqual(F.places('/home/s').map((p) => [p.label, p.path]), [
    ['Home', '/home/s'],
    ['Downloads', '/home/s/Downloads'],
    ['Codes', '/home/s/Codes'],
    ['Pictures', '/home/s/Pictures'],
    ['Documents', '/home/s/Documents'],
  ]);
});

test('a row\'s date is its day, month and time, Blueprint in caps, another year named instead of the time', () => {
  const now = new Date(2026, 9, 23, 14, 32).getTime();
  const ms = new Date(2026, 9, 19, 9, 12).getTime();
  assert.equal(F.dateText('caps', ms, now), '19 Oct 09:12');
  assert.equal(F.dateText('plain', ms, now), '19 Oct 09:12');
  assert.equal(F.dateText('bracket', ms, now), '19 OCT 09:12');
  assert.equal(F.dateText('caps', new Date(2025, 0, 3, 8, 0).getTime(), now), '3 Jan 2025');
});

test('a folder row says how many items it holds, a file its size, Blueprint in caps', () => {
  assert.equal(F.sizeText('caps', { dir: true, count: 8 }), '8 items');
  assert.equal(F.sizeText('bracket', { dir: true, count: 1 }), '1 ITEM');
  assert.equal(F.sizeText('plain', { dir: false, size: 3100000 }), '3.1 MB');
});

test('the path line counts the rows and says whether hidden files show', () => {
  assert.equal(F.countText('caps', 12, false), '12 items · hidden off');
  assert.equal(F.countText('bracket', 1, true), '1 ITEM · HIDDEN ON');
});

test('the status line counts folders, files and marks, and where the cursor is', () => {
  const rows = [{ name: 'a', dir: true }, { name: 'b', dir: true }, { name: 'c', dir: false }];
  assert.deepEqual(F.statusText('caps', rows, ['c'], 2), { counts: '3 items · 2 folders · 1 file · 1 marked', at: '3 of 3' });
  assert.deepEqual(F.statusText('bracket', rows, [], 0), { counts: '3 ITEMS · 2 FOLDERS · 1 FILE · 0 MARKED', at: '1 OF 3' });
  assert.deepEqual(F.statusText('plain', [], [], 0), { counts: '0 items · 0 folders · 0 files · 0 marked', at: '' });
});

test('space marks a folder as well as a file, and unmarks it again; an undecodable name is never marked', () => {
  assert.deepEqual(F.toggleMark([], { name: 'shots', dir: true }), ['shots']);
  assert.deepEqual(F.toggleMark(['shots', 'a.jpg'], { name: 'shots', dir: true }), ['a.jpg']);
  assert.deepEqual(F.toggleMark([], { name: 'x�', dir: false, undecodable: true }), []);
});

test('an action takes the marked rows in the list\'s order, or the cursor row when none is marked', () => {
  const rows = [{ name: 'shots', dir: true }, { name: 'a.jpg', dir: false }, { name: 'b.jpg', dir: false }];
  assert.deepEqual(F.targets(rows, ['b.jpg', 'shots'], '/home/s', rows[1]), ['/home/s/shots', '/home/s/b.jpg']);
  assert.deepEqual(F.targets(rows, [], '/home/s', rows[1]), ['/home/s/a.jpg']);
  assert.deepEqual(F.targets(rows, [], '/', rows[0]), ['/shots']);
  assert.deepEqual(F.targets([], [], '/home/s', null), []);
  assert.deepEqual(F.targets(rows, [], '/home/s', { name: 'caf\ufffd.txt', dir: false, undecodable: true }), []);
});

test('the preview names an image\'s size, kind and date, Blueprint in caps and ISO', () => {
  const row = { name: 'IMG_2041.jpg', dir: false, size: 3100000, mime: 'image/jpeg', mtime: new Date(2026, 9, 14, 16, 41).getTime() };
  assert.deepEqual(F.previewMeta('caps', row, 4032, 3024), { dims: '4032 × 3024', kind: '3.1 MB · JPEG image', date: '14 Oct 2026 · 16:41' });
  assert.deepEqual(F.previewMeta('bracket', row, 4032, 3024), { dims: '4032 × 3024', kind: '3.1 MB · JPEG IMAGE', date: '2026-10-14 · 16:41' });
  const pdf = { name: 'invoice-0912.pdf', dir: false, size: 184000, mime: 'application/pdf', mtime: row.mtime };
  assert.deepEqual(F.previewMeta('plain', pdf, 0, 0), { dims: '', kind: '184 KB · PDF file', date: '14 Oct 2026 · 16:41' });
  assert.equal(F.previewMeta('caps', { name: 'Makefile', dir: false, size: 10, mime: '', mtime: row.mtime }, 0, 0).kind, '10 B · file');
  assert.equal(F.previewMeta('caps', { name: 'shots', dir: true, count: 8, mtime: row.mtime }, 0, 0).kind, '8 items · folder');
});

test('a find query that starts exactly one place\'s name opens it; any other narrows the rows', () => {
  const places = [{ label: 'Home' }, { label: 'Downloads' }, { label: 'Codes' }, { label: 'Pictures' }, { label: 'Documents' }];
  assert.equal(F.findPlace(places, 'do'), -1);
  assert.equal(F.findPlace(places, 'dow'), 1);
  assert.equal(F.findPlace(places, 'DOWN'), 1);
  assert.equal(F.findPlace(places, '2041'), -1);
  assert.equal(F.findPlace(places, ''), -1);
  // One or two letters narrow the rows: /I in a folder of IMG_ files must not jump to a pin named invoices.
  assert.equal(F.findPlace(places.concat([{ label: 'invoices' }]), 'i'), -1);
  assert.equal(F.findPlace(places.concat([{ label: 'invoices' }]), 'inv'), 5);
});

test('the path line shows the find query in place of the counts while one is typed', () => {
  assert.equal(F.findText('caps', '2041'), '/ 2041');
  assert.equal(F.findText('bracket', 'a\nb'), '/ a b');
});

test('a z jump asks zoxide for the typed words, and none asks nothing', () => {
  assert.deepEqual(F.jumpWords('  dot  files '), ['dot', 'files']);
  assert.deepEqual(F.jumpWords('-x'), ['-x']);
  assert.deepEqual(F.jumpWords(' '), []);
});

test('the path line shows a z jump\'s words and where they go, or that they go nowhere', () => {
  assert.equal(F.jumpText('caps', '/home/s', 'dotf', '/home/s/Codes/dotfiles'), 'z dotf → ~/Codes/dotfiles');
  assert.equal(F.jumpText('caps', '/home/s', 'dotf', null), 'z dotf');
  assert.equal(F.jumpText('caps', '/home/s', 'qq', ''), 'z qq · no match');
  assert.equal(F.jumpText('bracket', '/home/s', 'qq', ''), 'z qq · NO MATCH');
  assert.equal(F.jumpText('caps', '/home/s', '', ''), 'z ');
  assert.equal(F.jumpText('caps', '/home/s', 'a\nb', '/x\ny'), 'z a b → /x y');
});

test('rename selects the name without its extension; a folder or a dotfile is selected whole', () => {
  assert.equal(F.stemLength({ name: 'invoice-0912.pdf', dir: false }), 12);
  assert.equal(F.stemLength({ name: 'a.tar.gz', dir: false }), 5);
  assert.equal(F.stemLength({ name: '.bashrc', dir: false }), 7);
  assert.equal(F.stemLength({ name: 'v1.2', dir: true }), 4);
});

test('a new name is refused when empty, holding /, . or .., or taken; never overwritten', () => {
  const entries = [{ name: 'notes.txt' }, { name: 'shots' }];
  assert.equal(F.nameProblem('', entries), 'empty');
  assert.equal(F.nameProblem('a/b', entries), 'slash');
  assert.equal(F.nameProblem('..', entries), 'dots');
  assert.equal(F.nameProblem('shots', entries), 'exists');
  assert.equal(F.nameProblem('invoice-0913.pdf', entries), '');
});

test('a refused name says why on the status line, the name in its own case', () => {
  assert.equal(F.noticeText('caps', 'exists', 'Notes.txt'), 'Notes.txt exists');
  assert.equal(F.noticeText('bracket', 'exists', 'Notes.txt'), '! Notes.txt EXISTS');
  assert.equal(F.noticeText('plain', 'slash', 'a/b'), 'a name cannot hold /');
  assert.equal(F.noticeText('caps', 'busy', ''), 'a copy is running; wait for it to finish');
  assert.equal(F.noticeText('caps', 'unreadable', 'secret'), 'secret cannot be read');
});

test('the prompts pair their keys as each theme writes them', () => {
  assert.equal(F.promptText('caps', [['↵', 'save'], ['esc', 'cancel']]), '↵ save · esc cancel');
  assert.equal(F.promptText('bracket', [['↵', 'save'], ['esc', 'cancel']]), '[↵] SAVE · [ESC] CANCEL');
  assert.deepEqual(F.trashAsk('caps', 2), { say: 'trash 2 files ·', keys: [{ key: '↵', word: 'trash ·' }, { key: 'esc', word: 'keep' }] });
  assert.deepEqual(F.trashAsk('bracket', 1), { say: 'TRASH 1 FILE ·', keys: [{ key: '[↵]', word: 'TRASH ·' }, { key: '[ESC]', word: 'KEEP' }] });
});

test('a drop takes the local files it carries, decoded, and nothing else', () => {
  assert.deepEqual(F.dropPaths(['file:///h/Downloads/report%20final.pdf', 'https://example.com/a.pdf', 'file:///h/%C3%A9.txt']), ['/h/Downloads/report final.pdf', '/h/é.txt']);
  assert.deepEqual(F.dropPaths(['file:///h/bad%E0%A4%A.txt']), []);
  assert.deepEqual(F.dropPaths(['file:///home/s/Documents%00x']), []);
});

test('while a drop hovers, the status line says what it will do and the row says drop here', () => {
  assert.deepEqual(F.dropText('caps', ['/d/report-final.pdf'], 'screenshots'), { counts: 'copy 1 file into screenshots/', at: 'report-final.pdf' });
  assert.deepEqual(F.dropText('bracket', ['/d/a', '/d/b'], 'Shots'), { counts: 'COPY 2 FILES INTO Shots/', at: '2 FILES' });
  assert.equal(F.dropText('caps', ['/d/a', '/d/b'], 'shots').at, '2 files');
  assert.equal(F.dropHere('caps'), 'drop here');
  assert.equal(F.dropHere('bracket'), '[DROP HERE]');
  assert.deepEqual(F.dropKeys('caps').map((k) => k.key), ['drop', 'esc']);
});

test('a running copy says what it copies from where, its percent, sizes and rate', () => {
  const op = { mode: 'copy', items: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], from: '/h/Pictures', done: 41000000, total: 96000000, rate: 12000000 };
  assert.deepEqual(F.opLine('caps', '/h', op), { say: 'copying 3 files from ~/Pictures', progress: '43% · 41 of 96 MB · 12 MB/s', keys: 'ctrl+c cancels' });
  assert.deepEqual(F.opLine('bracket', '/h', op), { say: 'COPYING 3 FILES FROM ~/Pictures', progress: '43% · 41 OF 96 MB · 12 MB/S', keys: '[CTRL+C] CANCELS' });
  const move = { mode: 'move', items: [{ name: 'a' }], from: '/h/D', done: 500, total: 2000, rate: 0 };
  assert.deepEqual(F.opLine('plain', '/h', move), { say: 'moving 1 file from ~/D', progress: '25% · 0.5 of 2 KB', keys: 'ctrl+c cancels' });
  assert.equal(F.opLine('caps', '/h', Object.assign({}, move, { done: 0, total: 0 })).progress, '');
});

test('a failed copy names each file as copied, stopped or not started, and what to press', () => {
  const op = {
    mode: 'copy', to: 'T7 Shield',
    items: [{ name: 'IMG_2039.jpg', size: 2800000 }, { name: 'IMG_2040.jpg', size: 3000000 }, { name: 'IMG_2041.jpg', size: 3100000 }, { name: 'diagram\nv2.png', size: 412000 }],
    failed: { index: 2, error: 'No space left on device', copied: [0, 1], pending: [3] },
  };
  const f = F.failText('caps', op);
  assert.equal(f.head, 'Copy failed');
  assert.equal(f.title, 'T7 Shield is full');
  assert.equal(f.why, 'No space left on T7 Shield. 2 of 4 files were copied; 2 were not.');
  assert.deepEqual(f.rows, [
    { name: 'IMG_2039.jpg', state: 'copied · 2.8 MB', stopped: false },
    { name: 'IMG_2040.jpg', state: 'copied · 3.0 MB', stopped: false },
    { name: 'IMG_2041.jpg', state: 'stopped · partial removed', stopped: true },
    { name: 'diagram v2.png', state: 'not started · 412 KB', stopped: false },
  ]);
  assert.equal(f.foot, 'Nothing half-written is left: the partial IMG_2041.jpg was deleted, and the 2 copied files are whole.');
  assert.equal(f.keys, 'r retry · s skip this file · esc cancel the rest');
  const inFolder = F.failText('caps', Object.assign({}, op, { items: [{ name: 'photos', dir: true }], failed: { index: 0, file: '/h/photos/b.jpg', error: 'Permission denied', copied: [], pending: [] } }));
  assert.equal(inFolder.foot, 'Nothing half-written is left: the partial b.jpg was deleted, and the 0 copied files are whole.');
  const b = F.failText('bracket', Object.assign({}, op, { failed: { index: 0, error: 'Permission denied', copied: [], pending: [1, 2, 3] } }));
  assert.equal(b.title, 'PERMISSION DENIED');
  assert.equal(b.rows[0].state, 'STOPPED · PARTIAL REMOVED');
  assert.equal(b.keys, '[R] RETRY · [S] SKIP THIS FILE · [ESC] CANCEL THE REST');
});

test('a stopped copy says so on the status line', () => {
  assert.deepEqual(F.stoppedText('caps', 'T7 Shield', 2, 4), { counts: 'copy to T7 Shield stopped', at: '2 of 4 copied' });
  assert.deepEqual(F.stoppedText('bracket', 'T7 Shield', 2, 4), { counts: 'COPY TO T7 SHIELD STOPPED', at: '2 OF 4 COPIED' });
});

test('a path is written from ~ inside the home folder', () => {
  assert.equal(F.tilde('/home/s', '/home/s/Downloads/IMG_2041.jpg'), '~/Downloads/IMG_2041.jpg');
  assert.equal(F.tilde('/home/s', '/home/s'), '~');
  assert.equal(F.tilde('/home/s', '/home/sam/x'), '/home/sam/x');
});

test('the key strip pairs each key with its word in the theme\'s idiom', () => {
  const paper = F.keyStrip('caps');
  assert.deepEqual(paper[0], { key: 'j/k', word: 'move' });
  assert.deepEqual(F.keyStrip('bracket')[0], { key: '[J/K]', word: 'MOVE' });
  assert.deepEqual(paper.map((k) => k.key), ['j/k', 'h/l', 'space', 'y x p', 'r', 'a', 'd', 'o', 's', 'e', '/', 'tab', 'esc']);
});

test('a drag offers the marked rows when it starts on one, else only the row it starts on', () => {
  const rows = [{ name: 'a.jpg', dir: false }, { name: 'b c#é.jpg', dir: false }, { name: 'd.jpg', dir: false }];
  assert.deepEqual(F.dragPaths(rows, ['d.jpg', 'a.jpg'], '/h/D', rows[2]), ['/h/D/a.jpg', '/h/D/d.jpg']);
  assert.deepEqual(F.dragPaths(rows, ['d.jpg'], '/h/D', rows[1]), ['/h/D/b c#é.jpg']);
});

test('a drag offers its files as text/uri-list, each URI encoded and ended by CRLF', () => {
  assert.equal(F.uriList(['/h/D/a.jpg', '/h/D/b c#é.jpg']), 'file:///h/D/a.jpg\r\nfile:///h/D/b%20c%23%C3%A9.jpg\r\n');
});

test('the drag chip counts the files, and the status line says what is dragged', () => {
  assert.equal(F.chipText('caps', 3), '3 files');
  assert.equal(F.chipText('plain', 1), '1 file');
  assert.equal(F.chipText('bracket', 3), '3 FILES');
  const rows = [{ name: 'a', dir: false, size: 4400000 }, { name: 'b', dir: false, size: 4500000 }];
  assert.deepEqual(F.dragText('caps', rows.map((r) => r)), { counts: '2 marked · 8.9 MB', at: 'dragging' });
  assert.deepEqual(F.dragText('bracket', rows), { counts: '2 MARKED · 8.9 MB', at: 'DRAGGING' });
});

test('while dragging, the key strip says where a drop goes', () => {
  assert.deepEqual(F.dragKeys('caps').map((k) => k.key), ['space', 'drag', 'e', 'esc']);
  assert.deepEqual(F.dragKeys('caps')[1], { key: 'drag', word: 'drop on a window or a folder row' });
  assert.deepEqual(F.dragKeys('bracket')[1], { key: '[DRAG]', word: 'DROP ON A WINDOW OR A FOLDER ROW' });
});

test('share names the files to send and their size, in each theme\'s voice', () => {
  assert.deepEqual(F.shareHead('caps', 3, 8900000), { label: 'SHARE', count: '3 files · 8.9 MB', tag: 'tailnet' });
  assert.deepEqual(F.shareHead('plain', 1, 2000), { label: 'Share', count: '1 file · 2 KB', tag: 'tailnet' });
  assert.deepEqual(F.shareHead('bracket', 3, 8900000), { label: 'SHARE', count: '3 FILES · 8.9 MB', tag: 'TAILNET' });
});

test('share counts the marked files and their bytes, or the cursor file when none is marked', () => {
  const rows = [{ name: 'a.txt', size: 1000 }, { name: 'b.txt', size: 2000 }, { name: 'c.txt', size: 4000 }];
  assert.deepEqual(F.shareSet(rows, ['c.txt', 'a.txt'], '/h', rows[1]), { paths: ['/h/a.txt', '/h/c.txt'], bytes: 5000 });
  assert.deepEqual(F.shareSet(rows, [], '/h', rows[1]), { paths: ['/h/b.txt'], bytes: 2000 });
  assert.deepEqual(F.shareSet([], [], '/h', null), { paths: [], bytes: 0 });
});

test('a device row reads its name on one line, its address when online and when it was seen when offline', () => {
  const on = { name: 'iPhone', ip: '100.95.3.21', online: true, age: '' };
  const off = { name: 'fed\nora‮', ip: '', online: false, age: '55d' };
  assert.deepEqual(F.shareRow('caps', on), { name: 'iPhone', detail: '100.95.3.21', status: 'online' });
  assert.deepEqual(F.shareRow('plain', off), { name: 'fed ora', detail: 'offline, seen 55d ago', status: 'offline' });
  assert.deepEqual(F.shareRow('bracket', off), { name: 'fed ora', detail: 'OFFLINE, SEEN 55D AGO', status: 'OFFLINE' });
  assert.deepEqual(F.shareRow('caps', { name: 'mini', ip: '', online: false, age: '' }), { name: 'mini', detail: 'offline', status: 'offline' });
});

test('open with names how many files of which type and how many apps, Blueprint in caps', () => {
  assert.deepEqual(F.openWithHead('caps', 3, 'JPEG image', 3), { title: '3 JPEG images', count: '3 apps' });
  assert.deepEqual(F.openWithHead('bracket', 3, 'JPEG image', 3), { title: '3 JPEG IMAGES', count: '3 APPS' });
  assert.deepEqual(F.openWithHead('plain', 1, 'PDF document', 1), { title: '1 PDF document', count: '1 app' });
  assert.deepEqual(F.openWithHead('plain', 2, null, 0), { title: '2 files', count: '0 apps' });
});

test('an app row is its name, its kind and command, and the default\'s badge in the theme\'s idiom', () => {
  const imv = { id: 'imv.desktop', name: 'imv', generic: 'Image viewer', exec: 'imv', default: true };
  assert.deepEqual(F.appText('caps', imv), { name: 'imv', sub: 'Image viewer · imv', badge: 'default' });
  assert.deepEqual(F.appText('plain', imv), { name: 'imv', sub: 'Image viewer · imv', badge: 'default' });
  assert.deepEqual(F.appText('bracket', imv), { name: 'imv', sub: 'IMAGE VIEWER · imv', badge: '[DEFAULT]' });
  assert.deepEqual(F.appText('caps', { name: 'Zathura', generic: null, exec: 'zathura', default: false }), { name: 'Zathura', sub: 'zathura', badge: '' });
});

test('an app name or kind with a newline or U+202E is one plain line', () => {
  assert.deepEqual(F.appText('plain', { name: 'bad\nname‮x', generic: 'a\nb', exec: 'v', default: false }), { name: 'bad namex', sub: 'a b · v', badge: '' });
});

test('the drives are the mounts under /run/media/<user>, each with its label, else its folder, and its size', () => {
  const findmnt = JSON.stringify({
    filesystems: [
      { target: '/', label: 'fedora', size: 172457197568 },
      { target: '/run/media/saiful/TESTUSB', label: 'TESTUSB', size: 20912128 },
      { target: '/run/media/saiful/4A1F-09C2', label: null, size: 1000204886016 },
      { target: '/run/media/saiful/evil', label: 'T7\nShield‮', size: 512 },
      { target: '/run/media/saiful2/X', label: 'X', size: 1 },
    ],
  });
  assert.deepEqual(F.drives('caps', findmnt, 'saiful'), [
    { label: 'TESTUSB', path: '/run/media/saiful/TESTUSB', size: '21 MB', group: 'drives' },
    { label: '4A1F-09C2', path: '/run/media/saiful/4A1F-09C2', size: '1000 GB', group: 'drives' },
    { label: 'T7 Shield', path: '/run/media/saiful/evil', size: '512 B', group: 'drives' },
  ]);
  assert.deepEqual(F.drives('caps', 'not json', 'saiful'), []);
});

test('the drives head and the eject badge in each theme', () => {
  assert.deepEqual(F.driveText('caps'), { head: 'DRIVES', badge: 'e' });
  assert.deepEqual(F.driveText('plain'), { head: 'Drives', badge: 'e' });
  assert.deepEqual(F.driveText('bracket'), { head: 'DRIVES', badge: 'E' });
});

test('a row draws the boards\' folder or page icon; an image is a page too, as every board draws diagram-v2.png', () => {
  assert.equal(F.rowIcon({ name: 'screenshots', dir: true }), 'folder');
  assert.equal(F.rowIcon({ name: 'IMG_2041.jpg', dir: false, mime: 'image/jpeg' }), 'file');
});

test('each place draws its own icon: the five places, a pin, a drive and Trash', () => {
  const kinds = F.places('/home/s')
    .map((p) => Object.assign({ group: 'places' }, p))
    .concat([{ label: 'lareys', group: 'pinned' }, { label: 'T7', group: 'drives' }, { label: 'Trash', group: 'trash' }])
    .map(F.placeIcon);
  assert.deepEqual(kinds, ['home', 'download', 'code', 'picture', 'document', 'bookmark', 'drive', 'trash']);
});

test('the icons are the boards\' own paths: Paper and Blueprint share a set, Artboard rounds its own', () => {
  assert.equal(F.iconPath('caps', 'folder'), 'M1.8 4.2h4l1.4 1.6h7v6.6H1.8z');
  assert.equal(F.iconPath('bracket', 'download'), 'M8 2.5v8M4.8 7.5L8 10.7l3.2-3.2M3 13.5h10');
  assert.equal(F.iconPath('plain', 'folder'), 'M2 4.5A1.5 1.5 0 0 1 3.5 3H6l1.5 1.8h5A1.5 1.5 0 0 1 14 6.3v5.2a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 11.5z');
  assert.equal(F.iconPath('plain', 'bookmark'), 'M9.6 2l4.4 4.4-2.2.5-2.1 2.9.2 2.2L8.2 11 4 14.2 5 10 3 7.8l2.2.2L8.1 5.9z');
  assert.equal(F.iconPath('caps', 'tick'), 'M3.5 8.5l3 3 6-7');
  assert.equal(F.iconPath('plain', 'tick'), 'M1.5 4.6l2 2L7.5 2.4');
});

test('the path line splits into the muted lead and the folder\'s own name', () => {
  assert.deepEqual(F.pathParts('/home/s', '/home/s/Downloads'), { lead: '~/', name: 'Downloads' });
  assert.deepEqual(F.pathParts('/home/s', '/home/s/Downloads/screenshots'), { lead: '~/Downloads/', name: 'screenshots' });
  assert.deepEqual(F.pathParts('/home/s', '/home/s'), { lead: '', name: '~' });
  assert.deepEqual(F.pathParts('/home/s', '/'), { lead: '', name: '/' });
  assert.deepEqual(F.pathParts('/home/s', '/etc'), { lead: '/', name: 'etc' });
  assert.deepEqual(F.pathParts('/home/s', '/home/s/a\nb‮c'), { lead: '~/', name: 'a bc' });
});

test('each theme\'s listing as its board draws it: marks, row height, the date\'s face and the key strip', () => {
  const caps = F.filesLook('caps');
  assert.deepEqual([caps.mark, caps.row, caps.date, caps.strip], ['box', 32, { face: 'display', italic: true, size: 17 }, { caps: true, size: 10, spacing: 1, keyWeight: 700, chip: false }]);
  const plain = F.filesLook('plain');
  assert.deepEqual([plain.mark, plain.row, plain.tile, plain.date.italic, plain.strip.chip, plain.head], ['circle', 38, true, false, true, { face: 'ui', size: 14, weight: 700 }]);
  const bracket = F.filesLook('bracket');
  assert.deepEqual([bracket.mark, bracket.date.face, bracket.strip.keyWeight, bracket.head], ['bracket', 'mono', 700, { face: 'mono', size: 12, weight: 700 }]);
});

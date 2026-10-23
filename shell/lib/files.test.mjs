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
});

test('the path line shows the find query in place of the counts while one is typed', () => {
  assert.equal(F.findText('caps', '2041'), '/ 2041');
  assert.equal(F.findText('bracket', 'a\nb'), '/ a b');
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
});

test('the prompts pair their keys as each theme writes them', () => {
  assert.equal(F.promptText('caps', [['↵', 'save'], ['esc', 'cancel']]), '↵ save · esc cancel');
  assert.equal(F.promptText('bracket', [['↵', 'save'], ['esc', 'cancel']]), '[↵] SAVE · [ESC] CANCEL');
  assert.deepEqual(F.trashAsk('caps', 2), { say: 'trash 2 files ·', keys: [{ key: '↵', word: 'trash ·' }, { key: 'esc', word: 'keep' }] });
  assert.deepEqual(F.trashAsk('bracket', 1), { say: 'TRASH 1 FILE ·', keys: [{ key: '[↵]', word: 'TRASH ·' }, { key: '[ESC]', word: 'KEEP' }] });
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

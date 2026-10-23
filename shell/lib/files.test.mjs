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

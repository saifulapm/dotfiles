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

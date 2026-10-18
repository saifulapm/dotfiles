import { test } from 'node:test';
import assert from 'node:assert/strict';
import { clipRows } from './clips.mjs';

const list = '12\tsecond\n9\t[[ binary data 12 KiB png 100x100 ]]\n4\tfirst line of first\n';
const db = '/state/dots/clips.db';

test('cliphist list lines become rows, newest first, an image as its size', () => {
  assert.deepEqual(
    clipRows(list, '', db).map((r) => [r.id, r.title]),
    [
      ['12', 'second'],
      ['9', 'image · 12 KiB'],
      ['4', 'first line of first'],
    ],
  );
});

test('the query keeps matching clips in their order, ignoring case', () => {
  assert.deepEqual(clipRows(list, 'FIRST', db).map((r) => r.title), ['first line of first']);
  assert.deepEqual(clipRows('', '', db), []);
});

test('Enter on a text clip copies it, then types it; the db and id travel as argv', () => {
  assert.deepEqual(clipRows(list, '', db)[0].exec, [
    'sh',
    '-c',
    't=$(cliphist -db-path "$1" decode "$2"); cliphist -db-path "$1" decode "$2" | wl-copy; sleep 0.1; wtype -- "$t"',
    'sh',
    db,
    '12',
  ]);
});

test('Enter on an image clip only copies it', () => {
  assert.deepEqual(clipRows(list, '', db)[1].exec, ['sh', '-c', 'cliphist -db-path "$1" decode "$2" | wl-copy', 'sh', db, '9']);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { clipRows, TERMINALS } from './clips.mjs';

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

test('Enter copies a clip, then presses the paste key of the window it came from; the db, id and terminals travel as argv', () => {
  for (const i of [0, 1]) {
    const exec = clipRows(list, '', db)[i].exec;
    assert.deepEqual(exec.slice(0, 2), ['sh', '-c']);
    assert.deepEqual(exec.slice(3), ['sh', db, i === 0 ? '12' : '9', TERMINALS.join(' ')]);
    assert.match(exec[2], /decode "\$2" \| wl-copy/);
    assert.doesNotMatch(exec[2], /wtype -- /);
  }
});

test('Shift+Enter only copies: the clip is decoded into wl-copy, no key is pressed, and the db and id travel as argv', () => {
  for (const i of [0, 1]) {
    const copy = clipRows(list, '', db)[i].copyExec;
    assert.deepEqual(copy.slice(0, 2), ['sh', '-c']);
    assert.deepEqual(copy.slice(3), ['sh', db, i === 0 ? '12' : '9']);
    assert.match(copy[2], /decode "\$2" \| wl-copy/);
    assert.doesNotMatch(copy[2], /wtype/);
  }
});

test('a terminal pastes on Ctrl+Shift+V and every other window on Ctrl+V', () => {
  const script = clipRows(list, '', db)[0].exec[2];
  assert.match(script, /wtype -M ctrl -M shift -k v -m shift -m ctrl/);
  assert.match(script, /wtype -M ctrl -k v -m ctrl/);
  assert.ok(TERMINALS.includes('foot'));
});

test('each clip carries a glyph for its type: ¶ for text, ◫ for an image', () => {
  assert.deepEqual(clipRows(list, '', db).map((r) => r.glyph), ['¶', '◫', '¶']);
});

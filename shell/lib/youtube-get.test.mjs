import { test } from 'node:test';
import assert from 'node:assert/strict';
import { downloaded, failedOf, index, playFiles, stdinLines } from './youtube-get.mjs';

const video = (id, extra = {}) => Object.assign({ id, kind: 'video', title: `Title ${id}`, channel: 'c', duration: '1:00', secs: 60, thumb: id }, extra);

test('index reads files and failures, and anything else as empty', () => {
  const text = JSON.stringify({ files: { abcdefghijk: { audio: '/m/a.opus' }, bad: 3 }, failed: { zyxwvutsrqp: { kind: 'video', title: 'T', reason: 'HTTP 403' } } });
  assert.deepEqual(index(text), { files: { abcdefghijk: { audio: '/m/a.opus' } }, failed: { zyxwvutsrqp: { kind: 'video', title: 'T', reason: 'HTTP 403' } } });
  for (const broken of ['', 'not json', '[]', 'null', '{"files": 1, "failed": []}']) assert.deepEqual(index(broken), { files: {}, failed: {} });
});

test('a row is downloaded when the index holds a file of either kind for its id', () => {
  const i = index(JSON.stringify({ files: { abcdefghijk: { audio: '/m/a.opus' }, bbbbbbbbbbb: { video: '/v/b.webm' }, ccccccccccc: {} } }));
  assert.equal(downloaded(i, 'abcdefghijk'), true);
  assert.equal(downloaded(i, 'bbbbbbbbbbb'), true);
  assert.equal(downloaded(i, 'ccccccccccc'), false);
  assert.equal(downloaded(i, 'ddddddddddd'), false);
});

test("a row's failure is its kind and reason drawn as one line, or null", () => {
  const i = index(JSON.stringify({ failed: { abcdefghijk: { kind: 'audio', title: 'T', reason: 'HTTP\n403‮' }, bbbbbbbbbbb: { kind: 'sideways', reason: 'x' } } }));
  assert.deepEqual(failedOf(i, 'abcdefghijk'), { kind: 'audio', reason: 'HTTP 403' });
  assert.equal(failedOf(i, 'bbbbbbbbbbb'), null);
  assert.equal(failedOf(i, 'ccccccccccc'), null);
});

test('stdinLines gives one JSON line per playable video, unavailable ones and playlists left out', () => {
  const rows = [video('aaaaaaaaaaa'), video('bbbbbbbbbbb', { unavailable: 'Private video' }), { id: 'PLx', kind: 'playlist', title: 'P' }, video('ccccccccccc', { title: 'a = b\nc' })];
  const lines = stdinLines(rows).split('\n');
  assert.equal(lines.length, 3);
  assert.equal(lines[2], '');
  assert.deepEqual(JSON.parse(lines[0]), { id: 'aaaaaaaaaaa', title: 'Title aaaaaaaaaaa' });
  assert.deepEqual(JSON.parse(lines[1]), { id: 'ccccccccccc', title: 'a = b\nc' });
  assert.equal(stdinLines([]), '');
});

test("where's answer gives the Queue each song's audio first, else its video, and only an absolute path", () => {
  const answer = { files: { aaaaaaaaaaa: { audio: '/m/a.opus', video: '/v/a.webm' }, bbbbbbbbbbb: { video: '/v/b.webm' }, ccccccccccc: { audio: 'relative.opus' } } };
  assert.deepEqual(playFiles(answer), { aaaaaaaaaaa: '/m/a.opus', bbbbbbbbbbb: '/v/b.webm' });
  assert.deepEqual(playFiles(null), {});
});

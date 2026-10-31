import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as H from './youtube-history.mjs';
import * as Y from './youtube.mjs';

const row = (id, o) => Object.assign({ id, title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: '4:27', secs: 267, thumb: id }, o);
const vid = (n) => 'fakeVid' + String(n).padStart(4, '0');

test('add puts a row on top, with secs as its duration and the time it was played', () => {
  const h = H.add(H.add(H.empty(), row('fakeVid0001'), 1000), row('fakeVid0002'), 2000);
  assert.deepEqual(h[0], { id: 'fakeVid0002', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: 267, thumb: 'fakeVid0002', at: 2000 });
  assert.deepEqual(h.map((e) => e.id), ['fakeVid0002', 'fakeVid0001']);
});

test('a live stream row keeps a null duration', () => {
  assert.equal(H.add(H.empty(), row('fakeVid0001', { duration: '', secs: null }), 1)[0].duration, null);
});

test('replaying a video moves it to the top and leaves one entry', () => {
  let h = H.empty();
  for (const [i, id] of ['fakeVid0001', 'fakeVid0002', 'fakeVid0003'].entries()) h = H.add(h, row(id), i);
  h = H.add(h, row('fakeVid0001'), 9);
  assert.deepEqual(h.map((e) => [e.id, e.at]), [['fakeVid0001', 9], ['fakeVid0003', 2], ['fakeVid0002', 1]]);
});

test('the 201st add drops the oldest and leaves 200', () => {
  assert.equal(H.MAX, 200);
  let h = H.empty();
  for (let i = 1; i <= 201; i++) h = H.add(h, row(vid(i)), i);
  assert.equal(h.length, 200);
  assert.equal(h[0].id, vid(201));
  assert.equal(h[199].id, vid(2));
});

test('add leaves the history it was given as it was', () => {
  const h = H.add(H.empty(), row('fakeVid0001'), 1);
  H.add(h, row('fakeVid0002'), 2);
  assert.equal(h.length, 1);
});

test('a file that holds a video twice reads with the newest one', () => {
  const e = (id, at) => ({ id, title: 't', channel: 'c', duration: 1, thumb: id, at });
  const h = H.parse(JSON.stringify([e('fakeVid0001', 5), e('fakeVid0002', 4), e('fakeVid0001', 3)]));
  assert.deepEqual(h.map((x) => [x.id, x.at]), [['fakeVid0001', 5], ['fakeVid0002', 4]]);
});

test('parse drops entries with a bad id and keeps the rest', () => {
  const ok = { id: 'fakeVid0001', title: 't', channel: 'c', duration: null, thumb: '', at: 1 };
  const h = H.parse(JSON.stringify([Object.assign({}, ok, { id: '../etc' }), ok, 'x', null]));
  assert.deepEqual(h, [ok]);
});

// A history that cannot be read must never be saved over, or one bad read would lose it all.
test('no file reads as empty; a broken or wrong-shaped one reads null', () => {
  assert.deepEqual(H.parse(''), []);
  assert.deepEqual(H.parse('  \n'), []);
  assert.equal(H.parse('[{"id":'), null);
  assert.equal(H.parse('{"entries":[]}'), null);
  assert.equal(H.parse('"x"'), null);
});

test('a history survives a write and a read, and the text ends in a newline', () => {
  const h = H.add(H.add(H.empty(), row('fakeVid0001'), 1), row('fakeVid0002', { secs: null }), 2);
  const text = H.serialize(h);
  assert.ok(text.endsWith('\n'));
  assert.deepEqual(H.parse(text), h);
});

test('rows draw like youtube.mjs rows, duration text and all', () => {
  const h = H.add(H.add(H.empty(), row('fakeVid0001', { secs: 3734 }), 1), row('fakeVid0002', { secs: null }), 2);
  assert.deepEqual(H.rows(h), [
    { id: 'fakeVid0002', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: '', secs: null, thumb: 'fakeVid0002' },
    { id: 'fakeVid0001', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: '1:02:14', secs: 3734, thumb: 'fakeVid0001' },
  ]);
  assert.deepEqual(H.rows(h), Y.rows({ rows: [{ id: 'fakeVid0002', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: null, thumb: 'fakeVid0002' }, { id: 'fakeVid0001', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: 3734, thumb: 'fakeVid0001' }] }));
});

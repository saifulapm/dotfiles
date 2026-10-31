import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as P from './youtube-playlists.mjs';

const video = (id, o) => Object.assign({ id, title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: 267, thumb: id }, o);

test('a new store holds only the fixed Playlist saved, empty', () => {
  const s = P.emptyStore();
  assert.deepEqual(Object.keys(s.playlists), ['saved']);
  assert.equal(s.playlists.saved.id, 'saved');
  assert.deepEqual(P.items(s, 'saved'), []);
});

test('s adds a video to Saved with its five fields', () => {
  const s = P.add(P.emptyStore(), 'saved', video('fakeVid0001'), 1000);
  assert.deepEqual(P.items(s, 'saved'), [video('fakeVid0001')]);
});

test('s on a video already in Saved leaves one copy', () => {
  let s = P.add(P.emptyStore(), 'saved', video('fakeVid0001'), 1000);
  s = P.add(s, 'saved', video('fakeVid0001', { title: 'renamed' }), 2000);
  assert.deepEqual(P.items(s, 'saved').map((v) => [v.id, v.title]), [['fakeVid0001', 'Aruarian Dance']]);
});

test('items keep the order they were added in', () => {
  let s = P.emptyStore();
  for (const [i, id] of ['fakeVid0003', 'fakeVid0001', 'fakeVid0002'].entries()) s = P.add(s, 'saved', video(id), 1000 + i);
  assert.deepEqual(P.items(s, 'saved').map((v) => v.id), ['fakeVid0003', 'fakeVid0001', 'fakeVid0002']);
});

test('only the five fields are kept, whatever else a row carries', () => {
  const s = P.add(P.emptyStore(), 'saved', Object.assign(video('fakeVid0001'), { secs: 1, url: 'x' }), 1000);
  assert.deepEqual(Object.keys(P.items(s, 'saved')[0]).sort(), ['channel', 'duration', 'id', 'thumb', 'title']);
});

test('the store survives a write and a read', () => {
  const s = P.add(P.emptyStore(), 'saved', video('fakeVid0001'), 1000);
  assert.deepEqual(P.items(P.parse(P.serialize(s)), 'saved'), [video('fakeVid0001')]);
});

// A store that cannot be read must never be saved over, or one bad read would lose every Playlist.
test('no file reads as a new store; a broken or wrong-shaped one reads null', () => {
  assert.deepEqual(P.parse(''), P.emptyStore());
  assert.equal(P.parse('{"playlists":'), null);
  assert.equal(P.parse('[]'), null);
  assert.equal(P.parse('{"playlists":[]}'), null);
});

test('a store whose file lost saved gets it back', () => {
  assert.deepEqual(P.items(P.parse('{"version":1,"playlists":{}}'), 'saved'), []);
});

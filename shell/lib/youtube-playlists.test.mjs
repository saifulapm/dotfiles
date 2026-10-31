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

// A file another machine wrote reaches the merge through parse, so a Playlist or item of the wrong shape must not get past it.
test('a store with a Playlist or an item of the wrong shape reads null', () => {
  for (const bad of [{ x: 'str' }, { x: null }, { x: { id: 'x', name: 'X', items: null } }, { x: { id: 'x', name: 'X', items: [] } }, { x: { id: 'x', name: 5, items: {} } }, { x: { id: 'x', name: 'X', items: { v: null } } }, { x: { id: 'x', name: 'X', items: { v: 'v' } } }]) {
    assert.equal(P.parse(JSON.stringify({ version: 1, playlists: bad })), null, JSON.stringify(bad));
  }
});

test('a store whose file lost saved gets it back', () => {
  assert.deepEqual(P.items(P.parse('{"version":1,"playlists":{}}'), 'saved'), []);
});

const ids = (s, p) => P.items(s, p).map((v) => v.id);
const filled = (n, p = 'saved') => {
  let s = P.emptyStore();
  for (let i = 1; i <= n; i++) s = P.add(s, p, video('fakeVid000' + i), 1000 + i);
  return s;
};

test('a new Playlist is listed with no videos', () => {
  const s = P.create(P.emptyStore(), 'pl1', '  Study  ', 1000);
  assert.deepEqual(P.playlists(s), [{ id: 'pl1', name: 'Study', count: 0, secs: 0 }]);
  assert.deepEqual(s.playlists.pl1, { id: 'pl1', name: 'Study', createdAt: 1000, updatedAt: 1000, deleted: false, items: {} });
});

test('two Playlists may share a name, oldest first', () => {
  let s = P.create(P.emptyStore(), 'b', 'Mix', 2000);
  s = P.create(s, 'a', 'Mix', 3000);
  assert.deepEqual(P.playlists(s).map((p) => p.id), ['b', 'a']);
});

test('create refuses a blank name, saved, or an id already there', () => {
  const s = P.create(P.emptyStore(), 'pl1', 'Study', 1000);
  assert.equal(P.create(s, 'pl2', '   ', 2000), s);
  assert.equal(P.create(s, 'saved', 'X', 2000), s);
  assert.equal(P.create(s, 'pl1', 'Other', 2000), s);
});

test('rename changes the name and stamps it; saved, blank, deleted or missing stay', () => {
  const s = P.create(P.emptyStore(), 'pl1', 'Study', 1000);
  const r = P.rename(s, 'pl1', ' Focus ', 2000);
  assert.equal(r.playlists.pl1.name, 'Focus');
  assert.equal(r.playlists.pl1.updatedAt, 2000);
  assert.equal(P.rename(s, 'saved', 'X', 2000), s);
  assert.equal(P.rename(s, 'pl1', ' ', 2000), s);
  assert.equal(P.rename(s, 'nope', 'X', 2000), s);
  const gone = P.remove(s, 'pl1', 2000);
  assert.equal(P.rename(gone, 'pl1', 'X', 3000), gone);
});

test('remove hides a Playlist but keeps a tombstone; saved stays', () => {
  const s = P.remove(P.create(P.emptyStore(), 'pl1', 'Study', 1000), 'pl1', 2000);
  assert.deepEqual(P.playlists(s), []);
  assert.equal(s.playlists.pl1.deleted, true);
  assert.equal(s.playlists.pl1.updatedAt, 2000);
  const e = P.emptyStore();
  assert.equal(P.remove(e, 'saved', 2000), e);
});

test('add to a deleted Playlist changes nothing', () => {
  const s = P.remove(P.create(P.emptyStore(), 'pl1', 'Study', 1000), 'pl1', 2000);
  assert.equal(P.add(s, 'pl1', video('fakeVid0001'), 3000), s);
});

test('an added item carries addedAt, deleted false, and unavailable only when set', () => {
  let s = P.add(P.emptyStore(), 'saved', video('fakeVid0001'), 1000);
  s = P.add(s, 'saved', video('fakeVid0002', { unavailable: 'made private' }), 1001);
  const it = s.playlists.saved.items;
  assert.equal(it.fakeVid0001.addedAt, 1000);
  assert.equal(it.fakeVid0001.deleted, false);
  assert.equal('unavailable' in it.fakeVid0001, false);
  assert.equal(P.items(s, 'saved')[1].unavailable, 'made private');
});

test('removeItem drops the count by one and keeps a tombstone', () => {
  let s = P.create(P.emptyStore(), 'pl1', 'Study', 1000);
  s = P.add(P.add(s, 'pl1', video('fakeVid0001'), 1001), 'pl1', video('fakeVid0002'), 1002);
  s = P.removeItem(s, 'pl1', 'fakeVid0001', 2000);
  assert.equal(P.playlists(s)[0].count, 1);
  assert.deepEqual(ids(s, 'pl1'), ['fakeVid0002']);
  assert.equal(s.playlists.pl1.items.fakeVid0001.deleted, true);
  assert.equal(s.playlists.pl1.items.fakeVid0001.updatedAt, 2000);
});

test('a video added again after removal returns at the end, not deleted', () => {
  let s = filled(2);
  s = P.removeItem(s, 'saved', 'fakeVid0001', 2000);
  s = P.add(s, 'saved', video('fakeVid0001'), 3000);
  assert.deepEqual(ids(s, 'saved'), ['fakeVid0002', 'fakeVid0001']);
  assert.equal(s.playlists.saved.items.fakeVid0001.deleted, false);
});

test('holds is true only for a live item', () => {
  let s = filled(1);
  assert.equal(P.holds(s, 'saved', 'fakeVid0001'), true);
  assert.equal(P.holds(s, 'saved', 'fakeVid0009'), false);
  assert.equal(P.holds(s, 'nope', 'fakeVid0001'), false);
  s = P.removeItem(s, 'saved', 'fakeVid0001', 2000);
  assert.equal(P.holds(s, 'saved', 'fakeVid0001'), false);
});

test('playlists sums live counts and numeric durations', () => {
  let s = P.create(P.emptyStore(), 'pl1', 'Study', 1000);
  s = P.addMany(s, 'pl1', [video('fakeVid0001', { duration: 100 }), video('fakeVid0002', { duration: null }), video('fakeVid0003', { duration: 20 })], 1001);
  assert.deepEqual(P.playlists(s), [{ id: 'pl1', name: 'Study', count: 3, secs: 120 }]);
});

test('move +1 on the first item makes it second, and the order survives a write', () => {
  const s = P.move(filled(3), 'saved', 'fakeVid0001', 1, 2000);
  assert.deepEqual(ids(s, 'saved'), ['fakeVid0002', 'fakeVid0001', 'fakeVid0003']);
  assert.deepEqual(ids(P.parse(P.serialize(s)), 'saved'), ['fakeVid0002', 'fakeVid0001', 'fakeVid0003']);
  assert.equal(s.playlists.saved.items.fakeVid0001.pos, 2.5);
  assert.equal(s.playlists.saved.items.fakeVid0001.updatedAt, 2000);
  assert.equal(s.playlists.saved.items.fakeVid0002.updatedAt, 1002);
});

test('move -1 puts an item before its neighbour; past the last, plus one', () => {
  const s = P.move(filled(3), 'saved', 'fakeVid0003', -1, 2000);
  assert.deepEqual(ids(s, 'saved'), ['fakeVid0001', 'fakeVid0003', 'fakeVid0002']);
  const t = P.move(filled(2), 'saved', 'fakeVid0001', 1, 2000);
  assert.equal(t.playlists.saved.items.fakeVid0001.pos, 3);
});

test('move off either end returns the same store', () => {
  const s = filled(3);
  assert.equal(P.move(s, 'saved', 'fakeVid0001', -1, 2000), s);
  assert.equal(P.move(s, 'saved', 'fakeVid0003', 1, 2000), s);
});

test('move steps over tombstones', () => {
  let s = P.removeItem(filled(3), 'saved', 'fakeVid0002', 1500);
  s = P.move(s, 'saved', 'fakeVid0001', 1, 2000);
  assert.deepEqual(ids(s, 'saved'), ['fakeVid0003', 'fakeVid0001']);
});

test('addMany keeps the given order, skips repeats and videos already there', () => {
  let s = filled(1);
  s = P.addMany(s, 'saved', [video('fakeVid0003'), video('fakeVid0001'), video('fakeVid0002'), video('fakeVid0003')], 2000);
  assert.deepEqual(ids(s, 'saved'), ['fakeVid0001', 'fakeVid0003', 'fakeVid0002']);
});

test('addMany of 300 keeps the order and 5000 runs well under a second', () => {
  const vs = (n) => Array.from({ length: n }, (_, i) => video('v' + String(i).padStart(5, '0')));
  const s = P.addMany(P.emptyStore(), 'saved', vs(300), 1000);
  assert.deepEqual(ids(s, 'saved'), vs(300).map((v) => v.id));
  const t0 = performance.now();
  const big = P.addMany(P.emptyStore(), 'saved', vs(5000), 1000);
  assert.ok(performance.now() - t0 < 500);
  assert.equal(ids(big, 'saved').length, 5000);
});

test('addMany with nothing new returns the same store', () => {
  const s = filled(1);
  assert.equal(P.addMany(s, 'saved', [video('fakeVid0001')], 2000), s);
});

// The file on disk before Playlists could be made has no createdAt, deleted or addedAt.
test('a store written by the old code parses and its Saved items list', () => {
  const old = '{"version":1,"playlists":{"saved":{"id":"saved","name":"Saved","updatedAt":5,"items":{"a":{"id":"a","title":"T","channel":"C","duration":9,"thumb":"a","pos":1,"updatedAt":5},"b":{"id":"b","title":"U","channel":"C","duration":9,"thumb":"b","pos":2,"updatedAt":5}}}}}';
  const s = P.parse(old);
  assert.deepEqual(ids(s, 'saved'), ['a', 'b']);
  assert.equal(P.holds(s, 'saved', 'a'), true);
  assert.deepEqual(ids(P.move(s, 'saved', 'a', 1, 9), 'saved'), ['b', 'a']);
});

// Two machines that last synced on base each edit, then each merges the other's file: both must end the same.
const both = (a, b) => {
  const ab = P.mergeStores(a, b);
  const ba = P.mergeStores(b, a);
  assert.deepEqual(P.playlists(ab), P.playlists(ba));
  for (const id of Object.keys(ab.playlists)) assert.deepEqual(ids(ab, id), ids(ba, id));
  return ab;
};
const focus = () => {
  let s = P.create(P.emptyStore(), 'focus', 'Focus', 100);
  s = P.addMany(s, 'focus', ['v1', 'v2', 'v3', 'v4'].map((id) => video(id)), 100);
  return P.create(s, 'gym', 'Gym', 101);
};

test('a video added on one machine and another removed on a second both survive the merge', () => {
  const base = focus();
  const a = P.add(base, 'focus', video('x'), 1000);
  const b = P.removeItem(base, 'focus', 'v2', 1001);
  const m = both(a, b);
  assert.deepEqual(ids(m, 'focus'), ['v1', 'v3', 'v4', 'x']);
  // A second round, each merging the result, changes nothing.
  assert.deepEqual(P.mergeStores(m, a), m);
  assert.deepEqual(P.mergeStores(m, b), m);
});

test('a move merges by last write: the later of two moves of one video wins on both', () => {
  const base = focus();
  const a = P.move(base, 'focus', 'v3', -1, 1000);
  const b = P.move(base, 'focus', 'v3', 1, 1001);
  assert.deepEqual(ids(a, 'focus'), ['v1', 'v3', 'v2', 'v4']);
  assert.deepEqual(ids(both(a, b), 'focus'), ['v1', 'v2', 'v4', 'v3']);
});

test('a name merges by last write, even when the other machine changed the Playlist later', () => {
  const base = focus();
  const b = P.add(P.rename(base, 'focus', 'Work', 1000), 'focus', video('y'), 3000);
  const a = P.rename(base, 'focus', 'Deep focus', 2000);
  const m = both(a, b);
  assert.deepEqual(P.playlists(m).map((l) => l.name), ['Deep focus', 'Gym']);
  assert.deepEqual(ids(m, 'focus'), ['v1', 'v2', 'v3', 'v4', 'y']);
});

test('a Playlist deleted on one machine stays gone though the other added to it or renamed it later', () => {
  const base = focus();
  const a = P.remove(base, 'gym', 1000);
  const b = P.rename(P.add(base, 'gym', video('z'), 2000), 'gym', 'Lifting', 2001);
  assert.deepEqual(P.playlists(both(a, b)).map((l) => l.name), ['Focus']);
});

test('the same video added on two machines in one round is one item, and items at one position list alike on both', () => {
  const base = focus();
  const a = P.add(P.add(base, 'focus', video('x'), 1000), 'focus', video('p'), 1002);
  const b = P.add(P.add(base, 'focus', video('q'), 1001), 'focus', video('x'), 1003);
  const m = both(a, b);
  assert.deepEqual(ids(m, 'focus').filter((id) => id === 'x'), ['x']);
  assert.equal(ids(m, 'focus').length, 7);
});

test('a video removed on one machine and added again later on another comes back', () => {
  const base = focus();
  const a = P.removeItem(base, 'focus', 'v1', 1000);
  const b = P.add(P.removeItem(base, 'focus', 'v1', 900), 'focus', video('v1'), 2000);
  assert.deepEqual(ids(both(a, b), 'focus'), ['v2', 'v3', 'v4', 'v1']);
});

test('Saved is never deleted or renamed by a merge', () => {
  const forged = JSON.parse(JSON.stringify(focus()));
  Object.assign(forged.playlists.saved, { name: 'Mine', nameAt: 9e12, deleted: true, updatedAt: 9e12 });
  for (const m of [P.mergeStores(focus(), forged), P.mergeStores(forged, focus())]) {
    assert.equal(m.playlists.saved.name, 'Saved');
    assert.notEqual(m.playlists.saved.deleted, true);
  }
});

test('merging a store with itself leaves its file byte for byte unchanged', () => {
  let s = P.removeItem(P.remove(focus(), 'gym', 200), 'focus', 'v2', 201);
  s = P.rename(P.add(s, 'saved', video('s1'), 202), 'focus', 'Deep focus', 203);
  const text = P.serialize(s);
  assert.equal(P.serialize(P.mergeStores(P.parseStore(text), P.parseStore(text))), text);
});

test('a store written by the old code merges with a new one without losing an item', () => {
  const old = P.parse('{"version":1,"playlists":{"saved":{"id":"saved","name":"Saved","updatedAt":5,"items":{"a":{"id":"a","title":"T","channel":"C","duration":9,"thumb":"a","pos":1,"updatedAt":5},"b":{"id":"b","title":"U","channel":"C","duration":9,"thumb":"b","updatedAt":5}}}}}');
  const m = both(old, focus());
  assert.deepEqual(ids(m, 'saved'), ['b', 'a']);
  assert.deepEqual(P.playlists(m).map((l) => l.name), ['Focus', 'Gym']);
  assert.equal(P.serialize(P.mergeStores(old, old)), P.serialize(old));
});

test('after two machines add at one position, a move still moves the video one step each time', () => {
  const base = P.addMany(P.create(P.emptyStore(), 'focus', 'Focus', 100), 'focus', [video('a1'), video('a2')], 100);
  const m = P.mergeStores(P.add(base, 'focus', video('p9'), 1000), P.add(base, 'focus', video('q9'), 1001));
  assert.deepEqual(ids(m, 'focus'), ['a1', 'a2', 'p9', 'q9']);
  let s = m;
  for (const want of [['a1', 'p9', 'a2', 'q9'], ['a1', 'p9', 'q9', 'a2']]) {
    s = P.move(s, 'focus', 'a2', 1, 2000);
    assert.deepEqual(ids(s, 'focus'), want);
  }
  assert.equal(P.move(s, 'focus', 'a2', 1, 2001), s);
  // Every stamp the move set travels, so the other machine ends in the same order.
  assert.deepEqual(ids(P.mergeStores(m, s), 'focus'), ['a1', 'p9', 'q9', 'a2']);
});

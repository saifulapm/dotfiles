import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as F from './youtube-find.mjs';

const video = (n) => ({ id: `fakeVid${String(n).padStart(4, '0')}`, kind: 'video', title: `Track ${n}`, channel: 'Nujabes', duration: 100 + n, thumb: `fakeVid${String(n).padStart(4, '0')}` });
const answer = (from, to, next) => ({ rows: Array.from({ length: to - from + 1 }, (_, i) => video(from + i)), next });

test('a YouTube URL is a link to open, with or without its scheme', () => {
  for (const url of ['https://www.youtube.com/watch?v=hQ5x8pHoIPA', 'https://youtu.be/hQ5x8pHoIPA', 'https://music.youtube.com/watch?v=hQ5x8pHoIPA', 'http://m.youtube.com/@Nujabes19740207', 'youtube.com/playlist?list=PLfFNYT1NiTNTj04xlfqK8zZUp8sC2ZOAO', '  https://www.youtube.com/channel/UCO5XcuQe_fLJVI3sZ0LmGCA  '])
    assert.equal(F.isLink(url), true, url);
});

test('another site, a query that names YouTube, or text with spaces is searched as text', () => {
  for (const text of ['https://vimeo.com/123', 'https://notyoutube.com/watch?v=hQ5x8pHoIPA', 'https://youtube.com.evil.net/watch', 'youtube.com tutorial', 'nujabes', 'youtube', ''])
    assert.equal(F.isLink(text), false, text);
});

test('a first page lists its rows, a repeat within it dropped, and says a full page may have more', () => {
  const a = answer(1, 20, 20);
  a.rows[19] = video(3);
  const l = F.page(a);
  assert.equal(l.rows.length, 19);
  assert.deepEqual(l.rows.slice(-2).map((r) => r.id), ['fakeVid0018', 'fakeVid0019']);
  assert.deepEqual([l.next, l.more, l.loading], [20, true, false]);
});

test('a page of fewer than 20 rows has no more to ask for', () => {
  const l = F.page(answer(1, 7, 7));
  assert.equal(l.more, false);
  assert.equal(F.wants(l, 6), false);
});

test('the cursor on any of the last 5 rows wants the next page, once while it loads', () => {
  const l = F.page(answer(1, 20, 20));
  assert.deepEqual([13, 14, 15, 16, 19].map((c) => F.wants(l, c)), [false, false, true, true, true]);
  const asked = F.asking(l);
  assert.equal(asked.loading, true);
  assert.equal(F.wants(asked, 16), false, 'no second request for offset 20 while the first runs');
  assert.equal(F.wants(asked, 19), false);
});

test('the next page appends below, keeping the rows on screen in order and dropping a video already listed', () => {
  const first = F.asking(F.page(answer(1, 20, 20)));
  const second = answer(21, 40, 40);
  second.rows[2] = video(7);
  const l = F.append(first, second);
  assert.equal(l.rows.length, 39);
  assert.deepEqual(l.rows.slice(0, 20), first.rows);
  assert.equal(l.rows.filter((r) => r.id === 'fakeVid0007').length, 1);
  assert.deepEqual([l.next, l.more, l.loading], [40, true, false]);
});

test('a short last page ends the list, and a failed page lets the next move ask again', () => {
  const two = F.append(F.asking(F.page(answer(1, 20, 20))), answer(21, 25, 25));
  assert.deepEqual([two.rows.length, two.more, F.wants(two, 24)], [25, false, false]);
  const failed = F.append(F.asking(F.page(answer(1, 20, 20))), { error: 'No network. Check Wi-Fi, then ↵ to try again.', kind: 'network', raw: '' });
  assert.deepEqual([failed.rows.length, failed.next, failed.more, failed.loading], [20, 20, true, false]);
  assert.equal(F.wants(failed, 19), true);
});

const channel = { id: 'UCfakeChan00000000000001', kind: 'channel', title: 'Nujabes', channel: '@nujabes', duration: '', secs: null, thumb: '' };
const playlist = { id: 'PLfakeList0001', kind: 'playlist', title: 'Modal Soul', channel: 'Nujabes', duration: '14 videos', secs: null, thumb: 'fakeVid0001', count: 14 };

test('opening a row shows its name at once over a list that loads, and keeps the results cursor to come back to', () => {
  const o = F.opening(channel, 7);
  assert.deepEqual([o.kind, o.id, o.title, o.count, o.list.rows, o.list.loading, o.failed, o.back], ['channel', 'UCfakeChan00000000000001', 'Nujabes', null, [], true, null, 7]);
  assert.equal(F.opening(playlist, 0).count, 14);
});

test('a channel answer lists its uploads under the name YouTube gives, paging on like a search', () => {
  const o = F.opened(F.opening(channel, 0), Object.assign(answer(1, 20, 20), { title: 'Nujabes\nOfficial' }));
  assert.deepEqual([o.title, o.list.rows.length, o.list.more, o.list.loading, o.failed], ['Nujabes Official', 20, true, false, null]);
  assert.equal(F.opened(F.opening(channel, 0), answer(1, 3, 3)).title, 'Nujabes', 'no title in the answer keeps the row\'s');
});

test('a channel with no uploads lists none and is done loading', () => {
  const o = F.opened(F.opening(channel, 0), { title: null, rows: [], next: 0 });
  assert.deepEqual([o.list.rows, o.list.more, o.list.loading, o.failed], [[], false, false, null]);
});

test('a playlist answer is every item at once, under its title and count, so it asks for no next page', () => {
  const o = F.opened(F.opening(playlist, 2), Object.assign(answer(1, 20, 20), { title: 'Modal Soul', count: 300 }));
  assert.deepEqual([o.title, o.count, o.list.rows.length, o.list.more, F.wants(o.list, 19), o.back], ['Modal Soul', 300, 20, false, false, 2]);
});

test('a failed open keeps its name and holds the failure, not an empty list', () => {
  const o = F.opened(F.opening(playlist, 0), { error: 'The playlist does not exist.', kind: 'extraction', raw: 'ERROR: [youtube:tab] PLfakeList0001: YouTube said: The playlist does not exist.' });
  assert.deepEqual([o.title, o.list.loading, o.failed.error], ['Modal Soul', false, 'The playlist does not exist.']);
});

test('a playlist or channel row in a page keeps its kind', () => {
  const l = F.page({ rows: [{ id: 'UCO5XcuQe_fLJVI3sZ0LmGCA', kind: 'channel', title: 'Nujabes', channel: '@nujabes', duration: null, thumb: '' }], next: 1 });
  assert.equal(l.rows[0].kind, 'channel');
});

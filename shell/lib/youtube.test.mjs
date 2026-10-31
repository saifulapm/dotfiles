import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as Y from './youtube.mjs';

const row = (o) => Object.assign({ id: 'dQw4w9WgXcQ', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: 267, thumb: 'dQw4w9WgXcQ' }, o);

test('a search answer lists its rows as the row draws them', () => {
  assert.deepEqual(Y.rows({ rows: [row()] }), [{ id: 'dQw4w9WgXcQ', kind: 'video', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: '4:27', secs: 267, thumb: 'dQw4w9WgXcQ' }]);
});

// Saved and History keep rows from before kinds, so a row with none is a video.
test('a row with no kind is a video, and one of a kind the App does not know is dropped', () => {
  assert.equal(Y.rows({ rows: [row({ kind: 'video' })] })[0].kind, 'video');
  assert.deepEqual(Y.rows({ rows: [row({ kind: 'mix' }), row({ kind: 7 })] }), []);
});

// A playlist id is YouTube's PL, OLAK5uy_ or RD run, and a channel's is UC and 22 more; each still names no file, so only YouTube's id characters pass.
test('a playlist row keeps its id and its count, and draws its count where a video draws its duration', () => {
  const [p] = Y.rows({ rows: [{ id: 'PLfFNYT1NiTNTj04xlfqK8zZUp8sC2ZOAO', kind: 'playlist', title: 'Modal Soul', channel: 'Nujabes', duration: null, thumb: 'hQ5x8pHoIPA', count: 300 }] });
  assert.deepEqual(p, { id: 'PLfFNYT1NiTNTj04xlfqK8zZUp8sC2ZOAO', kind: 'playlist', title: 'Modal Soul', channel: 'Nujabes', duration: '300 videos', secs: null, thumb: 'hQ5x8pHoIPA', count: 300 });
  const counts = Y.rows({ rows: [1, null, 'x', 1234].map((count, i) => ({ id: 'PLfakeList000' + i, kind: 'playlist', title: 't', channel: 'c', duration: null, thumb: '', count })) });
  assert.deepEqual(counts.map((r) => [r.count, r.duration]), [[1, '1 video'], [null, ''], [null, ''], [1234, '1,234 videos']]);
  assert.deepEqual(Y.rows({ rows: [{ id: 'PL/../x', kind: 'playlist', title: 't', count: 1 }] }), []);
});

test('a channel row keeps its UC id, its handle as the channel line, and no duration', () => {
  const [c] = Y.rows({ rows: [{ id: 'UCO5XcuQe_fLJVI3sZ0LmGCA', kind: 'channel', title: 'Nujabes', channel: '@Nujabes19740207', duration: null, thumb: '' }] });
  assert.deepEqual(c, { id: 'UCO5XcuQe_fLJVI3sZ0LmGCA', kind: 'channel', title: 'Nujabes', channel: '@Nujabes19740207', duration: '', secs: null, thumb: '' });
  assert.deepEqual(Y.rows({ rows: [{ id: 'dQw4w9WgXcQ', kind: 'channel', title: 'x' }] }), [], 'a video id is no channel');
});

// Saving a row keeps its seconds, so Saved draws its duration with no network.
test('a row keeps its duration in seconds beside the drawn one, null when yt-dlp gave none', () => {
  assert.equal(Y.rows({ rows: [row({ duration: null })] })[0].secs, null);
  assert.equal(Y.rows({ rows: [row({ duration: 'x' })] })[0].secs, null);
});

test('a title or channel with a newline, U+202E and ESC is one line without them', () => {
  const [r] = Y.rows({ rows: [row({ title: 'Low\nTide‮\u001b Radio', channel: 'lofi\r\narchive' })] });
  assert.equal(r.title, 'Low Tide Radio');
  assert.equal(r.channel, 'lofi archive');
});

test('a 300-character title stays whole for the drawn row to elide', () => {
  const long = 'x'.repeat(300);
  assert.equal(Y.rows({ rows: [row({ title: long })] })[0].title, long);
});

test('a duration reads m:ss under an hour, h:mm:ss past it, and nothing for a live or unknown one', () => {
  assert.equal(Y.duration(267), '4:27');
  assert.equal(Y.duration(5), '0:05');
  assert.equal(Y.duration(3734.4), '1:02:14');
  assert.equal(Y.duration(null), '');
  assert.equal(Y.duration(undefined), '');
  assert.equal(Y.duration(-1), '');
});

// The id and thumb name a cache file and a URL, so anything but YouTube's 11 id characters is no row and no thumbnail.
test('a row without a video id is dropped, and a bad thumb draws the placeholder', () => {
  const out = Y.rows({ rows: [row({ id: '../etc/passwd' }), row({ id: 'abcdefghijk', thumb: '../x' }), 'nope', null] });
  assert.deepEqual(out.map((r) => [r.id, r.thumb]), [['abcdefghijk', '']]);
});

test('an answer with no rows, or no answer, lists nothing', () => {
  assert.deepEqual(Y.rows(null), []);
  assert.deepEqual(Y.rows({ error: 'x', kind: 'network' }), []);
});

test('the CLI prints one JSON object; anything else is no answer', () => {
  assert.deepEqual(Y.answer('{"rows":[]}\n'), { rows: [] });
  assert.equal(Y.answer('Traceback (most recent call last):'), null);
  assert.equal(Y.answer('[1]'), null);
});

test('each empty view names the key that fills it', () => {
  assert.deepEqual(Y.EMPTY.saved, { head: 'Nothing saved yet', key: 's', rest: 'saves a video' });
  assert.equal(Y.EMPTY.playlists, 'n makes one');
});

// The CLI's error is the exact line the list shows, so it is read as given, made one line.
test('a failed answer is its error, kind and raw line', () => {
  assert.deepEqual(Y.failure({ error: 'yt-dlp 2026.10.26 may be behind YouTube: run dots bump, then dots update', kind: 'extraction', raw: "ERROR: [youtube] Sign in to confirm you're not a bot" }), {
    error: 'yt-dlp 2026.10.26 may be behind YouTube: run dots bump, then dots update',
    kind: 'extraction',
    raw: "ERROR: [youtube] Sign in to confirm you're not a bot",
  });
  assert.deepEqual(Y.failure({ error: 'yt-dlp needs deno 2.3 or newer: run dots update', kind: 'runtime' }), { error: 'yt-dlp needs deno 2.3 or newer: run dots update', kind: 'runtime', raw: '' });
  assert.deepEqual(Y.failure({ error: 'No network.\nCheck Wi-Fi', kind: 'network', raw: 'ERROR:\u001b x' }), { error: 'No network. Check Wi-Fi', kind: 'network', raw: 'ERROR: x' });
});

test('an answer with rows and no error is no failure', () => {
  assert.equal(Y.failure({ rows: [], next: 0 }), null);
  assert.equal(Y.failure({ rows: [], error: '' }), null);
});

// A CLI that crashed printed no JSON, and the list still says so rather than draw empty.
test('no answer at all is a failure that names the CLI', () => {
  const none = { error: 'dots-youtube-api gave no answer', kind: '', raw: '' };
  assert.deepEqual(Y.failure(null), none);
  assert.deepEqual(Y.failure('Traceback'), none);
  assert.deepEqual(Y.failure([1]), none);
});

test('span draws a Playlist length in minutes, with hours from an hour', () => {
  assert.equal(Y.span(840), '14 min');
  assert.equal(Y.span(3600), '1 h 0 min');
  assert.equal(Y.span(4440), '1 h 14 min');
  assert.equal(Y.span(89), '1 min');
  assert.equal(Y.span(0), '0 min');
  assert.equal(Y.span('x'), '0 min');
  assert.equal(Y.span(undefined), '0 min');
});

test('rows keeps an unavailable reason as one line and drops anything else', () => {
  assert.equal(Y.rows({ rows: [row({ unavailable: 'made\nprivate' })] })[0].unavailable, 'made private');
  for (const unavailable of ['', 7, null, undefined]) assert.equal('unavailable' in Y.rows({ rows: [row({ unavailable })] })[0], false);
});

// dots-youtube-api snapshot prints {read, count} per 100 rows, then {title, channel, count, rows}, or an error line.
test('a snapshot counts what it has read until its last line brings every row', () => {
  let s = Y.snapshotting('PLfakeList0002', 'Lofi Archive', 300);
  assert.equal(Y.readingText(s), 'reading 0 of 300');
  s = Y.snapshotStep(s, '{"read":100,"count":300,"title":"Lofi Archive","channel":"lofi archive"}');
  assert.equal(Y.readingText(s), 'reading 100 of 300');
  assert.equal(s.done, false);
  s = Y.snapshotStep(s, 'not json');
  assert.equal(s.read, 100);
  const rows = [{ id: 'fakeLof0001', kind: 'video', title: 'Lofi\n1', channel: 'lofi archive', duration: 61, thumb: 'fakeLof0001' }, { id: 'fakeGone001', kind: 'video', title: null, channel: null, duration: null, thumb: '', unavailable: 'made private' }];
  s = Y.snapshotStep(s, JSON.stringify({ title: 'Lofi Archive', channel: 'lofi archive', count: 2, rows }));
  assert.equal(s.done, true);
  assert.equal(s.failed, null);
  assert.deepEqual(s.rows.map((r) => [r.id, r.title, r.secs, r.unavailable]), [['fakeLof0001', 'Lofi 1', 61, undefined], ['fakeGone001', '', null, 'made private']]);
});

test('a snapshot with no count yet reads its rows alone, and an error line ends it failed', () => {
  let s = Y.snapshotting('PLx', 'X', null);
  assert.equal(Y.readingText(s), 'reading 0');
  s = Y.snapshotStep(s, '{"read":100,"count":null,"title":"X","channel":null}');
  assert.equal(Y.readingText(s), 'reading 100');
  s = Y.snapshotStep(s, '{"error":"The playlist does not exist.","kind":"extraction","raw":"ERROR: x"}');
  assert.equal(s.done, true);
  assert.equal(s.failed.error, 'The playlist does not exist.');
});

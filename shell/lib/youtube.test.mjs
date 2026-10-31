import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as Y from './youtube.mjs';

const row = (o) => Object.assign({ id: 'dQw4w9WgXcQ', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: 267, thumb: 'dQw4w9WgXcQ' }, o);

test('a search answer lists its rows as the row draws them', () => {
  assert.deepEqual(Y.rows({ rows: [row()] }), [{ id: 'dQw4w9WgXcQ', title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: '4:27', secs: 267, thumb: 'dQw4w9WgXcQ' }]);
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

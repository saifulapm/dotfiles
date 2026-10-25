import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as R from './dekho-releases.mjs';

const MB = 1024 * 1024;
const rel = (hash, seeders, size_bytes) => ({ hash, seeders, size_bytes });

test('releases rank by seeders, then by size, whatever order the backend sent', () => {
  const ranked = R.rank([rel('a', 88, 12 * MB), rel('b', 530, 1100 * MB), rel('c', 412, 2100 * MB), rel('d', 412, 900 * MB), rel('e', null, 50 * MB)]);
  assert.deepEqual(
    ranked.map((r) => r.hash),
    ['b', 'c', 'd', 'a', 'e'],
  );
});

test('a release with no size ranks after its seeders tie with one', () => {
  assert.deepEqual(
    R.rank([rel('x', 10, null), rel('y', 10, 1)]).map((r) => r.hash),
    ['y', 'x'],
  );
});

test('a size reads in the unit of the whole, as the board writes it', () => {
  assert.equal(R.ofText(41 * MB, 108 * MB), '41 of 108 MB');
  assert.equal(R.ofText(300 * MB, 1.1 * 1024 * MB), '0.3 of 1.1 GB');
  assert.equal(R.ofText(0, 108 * MB), '0 of 108 MB');
});

test('a rate in bits per second reads in megabytes a second', () => {
  assert.equal(R.rateText(31876710), '3.8 MB/s');
  assert.equal(R.rateText(3355443), '0.4 MB/s');
  assert.equal(R.rateText(0), '0.0 MB/s');
});

const run = [
  { event: 'status', text: 'looking' },
  { event: 'trying', quality: '720p', size: '1.1 GB', seeders: 530, audio: 'EN 2.0' },
  { event: 'buffer', bytes: 0, needed_bytes: 108 * MB, peers: 0, sending: 0, down_bps: 0, up_bps: 0 },
  { event: 'buffer', bytes: 41 * MB, needed_bytes: 108 * MB, peers: 14, sending: 9, down_bps: 31876710, up_bps: 3355443 },
];

test('the steps follow the events: found, connected, buffering, mpv, each done when the next is reached', () => {
  assert.deepEqual(R.starting(run.slice(0, 1)).steps, []);
  assert.deepEqual(R.starting(run.slice(0, 2)).steps, [{ text: 'Found 530 seeders', state: 'current' }]);
  assert.deepEqual(R.starting(run.slice(0, 3)).steps, [{ text: 'Found 530 seeders', state: 'current' }]);
  assert.deepEqual(R.starting(run).steps, [
    { text: 'Found 530 seeders', state: 'done' },
    { text: 'Connected to peers', state: 'done' },
    { text: 'Buffering the start of the file', state: 'current' },
    { text: 'mpv starts at 108 MB', state: 'pending' },
  ]);
  const ready = R.starting(run.concat([{ event: 'ready', rate_bps: 1, buffered: 1, cached: false }]));
  assert.deepEqual(
    ready.steps.map((s) => s.state),
    ['done', 'done', 'done', 'current'],
  );
  const playing = R.starting(run.concat([{ event: 'ready' }, { event: 'playing', title: 'x' }]));
  assert.equal(playing.playing, true);
  assert.deepEqual(
    playing.steps.map((s) => s.state),
    ['done', 'done', 'done', 'done'],
  );
});

test('progress is the bytes over what mpv needs, with the peers and rates of the last buffer', () => {
  const s = R.starting(run);
  assert.equal(s.progress, 41 / 108);
  assert.equal(s.percent, 'buffering 38%');
  assert.equal(s.amount, '41 of 108 MB');
  assert.equal(s.peers, '14 peers · 9 sending');
  assert.equal(s.down, '3.8 MB/s down');
  assert.equal(s.up, '0.4 MB/s up');
  assert.equal(s.release, '720p · 1.1 GB');
  assert.equal(s.playing, false);
  const none = R.starting([]);
  assert.equal(none.progress, 0);
  assert.equal(none.amount, '');
  assert.equal(R.starting(run.concat([{ event: 'ready' }])).progress, 1);
});

// mpv starts on the sequential run from the file's start, not on whatever pieces arrived (#1FTZTF75).
test('Starting counts the bytes buffered from the start, not every piece on disk', () => {
  const mb = 1048576;
  const s = R.starting([
    { event: 'trying', seeders: 9, quality: '1080p', size: '2.1 GB' },
    { event: 'buffer', peers: 4, sending: 3, buffered: 21 * mb, bytes: 95 * mb, needed_bytes: 31 * mb, down_bps: 8e6, up_bps: 1e6 },
  ]);
  assert.ok(s.progress > 0.6 && s.progress < 0.7, String(s.progress));
  assert.equal(s.amount, '21 of 31 MB');
  assert.equal(s.percent, 'buffering 68%');
});

// A film has no episodes to point at (#J0ZGNW4N).
test('the no-releases words name an episode for a series and the film for a film', () => {
  const w = R.releasesText('plain');
  assert.match(w.noneWhy('tv'), /this episode/);
  assert.doesNotMatch(w.noneWhy('movie'), /episode/);
  assert.match(w.noneWhy('movie'), /this film/);
  assert.ok(w.tries('tv').some(([, t]) => /earlier episode/.test(t)));
  assert.ok(w.tries('movie').every(([, t]) => !/episode|season/.test(t)));
});

test('the list opens on Auto, then the releases best first', () => {
  const items = [rel('b', 530, 1), rel('c', 412, 2)];
  assert.deepEqual(R.rows(items), [{ auto: true }, items[0], items[1]]);
  assert.equal(R.releasesText('plain').auto, 'Auto: let dekho decide');
});

const named = (hash, title) => ({ hash, title });
const listed = [
  named('b2', 'The.Long.Tide.S03E04.720p.WEB-DL.x264'),
  named('a1', 'The.Long.Tide.S03E04.1080p.WEB-DL.x265'),
  named('d4', 'The\nLong‮Tide\u001b[31m S03E04 1080p BluRay x264'),
];
const hashes = (rows) => rows.map((r) => (r.auto ? 'auto' : r.hash));

test('a filter keeps Auto first and the releases whose name holds it', () => {
  assert.deepEqual(hashes(R.rows(listed, '1080')), ['auto', 'a1', 'd4']);
});

test('an empty or missing filter keeps every release', () => {
  assert.deepEqual(hashes(R.rows(listed, '')), ['auto', 'b2', 'a1', 'd4']);
  assert.deepEqual(hashes(R.rows(listed)), ['auto', 'b2', 'a1', 'd4']);
});

test('a filter ignores case', () => {
  assert.deepEqual(hashes(R.rows(listed, 'WEB-dl')), ['auto', 'b2', 'a1']);
});

// The last name draws as "The LongTide [31m S03E04 ...": the newline is a space, the U+202E goes, ESC is a space.
test('a filter matches a name on its one-lined form', () => {
  assert.deepEqual(hashes(R.rows(listed, 'The LongTide [31m S03')), ['auto', 'd4']);
  assert.deepEqual(hashes(R.rows(listed, 'Long‮Tide')), ['auto']);
  assert.deepEqual(hashes(R.rows(listed, '\n')), ['auto']);
});

test('a filter that matches nothing leaves Auto alone', () => {
  assert.deepEqual(hashes(R.rows(listed, 'xyz')), ['auto']);
});

test('a no-match line and the filter key are worded in each voice', () => {
  assert.equal(R.releasesText('plain').noMatch('xyz'), 'No release matches xyz');
  assert.equal(R.releasesText('bracket').noMatch('xyz'), 'NO RELEASE MATCHES XYZ');
  assert.deepEqual(R.releasesText('plain').keys[3], ['ctrl+f', 'filter']);
});

test('Auto plays with no release, so dekho decides; a release plays by its hash', () => {
  const film = { id: 401, kind: 'movie' };
  const ep = { id: 101, kind: 'tv', season: 3, episode: 4 };
  assert.deepEqual(R.playArgs(film, { auto: true }), ['--id', '401', '--kind', 'movie']);
  assert.deepEqual(R.playArgs(ep, { auto: true }), ['--id', '101', '--kind', 'tv', '-s', '3', '-e', '4']);
  assert.deepEqual(R.playArgs(ep, rel('b', 530, 1)), ['--id', '101', '--kind', 'tv', '-s', '3', '-e', '4', '--release', 'b']);
});

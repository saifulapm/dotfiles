// bin/dev-fake-youtube, which nested checks trust to answer as bin/dots-youtube-api does: its rows, its thumbnails and its three failures.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dev-fake-youtube', import.meta.url).pathname;

function rig(t) {
  const dir = mkdtempSync(join(tmpdir(), 'fake-youtube-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const run = (...args) => spawnSync('bash', [bin, ...args], { env: { PATH: process.env.PATH, DOTS_DEV_DIR: dir }, encoding: 'utf8', timeout: 5000 });
  return { dir, run };
}

const keys = ['channel', 'duration', 'id', 'kind', 'thumb', 'title'];
const keysOf = (row) => Object.keys(row).sort();
const checkRow = (row, kind) => {
  assert.equal(row.kind, kind);
  assert.deepEqual(keysOf(row), kind === 'playlist' ? [...keys, 'count'].sort() : keys, row.id);
};
const json = (r) => {
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
};

test('search prints 20 video rows with exactly the contract\'s keys, and logs the call', (t) => {
  const { dir, run } = rig(t);
  const r = run('search', 'nujabes', 'videos', '0');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trimEnd().split('\n').length, 1, 'one line of JSON');
  const { rows, next } = JSON.parse(r.stdout);
  assert.equal(rows.length, 20);
  assert.equal(next, 20, 'where the following page starts, as the real CLI says');
  for (const row of rows) checkRow(row, 'video');
  assert.match(rows[3].title, /\n/, 'a title the App must flatten');
  assert.equal(rows[5].title.length, 300);
  assert.equal(readFileSync(join(dir, 'youtube.log'), 'utf8'), 'search nujabes videos 0\n');
});

test('a videos search pages 20, 20 with a repeat, 5, then none', (t) => {
  const { run } = rig(t);
  const p2 = json(run('search', 'x', 'videos', '20'));
  assert.equal(p2.rows.length, 20);
  assert.equal(p2.next, 40);
  assert.equal(p2.rows[2].id, 'fakeVid0007', 'the repeat of a page 1 row');
  assert.equal(p2.rows[2].title, 'Modal Soul — full album');
  for (const row of p2.rows) checkRow(row, 'video');
  const p3 = json(run('search', 'x', 'videos', '40'));
  assert.deepEqual([p3.rows.length, p3.next], [5, 45]);
  assert.equal(p3.rows[4].id, 'fakeVid0045');
  assert.deepEqual(json(run('search', 'x', 'videos', '60')), { rows: [], next: 45 });
});

test('a playlists search is one short page of playlist rows', (t) => {
  const { run } = rig(t);
  const { rows, next } = json(run('search', 'x', 'playlists', '0'));
  assert.equal(next, 3);
  assert.deepEqual(rows.map((r) => [r.id, r.title, r.channel, r.count, r.thumb, r.duration]), [
    ['PLfakeList0001', 'Modal Soul', 'Nujabes', 14, 'fakeVid0001', null],
    ['PLfakeList0002', 'Lofi Archive', 'lofi archive', 300, 'fakeVid0002', null],
    ['PLfakePrivate1', 'Private Mix', 'someone', null, 'fakeVid0003', null],
  ]);
  for (const row of rows) checkRow(row, 'playlist');
});

test('a channels search lists three channel rows', (t) => {
  const { run } = rig(t);
  const { rows, next } = json(run('search', 'x', 'channels', '0'));
  assert.equal(next, 3);
  assert.deepEqual(rows.map((r) => [r.id, r.title, r.channel, r.thumb, r.duration]), [
    ['UCfakeChan00000000000001', 'Nujabes', '@nujabes', '', null],
    ['UCfakeChan00000000000002', 'Quiet Corner', '', '', null],
    ['UCfakeChan00000000000003', 'Hydeout Productions', '@hydeout', '', null],
  ]);
  for (const row of rows) {
    checkRow(row, 'channel');
    assert.equal(row.id.length, 24);
  }
});

test('channel pages 25 uploads by 20, and @nujabes answers as its UC id', (t) => {
  const { dir, run } = rig(t);
  const c1 = 'UCfakeChan00000000000001';
  const p1 = json(run('channel', c1, '0'));
  assert.equal(p1.title, 'Nujabes');
  assert.equal(p1.rows.length, 20);
  assert.equal(p1.next, 20);
  assert.equal(p1.rows[0].id, 'fakeUpl0001');
  for (const row of p1.rows) {
    checkRow(row, 'video');
    assert.equal(row.channel, 'Nujabes');
    assert.equal(row.thumb, row.id);
  }
  const p2 = json(run('channel', c1, '20'));
  assert.deepEqual([p2.rows.length, p2.next, p2.rows[4].id], [5, 25, 'fakeUpl0025']);
  assert.deepEqual(json(run('channel', '@nujabes', '0')), p1);
  assert.deepEqual(json(run('channel', '@nujabes', '20')), p2);
  assert.match(readFileSync(join(dir, 'youtube.log'), 'utf8'), /^channel UCfakeChan00000000000001 0\n/);
});

test('a channel with no uploads, a small one and an unknown one', (t) => {
  const { run } = rig(t);
  assert.deepEqual(json(run('channel', 'UCfakeChan00000000000002', '0')), { title: null, rows: [], next: 0 });
  assert.deepEqual(json(run('channel', 'UCnotAChannel0000000000x', '20')), { title: null, rows: [], next: 20 });
  const h = json(run('channel', 'UCfakeChan00000000000003', '0'));
  assert.equal(h.title, 'Hydeout Productions');
  assert.equal(h.rows.length, 3);
  assert.equal(h.next, 3);
  for (const row of h.rows) checkRow(row, 'video');
});

test('playlist answers every item by bare id and by URL', (t) => {
  const { run } = rig(t);
  const a = json(run('playlist', 'PLfakeList0001'));
  assert.equal(a.title, 'Modal Soul');
  assert.equal(a.count, 14);
  assert.equal(a.rows.length, 14);
  for (const row of a.rows) checkRow(row, 'video');
  assert.deepEqual(json(run('playlist', 'https://www.youtube.com/playlist?list=PLfakeList0001')), a);
  assert.deepEqual(json(run('playlist', 'https://www.youtube.com/watch?v=fakeVid0001&list=PLfakeList0001&t=3')), a);
  const b = json(run('playlist', 'PLfakeList0002'));
  assert.equal(b.title, 'Lofi Archive');
  assert.equal(b.count, 300);
  assert.equal(b.rows.length, 300);
  assert.equal(b.rows[299].id, 'fakeLof0300');
  assert.ok(b.rows.every((r) => /^[A-Za-z0-9_-]{11}$/.test(r.id)));
  checkRow(b.rows[0], 'video');
});

test('a private or unknown playlist fails as extraction and exits 1', (t) => {
  const { run } = rig(t);
  for (const id of ['PLfakePrivate1', 'PLnoSuchList']) {
    const r = run('playlist', id);
    assert.equal(r.status, 1, id);
    assert.deepEqual(JSON.parse(r.stdout), {
      error: 'The playlist does not exist.',
      kind: 'extraction',
      raw: `ERROR: [youtube:tab] ${id}: YouTube said: The playlist does not exist.`,
    });
  }
});

const lines = (r) => {
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trimEnd().split('\n').map((l) => JSON.parse(l));
};

test('snapshot prints how far it has read after each 100 rows, then every row in order with the title, channel and count', (t) => {
  const { run } = rig(t);
  const out = lines(run('snapshot', 'https://www.youtube.com/playlist?list=PLfakeList0002'));
  assert.equal(out.length, 4);
  assert.deepEqual(out.slice(0, 3), [100, 200, 300].map((read) => ({ read, count: 300, title: 'Lofi Archive', channel: 'lofi archive' })));
  const last = out[3];
  assert.deepEqual(Object.keys(last), ['title', 'channel', 'count', 'rows']);
  assert.deepEqual([last.title, last.channel, last.count, last.rows.length], ['Lofi Archive', 'lofi archive', 300, 300]);
  assert.deepEqual(last.rows.map((r) => r.id), Array.from({ length: 300 }, (_, i) => `fakeLof${String(i + 1).padStart(4, '0')}`));
  assert.deepEqual(last.rows[0], { id: 'fakeLof0001', kind: 'video', title: 'Lofi 1', channel: 'lofi archive', duration: 61, thumb: 'fakeLof0001' });
});

test('with youtube-grow, playlist and snapshot both answer one more item', (t) => {
  const { dir, run } = rig(t);
  writeFileSync(join(dir, 'youtube-grow'), '');
  const grown = { id: 'fakeGrow001', kind: 'video', title: 'Grown', channel: 'lofi archive', duration: 60, thumb: '' };
  const p = json(run('playlist', 'PLfakeList0002'));
  assert.deepEqual([p.count, p.rows.length, p.rows[300]], [301, 301, grown]);
  const s = lines(run('snapshot', 'PLfakeList0002'));
  assert.deepEqual(s.slice(0, -1).map((l) => [l.read, l.count]), [[100, 301], [200, 301], [300, 301], [301, 301]]);
  assert.deepEqual([s.at(-1).count, s.at(-1).rows.length, s.at(-1).rows[300]], [301, 301, grown]);
});

test('PLfakeList0003 holds an unavailable video second, and snapshot fails as playlist does on an unknown list', (t) => {
  const { run } = rig(t);
  const p = json(run('playlist', 'PLfakeList0003'));
  assert.deepEqual([p.title, p.count, p.rows.map((r) => r.id)], ['Mixed tape', 4, ['fakeVid0004', 'fakeGone001', 'fakeVid0005', 'fakeVid0006']]);
  assert.deepEqual(p.rows[1], { id: 'fakeGone001', kind: 'video', title: '', channel: '', duration: null, thumb: '', unavailable: 'made private' });
  assert.ok(!('unavailable' in p.rows[0]));
  assert.deepEqual(lines(run('snapshot', 'PLfakeList0003')).at(-1).rows, p.rows);
  const r = run('snapshot', 'PLnoSuchList');
  assert.equal(r.status, 1);
  assert.deepEqual(JSON.parse(r.stdout), { error: 'The playlist does not exist.', kind: 'extraction', raw: 'ERROR: [youtube:tab] PLnoSuchList: YouTube said: The playlist does not exist.' });
});

test('resolve places each URL shape', (t) => {
  const { run } = rig(t);
  const res = (u) => json(run('resolve', u));
  const row7 = { id: 'fakeVid0007', kind: 'video', title: 'Modal Soul — full album', channel: 'lofi archive', duration: 3734, thumb: 'fakeVid0007' };
  const want7 = { kind: 'video', id: 'fakeVid0007', rows: [row7] };
  for (const u of [
    'https://www.youtube.com/watch?v=fakeVid0007',
    'https://www.youtube.com/watch?v=fakeVid0007&list=PLfakeList0001&t=30',
    'https://youtu.be/fakeVid0007',
    'https://music.youtube.com/watch?v=fakeVid0007',
    'youtube.com/watch?v=fakeVid0007',
  ]) assert.deepEqual(res(u), want7, u);
  assert.deepEqual(res('https://youtu.be/abcdefghijk'), {
    kind: 'video',
    id: 'abcdefghijk',
    rows: [{ id: 'abcdefghijk', kind: 'video', title: 'Pasted video', channel: 'Pasted', duration: 61, thumb: 'abcdefghijk' }],
  });
  assert.deepEqual(res('https://www.youtube.com/playlist?list=PLfakeList0002'), { kind: 'playlist', id: 'PLfakeList0002' });
  assert.deepEqual(res('https://www.youtube.com/@nujabes'), { kind: 'channel', id: '@nujabes' });
  assert.deepEqual(res('https://www.youtube.com/@nujabes/videos'), { kind: 'channel', id: '@nujabes' });
  assert.deepEqual(res('https://www.youtube.com/channel/UCfakeChan00000000000003'), { kind: 'channel', id: 'UCfakeChan00000000000003' });
  assert.deepEqual(res('https://example.com/watch?v=fakeVid0007'), { kind: 'none' });
  assert.deepEqual(res('https://www.youtube.com/feed/history'), { kind: 'none' });
});

test('with youtube-fail naming a kind, search, channel, playlist, snapshot and resolve print that failure as the real CLI does and exits 1', (t) => {
  const { dir, run } = rig(t);
  const want = {
    runtime: 'yt-dlp needs deno 2.3 or newer: run dots update',
    extraction: 'yt-dlp 2026.10.26 may be behind YouTube: run dots bump, then dots update',
    network: 'No network. Check Wi-Fi, then ↵ to try again.',
  };
  for (const [kind, error] of Object.entries(want)) {
    writeFileSync(join(dir, 'youtube-fail'), kind + '\n');
    for (const verb of [['search', 'lofi', 'videos', '0'], ['channel', '@nujabes', '0'], ['playlist', 'PLfakeList0001'], ['snapshot', 'PLfakeList0001'], ['resolve', 'https://youtu.be/fakeVid0007']]) {
      const r = run(...verb);
      assert.equal(r.status, 1, kind + ' ' + verb[0]);
      const a = JSON.parse(r.stdout);
      assert.deepEqual([a.kind, a.error], [kind, error]);
      assert.equal(typeof a.raw, 'string');
    }
  }
  rmSync(join(dir, 'youtube-fail'));
  assert.equal(run('search', 'lofi', 'videos', '0').status, 0, 'a retry once the file is gone finds rows');
});

test('thumbs names each asked thumbnail it holds, and leaves out one it lacks and a bad id', (t) => {
  const { run } = rig(t);
  const r = run('thumbs', 'fakeVid0001', 'fakeVid0008', '../../etc', 'fakeVid0020');
  assert.equal(r.status, 0, r.stderr);
  const a = JSON.parse(r.stdout);
  assert.ok(a.dir.startsWith('/'));
  assert.deepEqual(Object.keys(a.files).sort(), ['fakeVid0001', 'fakeVid0020']);
  for (const f of Object.values(a.files)) assert.ok(existsSync(f), f);
});

test('an unknown verb is a usage error', (t) => {
  const { run } = rig(t);
  assert.equal(run('bogus', 'x').status, 2);
});

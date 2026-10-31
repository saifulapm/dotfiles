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

test('search prints 20 rows, each with exactly the real CLI\'s five fields, and logs the call', (t) => {
  const { dir, run } = rig(t);
  const r = run('search', 'nujabes', 'videos', '0');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trimEnd().split('\n').length, 1, 'one line of JSON');
  const { rows, next } = JSON.parse(r.stdout);
  assert.equal(rows.length, 20);
  assert.equal(next, 20, 'where the following page starts, as the real CLI says');
  for (const row of rows) assert.deepEqual(Object.keys(row).sort(), ['channel', 'duration', 'id', 'thumb', 'title']);
  assert.match(rows[3].title, /\n/, 'a title the App must flatten');
  assert.equal(rows[5].title.length, 300);
  assert.equal(readFileSync(join(dir, 'youtube.log'), 'utf8'), 'search nujabes videos 0\n');
});

test('search past the canned rows lists none', (t) => {
  const { run } = rig(t);
  assert.deepEqual(JSON.parse(run('search', 'nujabes', 'videos', '20').stdout), { rows: [], next: 20 });
});

test('with youtube-fail naming a kind, search prints that failure as the real CLI does and exits 1', (t) => {
  const { dir, run } = rig(t);
  const want = {
    runtime: 'yt-dlp needs deno 2.3 or newer: run dots update',
    extraction: 'yt-dlp 2026.10.26 may be behind YouTube: run dots bump, then dots update',
    network: 'No network. Check Wi-Fi, then ↵ to try again.',
  };
  for (const [kind, error] of Object.entries(want)) {
    writeFileSync(join(dir, 'youtube-fail'), kind + '\n');
    const r = run('search', 'lofi', 'videos', '0');
    assert.equal(r.status, 1, kind);
    const a = JSON.parse(r.stdout);
    assert.deepEqual([a.kind, a.error], [kind, error]);
    assert.equal(typeof a.raw, 'string');
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
  assert.equal(run('resolve', 'x').status, 2);
});

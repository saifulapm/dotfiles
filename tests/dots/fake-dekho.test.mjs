// bin/dev-fake-dekho's play and trailer, which nested checks trust to behave as the real dekho does: its labels, its resume, the history a play leaves and how a stopped one ends.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dev-fake-dekho', import.meta.url).pathname;

// A scratch DOTS_DEV_DIR with a qs that stands in for fake-mpv.qml: it logs the window title it was given and, after a moment, ends by SIGTERM, as fake-mpv.qml does when its window closes.
function rig(t) {
  const dir = mkdtempSync(join(tmpdir(), 'fake-dekho-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  writeFileSync(join(dir, 'bin', 'qs'), `#!/bin/sh\necho "$FAKE_MPV_TITLE|$FAKE_MPV_NEXT_TITLE|$FAKE_MPV_NEXT_SECS" >>"${dir}/mpv-titles"\nsleep \${FAKE_QS_SECS:-0.1}\nkill -TERM $$\n`);
  chmodSync(join(dir, 'bin', 'qs'), 0o755);
  const env = { PATH: `${dir}/bin:${process.env.PATH}`, HOME: dir, DOTS_DEV_DIR: dir };
  const run = (...args) => spawnSync('bash', [bin, ...args], { env, encoding: 'utf8', timeout: 15000 });
  return { dir, env, run };
}

const events = (r) => r.stdout.trimEnd().split('\n').map((l) => JSON.parse(l));
const history = (run) => JSON.parse(run('api', 'history', '--limit', '20').stdout).items;

test('a series resumed with no -s/-e plays the episode history holds, from its time, labelled as the real dekho labels it', (t) => {
  const { run } = rig(t);
  const before = history(run).find((h) => h.id === 101);
  const r = run('play', '--json', '--id', '101', '--kind', 'tv', '--resume');
  assert.equal(r.status, 0, r.stderr);
  const playing = events(r).find((e) => e.event === 'playing');
  assert.match(playing.title, /^The Long Tide — S03E04  \S/);
  assert.equal(playing.resumed_at, before.position);
  assert.deepEqual(events(r).slice(-2).map((e) => e.event), ['ended', 'exit']);
  assert.equal(events(r).at(-1).code, 0);
});

test('a play that ends puts its title first in history, ten minutes past where it started', (t) => {
  const { run } = rig(t);
  const before = history(run).find((h) => h.id === 202);
  assert.equal(run('play', '--json', '--id', '202', '--kind', 'movie', '--resume').status, 0);
  const [first] = history(run);
  assert.deepEqual([first.id, first.kind, first.position, first.duration], [202, 'movie', before.position + 600, before.duration]);
  // A film not in history starts at 0 and joins it.
  const r = run('play', '--json', '--id', '401', '--kind', 'movie');
  assert.deepEqual(events(r).find((e) => e.event === 'playing'), { event: 'playing', title: 'Seven Stations (2026)', kind: 'movie', id: 401, resumed_at: 0, bitrate: 4000000 });
  assert.deepEqual(history(run).slice(0, 2).map((h) => [h.id, h.position]), [[401, 600], [202, before.position + 600]]);
});

// Starts a play and sends SIGTERM once its playing event is out and after waitMs more; resolves with the exit and the events.
async function stopped(env, waitMs) {
  const child = spawn('bash', [bin, 'play', '--json', '--id', '202', '--kind', 'movie'], { env: { ...env, FAKE_QS_SECS: '30' } });
  let out = '';
  child.stdout.on('data', (d) => (out += d));
  await new Promise((resolve) => {
    const poll = setInterval(() => {
      if (out.includes(waitMs === null ? '"buffer"' : '"playing"')) {
        clearInterval(poll);
        setTimeout(() => child.kill('SIGTERM'), waitMs ?? 0);
        resolve();
      }
    }, 50);
  });
  const code = await new Promise((resolve) => child.on('exit', (c, s) => resolve(c ?? s)));
  return { code, events: out.trimEnd().split('\n').map((l) => JSON.parse(l)) };
}

test('a play stopped once mpv is up ends as when mpv quits, history first, as the real one does on SIGTERM', async (t) => {
  const { env, run } = rig(t);
  // Past the playing event's 1.5 s wait, so the stand-in for mpv is up.
  const { code, events } = await stopped(env, 2000);
  assert.equal(code, 0);
  assert.deepEqual(events.slice(-2).map((e) => e.event), ['ended', 'exit']);
  assert.equal(events.at(-1).code, 0);
  assert.deepEqual([history(run)[0].id, history(run)[0].position], [202, 600]);
});

test('a play stopped before mpv opens exits 143 with no event and leaves history alone', async (t) => {
  const { env, run } = rig(t);
  const before = history(run);
  const { code, events } = await stopped(env, null);
  assert.equal(code, 143);
  assert.ok(!events.some((e) => e.event === 'ended' || e.event === 'exit'));
  assert.deepEqual(history(run), before);
});

test('with dekho-advance a series moves on to its next episode only by its mpv window title, and history then holds that one', (t) => {
  const { dir, run } = rig(t);
  writeFileSync(join(dir, 'dekho-advance'), '1');
  const r = spawnSync('bash', [bin, 'play', '--json', '--id', '101', '--kind', 'tv', '-s', '3', '-e', '4'], { env: { PATH: `${dir}/bin:${process.env.PATH}`, HOME: dir, DOTS_DEV_DIR: dir, FAKE_QS_SECS: '2' }, encoding: 'utf8', timeout: 15000 });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(events(r).filter((e) => e.event === 'playing').map((e) => e.title), ['The Long Tide — S03E04  Quay Nine']);
  const [title, next, secs] = readFileSync(join(dir, 'mpv-titles'), 'utf8').trim().split('|');
  assert.deepEqual([title, secs], ['The Long Tide — S03E04  Quay Nine', '1']);
  assert.match(next, /^The Long Tide — S03E05  \S/);
  assert.deepEqual([history(run)[0].id, history(run)[0].season, history(run)[0].episode, history(run)[0].position], [101, 3, 5, 600]);
});

test('any film answers as a film named as Home has it, with a trailer, and A Quiet Verdict and Harbour Lights have none', (t) => {
  const { run } = rig(t);
  const title = (id, kind) => JSON.parse(run('api', 'title', '--id', id, '--kind', kind).stdout);
  const film = title('401', 'movie');
  assert.deepEqual([film.id, film.kind, film.title, film.year, film.poster], [401, 'movie', 'Seven Stations', '2026', '/p401.jpg']);
  assert.match(film.trailer, /^https:\/\/www\.youtube\.com\/watch\?v=/);
  assert.equal(title('202', 'movie').title, 'Night Ferry');
  assert.equal(title('400', 'movie').trailer, null);
  assert.equal(title('300', 'tv').trailer, null);
  assert.match(title('101', 'tv').trailer, /^https:/);
});

test("a trailer plays the title's trailer in mpv and leaves history alone; a title with none fails as the real one does", (t) => {
  const { dir, run } = rig(t);
  const before = history(run);
  const r = run('trailer', '--json', '--id', '401', '--kind', 'movie');
  assert.equal(r.status, 0, r.stderr);
  const playing = events(r).find((e) => e.event === 'playing');
  assert.deepEqual([playing.title, playing.kind, playing.id], ['Seven Stations (2026) — Trailer', 'movie', 401]);
  assert.match(playing.url, /^https:/);
  assert.deepEqual(events(r).at(-1), { event: 'exit', code: 0 });
  assert.deepEqual(history(run), before);
  const none = run('trailer', '--json', '--id', '400', '--kind', 'movie');
  assert.equal(none.status, 1);
  assert.deepEqual(events(none).slice(-2), [{ event: 'error', text: 'TMDB has no trailer for A Quiet Verdict' }, { event: 'exit', code: 1 }]);
  writeFileSync(join(dir, 'dekho-trailer-fails'), 'yt-dlp: no formats');
  assert.deepEqual(events(run('trailer', '--json', '--id', '401', '--kind', 'movie')).slice(-2), [{ event: 'error', text: 'yt-dlp: no formats' }, { event: 'exit', code: 1 }]);
});

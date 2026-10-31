// Two machines, a and b, sync the YouTube App's Playlists and Saved through one local alias remote.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import * as P from '../../shell/lib/youtube-playlists.mjs';
import { machine, sync, world } from './lib.mjs';

const T = 1760000000000;
const FAR = 9999999999999;

const write = (path, store) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, P.serialize(store));
};
const storePath = (m) => join(m.data, 'youtube', m.id + '.json');
const store = (m) => P.parseStore(readFileSync(storePath(m), 'utf8'));
const status = (m) => JSON.parse(readFileSync(m.status, 'utf8'));
const ids = (s, id) => P.items(s, id).map((v) => v.id);
const video = (id) => ({ id, title: 'Aruarian Dance', channel: 'Nujabes - Topic', duration: 267, thumb: id });
const focus = () => P.addMany(P.create(P.emptyStore(), 'focus', 'Focus', T), 'focus', ['v1', 'v2', 'v3'].map(video), T);

async function ok(m, args) {
  const r = await sync(m, args);
  assert.equal(r.code, 0, `dots sync on ${m.id} exited ${r.code}: ${r.stdout}${r.stderr}`);
  return r;
}

// Every file under the remote, as paths relative to it.
function remoteFiles(w) {
  const out = [];
  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      if (e.isDirectory()) walk(join(dir, e.name));
      else out.push(relative(w.remote, join(dir, e.name)));
    }
  };
  walk(w.remote);
  return out.sort();
}

test('a song added to Focus on a and another removed on b are both kept on both machines after each syncs twice', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(a), focus());
  await ok(a);
  await ok(b);
  assert.deepEqual(ids(store(b), 'focus'), ['v1', 'v2', 'v3']);
  write(storePath(a), P.add(store(a), 'focus', video('x'), T + 10));
  write(storePath(b), P.removeItem(store(b), 'focus', 'v2', T + 20));
  for (let i = 0; i < 2; i++) {
    await ok(a);
    await ok(b);
  }
  for (const m of [a, b]) {
    assert.deepEqual(ids(store(m), 'focus'), ['v1', 'v3', 'x'], m.id);
    assert.equal(status(m).youtube.ok, true, m.id);
  }
});

test('--only youtube runs the youtube unit alone, uploads this machine file and keeps the other entries', async () => {
  const w = world();
  const a = machine(w, 'a');
  write(storePath(a), focus());
  await ok(a, ['--only', 'goals']);
  const before = status(a).goals;
  await ok(a, ['--only', 'youtube']);
  assert.deepEqual(status(a).goals, before);
  assert.deepEqual(Object.keys(status(a)).sort(), ['goals', 'youtube']);
  assert.deepEqual([status(a).youtube.ok, status(a).youtube.error], [true, null]);
  assert.deepEqual(ids(P.parseStore(readFileSync(join(w.remote, 'dots-sync/youtube/a.json'), 'utf8')), 'focus'), ['v1', 'v2', 'v3']);
});

test('History and the download index stay on the machine; the remote holds only each store', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  for (const m of [a, b]) {
    write(storePath(m), focus());
    const state = join(m.env.XDG_STATE_HOME, 'dots/youtube');
    mkdirSync(state, { recursive: true });
    writeFileSync(join(state, 'history.json'), '{"version":1,"items":[]}');
    writeFileSync(join(state, 'downloads.json'), '{"version":1,"items":{}}');
  }
  await ok(a, ['--only', 'youtube']);
  await ok(b, ['--only', 'youtube']);
  assert.deepEqual(remoteFiles(w), ['dots-sync/youtube/a.json', 'dots-sync/youtube/b.json']);
});

test('another machine file that does not parse fails the unit by its name, what parses still merges and goes up, and the next good round clears it', async () => {
  const w = world();
  const [a, c] = [machine(w, 'a'), machine(w, 'c')];
  write(storePath(c), focus());
  await ok(c);
  writeFileSync(join(w.remote, 'dots-sync/youtube/other.json'), '{"playlists":');
  write(storePath(a), P.add(P.emptyStore(), 'saved', video('s1'), T));
  let r = await sync(a, ['--only', 'youtube']);
  assert.equal(r.code, 5, r.stderr);
  assert.deepEqual([status(a).youtube.ok, status(a).youtube.error], [false, 'youtube: skipped other.json, which does not parse']);
  assert.deepEqual(ids(store(a), 'focus'), ['v1', 'v2', 'v3']);
  // JSON of the wrong shape is skipped the same way, not a crash that holds this machine's store back.
  writeFileSync(join(w.remote, 'dots-sync/youtube/other.json'), '{"version":1,"playlists":{"x":{"id":"x","name":"X","items":null}}}');
  r = await sync(a, ['--only', 'youtube']);
  assert.equal(r.code, 5, r.stderr);
  assert.equal(status(a).youtube.error, 'youtube: skipped other.json, which does not parse');
  const pushed = P.parseStore(readFileSync(join(w.remote, 'dots-sync/youtube/a.json'), 'utf8'));
  assert.deepEqual([ids(pushed, 'focus'), ids(pushed, 'saved')], [['v1', 'v2', 'v3'], ['s1']]);
  writeFileSync(join(w.remote, 'dots-sync/youtube/other.json'), P.serialize(P.emptyStore()));
  await ok(a, ['--only', 'youtube']);
  assert.deepEqual([status(a).youtube.ok, status(a).youtube.error], [true, null]);
});

// a's clock ran far ahead when it pushed these: a rename and a removal that would outvote every later edit.
const ahead = () => P.removeItem(P.rename(focus(), 'focus', 'Forged', FAR), 'focus', 'v1', FAR);

test('a pulled Playlist or item stamped more than a day ahead is left out, and the unit says so', async () => {
  const w = world();
  const b = machine(w, 'b');
  const pulled = P.add(ahead(), 'saved', video('s1'), T);
  write(join(w.remote, 'dots-sync/youtube/a.json'), pulled);
  write(storePath(b), P.add(P.emptyStore(), 'saved', video('s2'), T));
  const r = await sync(b, ['--only', 'youtube']);
  assert.equal(r.code, 5, r.stderr);
  assert.match(r.stderr, /^dots sync: youtube: left out 1 record from a\.json, stamped more than a day ahead$/m);
  // The Playlist stamped ahead goes with its items; Saved, stamped right, still merges.
  assert.deepEqual(P.playlists(store(b)), []);
  assert.deepEqual(ids(store(b), 'saved'), ['s1', 's2']);
});

test('a machine re-stamps its own Playlists and items stamped ahead to now, so they travel again', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(a), ahead());
  const t0 = Date.now();
  const r = await ok(a, ['--only', 'youtube']);
  assert.match(r.stderr, /^youtube: re-stamped 2 records stamped more than a day ahead$/m);
  const f = store(a).playlists.focus;
  for (const t of [f.updatedAt, f.nameAt, f.items.v1.updatedAt]) assert.ok(t >= t0 && t <= Date.now(), `stamp ${t}`);
  await ok(b, ['--only', 'youtube']);
  assert.deepEqual([P.playlists(store(b)).map((l) => l.name), ids(store(b), 'focus')], [['Forged'], ['v2', 'v3']]);
});

test('a store from before Playlists merges with a new one without losing a video', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  const old = '{"version":1,"playlists":{"saved":{"id":"saved","name":"Saved","updatedAt":5,"items":{"o1":{"id":"o1","title":"T","channel":"C","duration":9,"thumb":"o1","pos":1,"updatedAt":5}}}}}';
  mkdirSync(dirname(storePath(b)), { recursive: true });
  writeFileSync(storePath(b), old);
  write(storePath(a), P.add(focus(), 'saved', video('s1'), T));
  await ok(a, ['--only', 'youtube']);
  await ok(b, ['--only', 'youtube']);
  await ok(a, ['--only', 'youtube']);
  for (const m of [a, b]) assert.deepEqual([ids(store(m), 'saved'), ids(store(m), 'focus')], [['o1', 's1'], ['v1', 'v2', 'v3']], m.id);
});

test('an App save that lands just before the merge puts its result in place is kept beside the pulled items', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(b), P.add(focus(), 'focus', video('from-b'), T + 1));
  await ok(b, ['--only', 'youtube']);
  const early = P.add(P.emptyStore(), 'saved', video('early'), T);
  write(storePath(a), early);
  // The hook stands in for the App: once, it saves a video over the store the round already read.
  const late = join(w.root, 'late.json');
  writeFileSync(late, P.serialize(P.add(early, 'saved', video('late'), T + 2)));
  const hook = join(w.root, 'save-late');
  writeFileSync(hook, `#!/bin/sh\n[ -e ${hook}.done ] && exit 0\ntouch ${hook}.done\ncp ${late} ${storePath(a)}\n`);
  chmodSync(hook, 0o755);
  a.env.DOTS_MERGE_BEFORE_SWAP = hook;
  await ok(a, ['--only', 'youtube']);
  assert.ok(existsSync(hook + '.done'), 'the hook ran');
  assert.deepEqual([ids(store(a), 'saved'), ids(store(a), 'focus')], [['early', 'late'], ['v1', 'v2', 'v3', 'from-b']]);
});

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
const focus = () => P.addMany(P.create(P.emptyStore(), 'focus', 'Focus', T), 'focus', ['v1000000000', 'v2000000000', 'v3000000000'].map(video), T);

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
  assert.deepEqual(ids(store(b), 'focus'), ['v1000000000', 'v2000000000', 'v3000000000']);
  write(storePath(a), P.add(store(a), 'focus', video('x0000000000'), T + 10));
  write(storePath(b), P.removeItem(store(b), 'focus', 'v2000000000', T + 20));
  for (let i = 0; i < 2; i++) {
    await ok(a);
    await ok(b);
  }
  for (const m of [a, b]) {
    assert.deepEqual(ids(store(m), 'focus'), ['v1000000000', 'v3000000000', 'x0000000000'], m.id);
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
  assert.deepEqual(ids(P.parseStore(readFileSync(join(w.remote, 'dots-sync/youtube/a.json'), 'utf8')), 'focus'), ['v1000000000', 'v2000000000', 'v3000000000']);
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
  write(storePath(a), P.add(P.emptyStore(), 'saved', video('s1000000000'), T));
  let r = await sync(a, ['--only', 'youtube']);
  assert.equal(r.code, 5, r.stderr);
  assert.deepEqual([status(a).youtube.ok, status(a).youtube.error], [false, 'youtube: skipped other.json, which does not parse']);
  assert.deepEqual(ids(store(a), 'focus'), ['v1000000000', 'v2000000000', 'v3000000000']);
  // JSON of the wrong shape is skipped the same way, not a crash that holds this machine's store back.
  writeFileSync(join(w.remote, 'dots-sync/youtube/other.json'), '{"version":1,"playlists":{"x":{"id":"x","name":"X","items":null}}}');
  r = await sync(a, ['--only', 'youtube']);
  assert.equal(r.code, 5, r.stderr);
  assert.equal(status(a).youtube.error, 'youtube: skipped other.json, which does not parse');
  const pushed = P.parseStore(readFileSync(join(w.remote, 'dots-sync/youtube/a.json'), 'utf8'));
  assert.deepEqual([ids(pushed, 'focus'), ids(pushed, 'saved')], [['v1000000000', 'v2000000000', 'v3000000000'], ['s1000000000']]);
  writeFileSync(join(w.remote, 'dots-sync/youtube/other.json'), P.serialize(P.emptyStore()));
  await ok(a, ['--only', 'youtube']);
  assert.deepEqual([status(a).youtube.ok, status(a).youtube.error], [true, null]);
});

// a's clock ran far ahead when it pushed these: a rename and a removal that would outvote every later edit.
const ahead = () => P.removeItem(P.rename(focus(), 'focus', 'Forged', FAR), 'focus', 'v1000000000', FAR);

test('a pulled Playlist or item stamped more than a day ahead is left out, and the unit says so', async () => {
  const w = world();
  const b = machine(w, 'b');
  const pulled = P.add(ahead(), 'saved', video('s1000000000'), T);
  write(join(w.remote, 'dots-sync/youtube/a.json'), pulled);
  write(storePath(b), P.add(P.emptyStore(), 'saved', video('s2000000000'), T));
  const r = await sync(b, ['--only', 'youtube']);
  assert.equal(r.code, 5, r.stderr);
  assert.match(r.stderr, /^dots sync: youtube: left out 1 record from a\.json, stamped more than a day ahead$/m);
  // The Playlist stamped ahead goes with its items; Saved, stamped right, still merges.
  assert.deepEqual(P.playlists(store(b)), []);
  assert.deepEqual(ids(store(b), 'saved'), ['s1000000000', 's2000000000']);
});

test('a machine re-stamps its own Playlists and items stamped ahead to now, so they travel again', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(a), ahead());
  const t0 = Date.now();
  const r = await ok(a, ['--only', 'youtube']);
  assert.match(r.stderr, /^youtube: re-stamped 2 records stamped more than a day ahead$/m);
  const f = store(a).playlists.focus;
  for (const t of [f.updatedAt, f.nameAt, f.items.v1000000000.updatedAt]) assert.ok(t >= t0 && t <= Date.now(), `stamp ${t}`);
  await ok(b, ['--only', 'youtube']);
  assert.deepEqual([P.playlists(store(b)).map((l) => l.name), ids(store(b), 'focus')], [['Forged'], ['v2000000000', 'v3000000000']]);
});

test('a store from before Playlists merges with a new one without losing a video', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  const old = '{"version":1,"playlists":{"saved":{"id":"saved","name":"Saved","updatedAt":5,"items":{"o1000000000":{"id":"o1000000000","title":"T","channel":"C","duration":9,"thumb":"o1000000000","pos":1,"updatedAt":5}}}}}';
  mkdirSync(dirname(storePath(b)), { recursive: true });
  writeFileSync(storePath(b), old);
  write(storePath(a), P.add(focus(), 'saved', video('s1000000000'), T));
  await ok(a, ['--only', 'youtube']);
  await ok(b, ['--only', 'youtube']);
  await ok(a, ['--only', 'youtube']);
  for (const m of [a, b]) assert.deepEqual([ids(store(m), 'saved'), ids(store(m), 'focus')], [['o1000000000', 's1000000000'], ['v1000000000', 'v2000000000', 'v3000000000']], m.id);
});

test('an App save that lands just before the merge puts its result in place is kept beside the pulled items', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(b), P.add(focus(), 'focus', video('from-b00000'), T + 1));
  await ok(b, ['--only', 'youtube']);
  const early = P.add(P.emptyStore(), 'saved', video('early000000'), T);
  write(storePath(a), early);
  // The hook stands in for the App: once, it saves a video over the store the round already read.
  const late = join(w.root, 'late.json');
  writeFileSync(late, P.serialize(P.add(early, 'saved', video('late0000000'), T + 2)));
  const hook = join(w.root, 'save-late');
  writeFileSync(hook, `#!/bin/sh\n[ -e ${hook}.done ] && exit 0\ntouch ${hook}.done\ncp ${late} ${storePath(a)}\n`);
  chmodSync(hook, 0o755);
  a.env.DOTS_MERGE_BEFORE_SWAP = hook;
  await ok(a, ['--only', 'youtube']);
  assert.ok(existsSync(hook + '.done'), 'the hook ran');
  assert.deepEqual([ids(store(a), 'saved'), ids(store(a), 'focus')], [['early000000', 'late0000000'], ['v1000000000', 'v2000000000', 'v3000000000', 'from-b00000']]);
});

test('three App saves caught one after another all land beside the pulled items', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(b), P.add(focus(), 'focus', video('from-b00000'), T + 1));
  await ok(b, ['--only', 'youtube']);
  const early = P.add(P.emptyStore(), 'saved', video('early000000'), T);
  write(storePath(a), early);
  // The hook stands in for the App, which saves its whole store: its nth run copies late<n>.json, holding one more video each time, and after three it does nothing.
  for (let i = 1, s = early; i <= 3; i++) writeFileSync(join(w.root, `late${i}.json`), P.serialize((s = P.add(s, 'saved', video('late' + i + '000000'), T + 1 + i))));
  const hook = join(w.root, 'save-late');
  writeFileSync(hook, `#!/bin/sh\nn=$(( $(cat ${hook}.n 2>/dev/null || echo 0) + 1 ))\necho $n > ${hook}.n\n[ -e ${w.root}/late$n.json ] || exit 0\ncp ${w.root}/late$n.json ${storePath(a)}\n`);
  chmodSync(hook, 0o755);
  a.env.DOTS_MERGE_BEFORE_SWAP = hook;
  await ok(a, ['--only', 'youtube']);
  assert.deepEqual([ids(store(a), 'saved'), ids(store(a), 'focus')], [['early000000', 'late1000000', 'late2000000', 'late3000000'], ['v1000000000', 'v2000000000', 'v3000000000', 'from-b00000']]);
});

// A Playlist made while a's clock ran ahead carries that time as when it was made, which also stands for when it was named.
test('a Playlist made while the clock ran ahead is re-stamped whole, so a later rename and add on b win on both and both rounds settle', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(a), P.add(P.create(P.emptyStore(), 'gym', 'Gym', FAR), 'gym', video('g1000000000'), FAR));
  await ok(a, ['--only', 'youtube']);
  await ok(b, ['--only', 'youtube']);
  write(storePath(b), P.add(P.rename(store(b), 'gym', 'Lifting', Date.now()), 'gym', video('g2000000000'), Date.now()));
  for (let i = 0; i < 2; i++) {
    await ok(b, ['--only', 'youtube']);
    await ok(a, ['--only', 'youtube']);
  }
  for (const m of [a, b]) {
    assert.deepEqual([P.playlists(store(m)).map((l) => l.name), ids(store(m), 'gym')], [['Lifting'], ['g1000000000', 'g2000000000']], m.id);
    assert.ok(store(m).playlists.gym.createdAt <= Date.now(), m.id);
  }
});

// The App draws only rows whose id is a video id, so a pulled item with any other id would be counted in its Playlist but never drawn.
test('a pulled item whose id is not a video id is left out, and the unit says so', async () => {
  const w = world();
  const b = machine(w, 'b');
  const pulled = JSON.parse(P.serialize(focus()));
  pulled.playlists.focus.items['../x'] = Object.assign(video('../x'), { pos: 9, addedAt: T, updatedAt: T, deleted: false });
  pulled.playlists.focus.items['v2000000000'].id = 'v9000000000';
  write(join(w.remote, 'dots-sync/youtube/a.json'), pulled);
  const r = await sync(b, ['--only', 'youtube']);
  assert.equal(r.code, 5, r.stderr);
  assert.match(r.stderr, /^dots sync: youtube: left out 2 records from a\.json, which are not videos$/m);
  assert.deepEqual(ids(store(b), 'focus'), ['v1000000000', 'v3000000000']);
});

test('a pulled item with no stamp merges as stamped long ago, not as ahead', async () => {
  const w = world();
  const b = machine(w, 'b');
  const pulled = JSON.parse(P.serialize(focus()));
  delete pulled.playlists.focus.items['v1000000000'].updatedAt;
  write(join(w.remote, 'dots-sync/youtube/a.json'), pulled);
  await ok(b, ['--only', 'youtube']);
  assert.deepEqual(ids(store(b), 'focus'), ['v1000000000', 'v2000000000', 'v3000000000']);
});

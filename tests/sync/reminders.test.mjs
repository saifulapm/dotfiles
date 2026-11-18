// Machines a, b and c sync reminders through one local alias remote.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import * as R from '../../shell/lib/reminders.mjs';
import { machine, sync, world } from './lib.mjs';

const T = 1760000000000;
const MIN = 60000;

const write = (path, store) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(store));
};
const storePath = (m) => join(m.data, 'reminders', m.id + '.json');
const store = (m) => R.parseStore(readFileSync(storePath(m), 'utf8'));
const status = (m) => JSON.parse(readFileSync(m.status, 'utf8'));
const set = (s, q, now) => R.setReminder(s, R.parseReminder(q, now), now).store;

async function ok(m, args) {
  const r = await sync(m, args);
  assert.equal(r.code, 0, `dots sync on ${m.id} exited ${r.code}: ${r.stdout}${r.stderr}`);
  return r;
}

test('a round on a machine with no store succeeds and records the reminders unit', async () => {
  const w = world();
  const a = machine(w, 'a');
  await ok(a, ['--only', 'reminders']);
  assert.equal(status(a).reminders.ok, true);
});

test('a reminder set on a reaches b, pending, with the same id and due', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  const s = set(R.emptyStore(), '20m tea', T);
  write(storePath(a), s);
  await ok(a);
  await ok(b);
  const got = R.pendingList(store(b));
  assert.deepEqual(got, [{ id: s.reminders[0].id, text: 'tea', due: T + 20 * MIN, created: T }]);
});

test('a reminder removed on a is ended and no longer pending on b', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  const s = set(R.emptyStore(), '20m tea', T);
  write(storePath(a), s);
  await ok(a);
  await ok(b);
  write(storePath(a), R.endReminder(s, s.reminders[0].id, 'removed', T + 1));
  await ok(a);
  await ok(b);
  assert.equal(store(b).reminders[0].ended, 'removed');
  assert.deepEqual(R.pendingList(store(b)), []);
});

test('reminders each machine added offline are both pending on both after a, b, a', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(a), set(R.emptyStore(), '20m tea', T));
  write(storePath(b), set(R.emptyStore(), '30m walk', T + 1));
  await ok(a);
  await ok(b);
  await ok(a);
  assert.deepEqual(R.pendingList(store(a)).map((r) => r.text), ['tea', 'walk']);
  assert.deepEqual(R.pendingList(store(b)).map((r) => r.text), ['tea', 'walk']);
});

test('a pulled record with no text is left out and named, while the valid one merges and this machine still pushes', async () => {
  const w = world();
  const b = machine(w, 'b');
  const good = set(R.emptyStore(), '20m tea', T);
  const bad = Object.assign({}, good.reminders[0], { id: 'bad', text: '' });
  write(join(w.remote, 'dots-sync/reminders/c.json'), { version: 1, reminders: [bad, good.reminders[0]] });
  write(storePath(b), set(R.emptyStore(), '30m walk', T + 1));
  const r = await sync(b, ['--only', 'reminders']);
  assert.equal(r.code, 5);
  assert.match(r.stderr, /c\.json/);
  const s = status(b).reminders;
  assert.deepEqual([s.ok, s.error], [false, 'reminders: left out 1 record from c.json, with no text or a due no clock holds']);
  assert.deepEqual(R.pendingList(store(b)).map((x) => x.text), ['tea', 'walk']);
  assert.ok(!store(b).reminders.some((x) => x.id === 'bad'));
  assert.ok(existsSync(join(w.remote, 'dots-sync/reminders/b.json')));
});

test('a shell save that lands just before the merge puts its result in place is kept beside the pulled reminder', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(storePath(b), set(R.emptyStore(), '20m from b', T));
  await ok(b);
  const early = set(R.emptyStore(), '10m early', T);
  write(storePath(a), early);
  // The hook stands in for the shell: once, it saves a reminder over the store the round already read.
  const late = join(w.root, 'late.json');
  writeFileSync(late, JSON.stringify(set(early, '15m late save', T + 1)));
  const hook = join(w.root, 'save-late');
  writeFileSync(hook, `#!/bin/sh\n[ -e ${hook}.done ] && exit 0\ntouch ${hook}.done\ncp ${late} ${storePath(a)}\n`);
  chmodSync(hook, 0o755);
  a.env.DOTS_MERGE_BEFORE_SWAP = hook;
  await ok(a, ['--only', 'reminders']);
  assert.ok(existsSync(hook + '.done'), 'the hook ran');
  assert.deepEqual(R.pendingList(store(a)).map((r) => r.text).sort(), ['early', 'from b', 'late save']);
});

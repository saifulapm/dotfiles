// Two machines, a and b, sync notes and goals through one local alias remote.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import * as G from '../../shell/lib/goals.mjs';
import * as N from '../../shell/lib/notes.mjs';
import { holdLock, machine, sync, world } from './lib.mjs';

const T = 1760000000000;
const SHA = 'ab'.repeat(32);

const write = (path, store) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(store));
};
const notesPath = (m) => join(m.data, 'notes', m.id + '.json');
const goalsPath = (m) => join(m.data, 'goals', m.id + '.json');
const notes = (m) => N.parseStore(readFileSync(notesPath(m), 'utf8'));
const goals = (m) => G.parseStore(readFileSync(goalsPath(m), 'utf8'));
const status = (m) => JSON.parse(readFileSync(m.status, 'utf8'));
const withN1 = (text) => N.compose(N.emptyStore(), text, T, 'n1');

async function ok(m, args) {
  const r = await sync(m, args);
  assert.equal(r.code, 0, `dots sync on ${m.id} exited ${r.code}: ${r.stdout}${r.stderr}`);
  return r;
}

test('a goal added on a reaches b after a then b sync', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(goalsPath(a), G.addGoal(G.emptyStore(), 'X', null, T, 'g1'));
  await ok(a);
  await ok(b);
  assert.deepEqual(G.activeGoals(goals(b)).map((g) => g.title), ['X']);
});

test('a machine that lost its local store gets its own goals back from the remote', async () => {
  const w = world();
  const a = machine(w, 'a');
  write(goalsPath(a), G.addGoal(G.emptyStore(), 'only on a', null, T, 'g1'));
  await ok(a);
  // A reinstall under the same machine id starts with no store.
  renameSync(goalsPath(a), goalsPath(a) + '.gone');
  await ok(a);
  assert.deepEqual(G.activeGoals(goals(a)).map((g) => g.title), ['only on a']);
});

test('a pulled goal or note stamped more than a day ahead is left out, so it cannot outvote every later edit, and the unit says so', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  const FAR = 9999999999999;
  const forged = G.editGoal(G.addGoal(G.emptyStore(), 'mine', null, T, 'g1'), 'g1', 'forged', null, FAR);
  write(goalsPath(a), forged);
  write(notesPath(a), N.deleteNotes(withN1('kept'), ['n1'], FAR));
  write(goalsPath(b), G.addGoal(G.emptyStore(), 'mine', null, T, 'g1'));
  write(notesPath(b), withN1('kept'));
  await ok(a);
  const r = await sync(b);
  assert.equal(r.code, 5, r.stderr);
  assert.match(r.stderr, /^dots sync: goals: left out 1 record from a\.json, stamped more than a day ahead$/m);
  assert.match(r.stderr, /^dots sync: notes: left out 1 record from a\.json, stamped more than a day ahead$/m);
  assert.deepEqual(G.activeGoals(goals(b)).map((g) => g.title), ['mine']);
  assert.deepEqual(N.sectionNotes(notes(b), 'inbox').map((n) => n.text), ['kept']);
  assert.equal(status(b).goals.error, 'goals: left out 1 record from a.json, stamped more than a day ahead');
});

test('a note edited on both machines offline ends with the later edit on both', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(notesPath(a), N.editNote(withN1('first'), 'n1', 'edit on a', T + 1));
  write(notesPath(b), N.editNote(withN1('first'), 'n1', 'edit on b', T + 2));
  await ok(a);
  await ok(b);
  await ok(a);
  for (const m of [a, b]) {
    const n1 = notes(m).notes.find((n) => n.id === 'n1');
    assert.deepEqual([n1.text, n1.updatedAt], ['edit on b', T + 2], m.id);
  }
});

test('a note deleted on a is gone on b after both sync, and stays gone a round later', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(notesPath(a), N.deleteNotes(withN1('doomed'), ['n1'], T + 5));
  write(notesPath(b), withN1('doomed'));
  await ok(a);
  await ok(b);
  assert.deepEqual(N.sectionNotes(notes(b), 'inbox'), []);
  await ok(a);
  await ok(b);
  assert.deepEqual(N.sectionNotes(notes(b), 'inbox'), []);
  assert.deepEqual(N.sectionNotes(notes(a), 'inbox'), []);
});

test('an attachment added on a lands on b under the same sha256 name', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  const att = { sha256: SHA, name: 'shot.png', mime: 'image/png', size: 5 };
  write(notesPath(a), N.attachTo(N.emptyStore(), null, [att], T, 'n1'));
  mkdirSync(join(a.data, 'notes/attachments'), { recursive: true });
  writeFileSync(join(a.data, 'notes/attachments', SHA + '.png'), 'bytes');
  await ok(a);
  await ok(b);
  assert.equal(readFileSync(join(b.data, 'notes/attachments', SHA + '.png'), 'utf8'), 'bytes');
});

test('each machine writes only its own remote file, and the remote holds only a.json and b.json', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(notesPath(a), withN1('from a'));
  write(notesPath(b), N.compose(N.emptyStore(), 'from b', T, 'n2'));
  write(goalsPath(a), G.addGoal(G.emptyStore(), 'X', null, T, 'g1'));
  write(goalsPath(b), G.addGoal(G.emptyStore(), 'Y', null, T, 'g2'));
  const remote = (unit, file) => readFileSync(join(w.remote, 'dots-sync', unit, file));
  await ok(a);
  const aFiles = ['notes', 'goals'].map((u) => remote(u, 'a.json'));
  await ok(b);
  assert.deepEqual(['notes', 'goals'].map((u) => remote(u, 'a.json')), aFiles);
  const bFiles = ['notes', 'goals'].map((u) => remote(u, 'b.json'));
  await ok(a);
  assert.deepEqual(['notes', 'goals'].map((u) => remote(u, 'b.json')), bFiles);
  assert.deepEqual(readdirSync(join(w.remote, 'dots-sync/notes')).sort(), ['a.json', 'attachments', 'b.json']);
  assert.deepEqual(readdirSync(join(w.remote, 'dots-sync/goals')).sort(), ['a.json', 'b.json']);
});

test('a round that brings nothing new leaves the local stores unwritten, so a path unit on them stays quiet', async () => {
  const w = world();
  const a = machine(w, 'a');
  write(notesPath(a), N.compose(withN1('one'), 'two', T, 'm0'));
  write(goalsPath(a), G.addGoal(G.addGoal(G.emptyStore(), 'Z', null, T, 'gz'), 'A', null, T, 'ga'));
  const mtimes = () => [notesPath(a), goalsPath(a)].map((p) => statSync(p).mtimeMs);
  const before = mtimes();
  await ok(a);
  await ok(a);
  assert.deepEqual(mtimes(), before);
});

test('an unreachable remote marks notes and goals failed, and the next good round clears them', async () => {
  const w = world();
  const a = machine(w, 'a');
  renameSync(w.remote, w.remote + '.away');
  const r = await sync(a);
  assert.notEqual(r.code, 0);
  for (const unit of ['notes', 'goals']) {
    const s = status(a)[unit];
    assert.equal(s.ok, false, unit);
    assert.equal(s.lastOk, null, unit);
    assert.match(s.error, /directory not found/, unit);
  }
  renameSync(w.remote + '.away', w.remote);
  await ok(a);
  for (const unit of ['notes', 'goals']) {
    const s = status(a)[unit];
    assert.deepEqual([s.ok, s.error, s.lastOk], [true, null, s.lastRun], unit);
  }
});

test('--only goals runs the goals unit alone and keeps the notes entry', async () => {
  const w = world();
  const a = machine(w, 'a');
  await ok(a);
  const before = status(a).notes;
  await ok(a, ['--only', 'goals']);
  assert.deepEqual(status(a).notes, before);
  assert.ok(status(a).goals.lastRun >= before.lastRun);
});

test('two rounds started together run once, and the other says already running', async () => {
  const w = world();
  const a = machine(w, 'a', { slow: true });
  const runs = await Promise.all([sync(a), sync(a)]);
  assert.deepEqual(runs.map((r) => r.code), [0, 0]);
  assert.deepEqual(runs.map((r) => r.stdout.trim() === 'already running').sort(), [false, true]);
  assert.equal(status(a).goals.ok, true);
});

test('a pulled goals file that does not parse marks the unit failed, while the files that parse still merge and this machine still pushes', async () => {
  const w = world();
  const [a, c] = [machine(w, 'a'), machine(w, 'c')];
  write(goalsPath(c), G.addGoal(G.emptyStore(), 'From c', null, T, 'gc'));
  await ok(c);
  writeFileSync(join(w.remote, 'dots-sync/goals/other.json'), '{"goals":');
  write(goalsPath(a), G.addGoal(G.emptyStore(), 'From a', null, T, 'ga'));
  const r = await sync(a);
  assert.notEqual(r.code, 0);
  const s = status(a).goals;
  assert.deepEqual([s.ok, s.error], [false, 'goals: skipped other.json, which does not parse']);
  assert.deepEqual(G.activeGoals(goals(a)).map((g) => g.title).sort(), ['From a', 'From c']);
  const pushed = G.parseStore(readFileSync(join(w.remote, 'dots-sync/goals/a.json'), 'utf8'));
  assert.deepEqual(G.activeGoals(pushed).map((g) => g.title).sort(), ['From a', 'From c']);
  assert.equal(status(a).notes.ok, true);
});

test('a shell save that lands just before the merge puts its result in place is kept beside the pulled goals', async () => {
  const w = world();
  const [a, b] = [machine(w, 'a'), machine(w, 'b')];
  write(goalsPath(b), G.addGoal(G.emptyStore(), 'From b', null, T, 'gb'));
  await ok(b);
  const early = G.addGoal(G.emptyStore(), 'Early', null, T, 'ga');
  write(goalsPath(a), early);
  // The hook stands in for the shell: once, it saves a goal over the store the round already read.
  const late = join(w.root, 'late.json');
  writeFileSync(late, JSON.stringify(G.addGoal(early, 'Late save', null, T + 1, 'gl')));
  const hook = join(w.root, 'save-late');
  writeFileSync(hook, `#!/bin/sh\n[ -e ${hook}.done ] && exit 0\ntouch ${hook}.done\ncp ${late} ${goalsPath(a)}\n`);
  chmodSync(hook, 0o755);
  a.env.DOTS_MERGE_BEFORE_SWAP = hook;
  await ok(a, ['--only', 'goals']);
  assert.ok(existsSync(hook + '.done'), 'the hook ran');
  assert.deepEqual(G.activeGoals(goals(a)).map((g) => g.title).sort(), ['Early', 'From b', 'Late save']);
});

test('a notes file from another machine that does not parse still lets attachments travel, and names its unit once', async () => {
  const w = world();
  const a = machine(w, 'a');
  await ok(a);
  writeFileSync(join(w.remote, 'dots-sync/notes/other.json'), '{"notes":');
  const att = { sha256: SHA, name: 'shot.png', mime: 'image/png', size: 5 };
  write(notesPath(a), N.attachTo(N.emptyStore(), null, [att], T, 'n1'));
  mkdirSync(join(a.data, 'notes/attachments'), { recursive: true });
  writeFileSync(join(a.data, 'notes/attachments', SHA + '.png'), 'bytes');
  const r = await sync(a, ['--only', 'notes']);
  assert.notEqual(r.code, 0);
  assert.equal(readFileSync(join(w.remote, 'dots-sync/notes/attachments', SHA + '.png'), 'utf8'), 'bytes');
  assert.match(r.stderr, /^dots sync: notes: skipped other\.json, which does not parse$/m);
  assert.doesNotMatch(r.stderr, /notes: notes:/);
});

// A store change starts a --only round from its path unit; one that met a running round used to wait 15 min for the timer.
test('a --only goals round that meets the lock waits for it, then pushes the goal saved before it started', async () => {
  const w = world();
  const a = machine(w, 'a');
  write(goalsPath(a), G.addGoal(G.emptyStore(), 'Late', null, T, 'g1'));
  const lock = await holdLock(a, 3);
  const t0 = Date.now();
  const r = await ok(a, ['--only', 'goals']);
  await lock.freed;
  assert.ok(Date.now() - t0 >= 2500, `it ran after ${Date.now() - t0} ms, before the lock was let go`);
  assert.doesNotMatch(r.stdout, /already running/);
  const remote = G.parseStore(readFileSync(join(w.remote, 'dots-sync/goals/a.json'), 'utf8'));
  assert.deepEqual(G.activeGoals(remote).map((g) => g.title), ['Late']);
});

test('a full round that meets the lock still says already running and exits at once', async () => {
  const w = world();
  const a = machine(w, 'a');
  const lock = await holdLock(a, 3);
  const t0 = Date.now();
  const r = await ok(a);
  assert.ok(Date.now() - t0 < 1000, `it took ${Date.now() - t0} ms`);
  assert.equal(r.stdout.trim(), 'already running');
  await lock.freed;
});

test('with no Dropbox remote set up, dots sync skips with exit 0 and records no failure', async () => {
  const w = world();
  const conf = join(w.root, 'empty.conf');
  writeFileSync(conf, '');
  const a = machine(w, 'a', { conf });
  const r = await ok(a);
  assert.equal(r.stdout.trim().split('\n').length, 1);
  assert.match(r.stdout, /skipped/);
  const s = existsSync(a.status) ? status(a) : {};
  assert.deepEqual(Object.keys(s).filter((u) => s[u].ok === false), []);
});

// Two machines, a and b, sync notes and goals through one local alias remote.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import * as G from '../../shell/lib/goals.mjs';
import * as N from '../../shell/lib/notes.mjs';
import { machine, sync, world } from './lib.mjs';

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

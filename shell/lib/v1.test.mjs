import { test } from 'node:test';
import assert from 'node:assert/strict';
import { notesFromV1, goalsFromV1 } from './v1.mjs';
import * as notes from './notes.mjs';
import * as goals from './goals.mjs';

const ms = (iso) => Date.parse(iso);
const png = { sha256: 'a'.repeat(64), name: 'paste-1.png', mime: 'image/png', size: 3 };

const v1Notes = JSON.stringify({
  version: 2,
  notes: [
    { id: '0mt0a0001-aaaa', text: 'first note', path: '', done: false, updatedAt: '2026-09-04T00:00:00.000Z' },
    { id: '0mt0a0002-aaaa', text: '', path: '/v1/notes/attachments/paste-1.png', done: false, updatedAt: '2026-09-29T00:00:00.000Z' },
    { id: '0mt0a0003-aaaa', text: '', path: '', done: false, updatedAt: '2026-09-30T00:00:00.000Z', deletedAt: '2026-09-30T00:00:00.000Z' },
    { id: '0mt0a0004-aaaa', text: 'ticked', path: '', done: true, updatedAt: '2026-09-26T00:00:00.000Z' },
  ],
});

test('v1 notes become a v2 store the notes model reads, in the inbox, created when their id says', () => {
  const s = notes.parseStore(JSON.stringify(notesFromV1(v1Notes, (path) => (path === '/v1/notes/attachments/paste-1.png' ? png : null))));
  assert.ok(s);
  const n = s.notes.find((x) => x.id === '0mt0a0001-aaaa');
  assert.deepEqual(n, { id: '0mt0a0001-aaaa', section: 'inbox', text: 'first note', attachments: [], todo: false, done: false, tags: [], createdAt: parseInt('0mt0a0001', 36), updatedAt: ms('2026-09-04T00:00:00.000Z') });
  assert.deepEqual(s.notes.find((x) => x.id === '0mt0a0002-aaaa').attachments, [png]);
  assert.deepEqual(notes.sectionNotes(s, 'inbox').map((x) => x.id).sort(), ['0mt0a0001-aaaa', '0mt0a0002-aaaa', '0mt0a0004-aaaa']);
});

test('a ticked v1 note is a done todo', () => {
  const n = notesFromV1(v1Notes, () => null).notes.find((x) => x.id === '0mt0a0004-aaaa');
  assert.equal(n.todo, true);
  assert.equal(n.done, true);
});

test('a deleted v1 note stays a tombstone, so a later import from a machine that still has it live cannot bring it back', () => {
  const t = notesFromV1(v1Notes, () => null).notes.find((x) => x.id === '0mt0a0003-aaaa');
  assert.equal(t.deleted, true);
  assert.equal(t.updatedAt, ms('2026-09-30T00:00:00.000Z'));
  const live = notes.parseStore(JSON.stringify(Object.assign(notes.emptyStore(), { notes: [{ id: '0mt0a0003-aaaa', section: 'inbox', text: 'old', updatedAt: ms('2026-09-01T00:00:00Z') }] })));
  const merged = notes.mergeStores(live, notes.parseStore(JSON.stringify(notesFromV1(v1Notes, () => null))));
  assert.equal(merged.notes.find((x) => x.id === '0mt0a0003-aaaa').deleted, true);
});

test('a note whose file cannot come keeps the path as its text, so it never arrives blank', () => {
  const n = notesFromV1(v1Notes, () => null).notes.find((x) => x.id === '0mt0a0002-aaaa');
  assert.deepEqual(n.attachments, []);
  assert.equal(n.text, '/v1/notes/attachments/paste-1.png');
});

test('the same v1 file always converts to the same store, so importing twice writes nothing new', () => {
  assert.equal(JSON.stringify(notesFromV1(v1Notes, () => png)), JSON.stringify(notesFromV1(v1Notes, () => png)));
  assert.equal(JSON.stringify(goalsFromV1(v1Goals)), JSON.stringify(goalsFromV1(v1Goals)));
});

test('a v1 file that is not a notes or goals store converts to null', () => {
  for (const t of ['', '{', '[]', '{"version":2}', '{"notes":{}}']) assert.equal(notesFromV1(t, () => null), null);
  for (const t of ['', '{', '{"goals":3}']) assert.equal(goalsFromV1(t), null);
});

const v1Goals = JSON.stringify({
  version: 1,
  goals: [
    {
      id: 'g1',
      name: 'Ship app',
      due: '2026-09-22T00:00:00.000Z',
      state: 'shipped',
      tasks: [
        { id: 't1', text: 'a', done: true, updatedAt: '2026-09-21T00:00:00.000Z' },
        { id: 't2', text: 'b', done: false, updatedAt: '2026-09-25T00:00:00.000Z' },
      ],
      createdAt: '2026-09-10T00:00:00.000Z',
      updatedAt: '2026-09-26T12:00:00.000Z',
      shippedAt: '2026-09-26T12:00:00.000Z',
    },
    { id: 'g2', name: 'Next app', due: '2026-10-30T00:00:00.000Z', state: 'active', tasks: [], createdAt: '2026-10-01T00:00:00.000Z', updatedAt: '2026-10-02T00:00:00.000Z' },
    { id: 'g3', name: 'Later', due: '', state: 'queued', tasks: [], createdAt: '2026-10-01T00:00:00.000Z', updatedAt: '2026-10-03T00:00:00.000Z' },
    { id: 'g4', name: '', due: '', state: '', tasks: [], createdAt: '2026-10-01T00:00:00.000Z', updatedAt: '2026-10-04T00:00:00.000Z', deletedAt: '2026-10-04T00:00:00.000Z' },
  ],
});

test('a shipped v1 goal is done at its ship time, keeping its deadline and tasks', () => {
  const s = goals.parseStore(JSON.stringify(goalsFromV1(v1Goals)));
  assert.ok(s);
  const g = s.goals.find((x) => x.id === 'g1');
  assert.deepEqual(g, {
    id: 'g1',
    title: 'Ship app',
    deadline: ms('2026-09-22T00:00:00.000Z'),
    order: 0,
    done: true,
    doneAt: ms('2026-09-26T12:00:00.000Z'),
    updatedAt: ms('2026-09-26T12:00:00.000Z'),
    deleted: false,
    tasks: [
      { id: 't1', text: 'a', done: true, order: 0, updatedAt: ms('2026-09-21T00:00:00.000Z'), deleted: false },
      { id: 't2', text: 'b', done: false, order: 1, updatedAt: ms('2026-09-25T00:00:00.000Z'), deleted: false },
    ],
  });
});

test('active and queued v1 goals are active, one without a due date has no deadline, and a deleted one stays deleted', () => {
  const s = goals.parseStore(JSON.stringify(goalsFromV1(v1Goals)));
  assert.deepEqual(goals.activeGoals(s).map((g) => g.id), ['g2', 'g3']);
  assert.equal(s.goals.find((g) => g.id === 'g3').deadline, null);
  const gone = s.goals.find((g) => g.id === 'g4');
  assert.equal(gone.deleted, true);
  assert.equal(gone.updatedAt, ms('2026-10-04T00:00:00.000Z'));
});

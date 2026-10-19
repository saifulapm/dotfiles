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
    { id: '0mtmhm85a-xdie', text: 'cli setup', path: '', done: false, updatedAt: '2026-09-04T05:02:24.190Z' },
    { id: '0mun8kh5q-88yi', text: '', path: '/v1/notes/attachments/paste-1.png', done: false, updatedAt: '2026-09-29T22:16:34.526Z' },
    { id: '0mteaikqo-mp7z', text: '', path: '', done: false, updatedAt: '2026-09-30T20:09:46.423Z', deletedAt: '2026-09-30T20:09:46.423Z' },
    { id: '0mtqvousn-jtbs', text: 'ticked', path: '', done: true, updatedAt: '2026-09-26T11:06:41.801Z' },
  ],
});

test('v1 notes become a v2 store the notes model reads, in the inbox, created when their id says', () => {
  const s = notes.parseStore(JSON.stringify(notesFromV1(v1Notes, (path) => (path === '/v1/notes/attachments/paste-1.png' ? png : null))));
  assert.ok(s);
  const n = s.notes.find((x) => x.id === '0mtmhm85a-xdie');
  assert.deepEqual(n, { id: '0mtmhm85a-xdie', section: 'inbox', text: 'cli setup', attachments: [], todo: false, done: false, tags: [], createdAt: parseInt('0mtmhm85a', 36), updatedAt: ms('2026-09-04T05:02:24.190Z') });
  assert.deepEqual(s.notes.find((x) => x.id === '0mun8kh5q-88yi').attachments, [png]);
  assert.deepEqual(notes.sectionNotes(s, 'inbox').map((x) => x.id).sort(), ['0mtmhm85a-xdie', '0mtqvousn-jtbs', '0mun8kh5q-88yi']);
});

test('a ticked v1 note is a done todo', () => {
  const n = notesFromV1(v1Notes, () => null).notes.find((x) => x.id === '0mtqvousn-jtbs');
  assert.equal(n.todo, true);
  assert.equal(n.done, true);
});

test('a deleted v1 note stays a tombstone, so a later import from a machine that still has it live cannot bring it back', () => {
  const t = notesFromV1(v1Notes, () => null).notes.find((x) => x.id === '0mteaikqo-mp7z');
  assert.equal(t.deleted, true);
  assert.equal(t.updatedAt, ms('2026-09-30T20:09:46.423Z'));
  const live = notes.parseStore(JSON.stringify(Object.assign(notes.emptyStore(), { notes: [{ id: '0mteaikqo-mp7z', section: 'inbox', text: 'old', updatedAt: ms('2026-09-01T00:00:00Z') }] })));
  const merged = notes.mergeStores(live, notes.parseStore(JSON.stringify(notesFromV1(v1Notes, () => null))));
  assert.equal(merged.notes.find((x) => x.id === '0mteaikqo-mp7z').deleted, true);
});

test('an attachment whose file is gone leaves its note without one', () => {
  assert.deepEqual(notesFromV1(v1Notes, () => null).notes.find((x) => x.id === '0mun8kh5q-88yi').attachments, []);
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
      name: 'SplitRoute',
      due: '2026-09-22T15:58:58.547Z',
      state: 'shipped',
      tasks: [
        { id: 't1', text: 'Overrides', done: true, updatedAt: '2026-09-22T03:59:23.008Z' },
        { id: 't2', text: 'Submit', done: false, updatedAt: '2026-09-26T10:32:02.942Z' },
      ],
      createdAt: '2026-09-10T11:44:57.460Z',
      updatedAt: '2026-09-26T10:32:04.402Z',
      shippedAt: '2026-09-26T10:32:04.402Z',
    },
    { id: 'g2', name: 'ShortCart', due: '2026-10-30T00:00:00.000Z', state: 'active', tasks: [], createdAt: '2026-10-01T00:00:00.000Z', updatedAt: '2026-10-02T00:00:00.000Z' },
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
    title: 'SplitRoute',
    deadline: ms('2026-09-22T15:58:58.547Z'),
    order: 0,
    done: true,
    doneAt: ms('2026-09-26T10:32:04.402Z'),
    updatedAt: ms('2026-09-26T10:32:04.402Z'),
    deleted: false,
    tasks: [
      { id: 't1', text: 'Overrides', done: true, order: 0, updatedAt: ms('2026-09-22T03:59:23.008Z'), deleted: false },
      { id: 't2', text: 'Submit', done: false, order: 1, updatedAt: ms('2026-09-26T10:32:02.942Z'), deleted: false },
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

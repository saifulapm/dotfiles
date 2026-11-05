import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as G from './goals.mjs';
import { rows, blocks, findRow } from './goals-view.mjs';

const now = new Date(2026, 9, 19, 0, 0).getTime();
let store = G.emptyStore();
store = G.addGoal(store, 'Ship v2', new Date(2026, 9, 21, 23, 59).getTime(), now, 'a');
store = G.addGoal(store, 'Read', null, now, 'b');
store = G.addGoal(store, 'Old', null, now, 'c');
store = G.addTask(store, 'b', 'ch 1', now, 't1');
store = G.addTask(store, 'b', 'ch 2', now, 't2');
store = G.toggleTask(store, 'b', 't1', now);
store = G.toggleGoal(store, 'c', now);

test('active goals list in order, an unfolded goal shows its tasks, and the done group folds', () => {
  assert.deepEqual(rows(store, { b: true }, false, now), [
    { kind: 'goal', id: 'a', goal: 'a', text: 'Ship v2', done: false, count: '0/0', due: '3d · Wed 21 Oct' },
    { kind: 'goal', id: 'b', goal: 'b', text: 'Read', done: false, count: '1/2', due: 'no deadline' },
    { kind: 'task', id: 't1', goal: 'b', text: 'ch 1', done: true },
    { kind: 'task', id: 't2', goal: 'b', text: 'ch 2', done: false },
    { kind: 'done', id: 'done', goal: '', text: 'done · 1' },
  ]);
});

test('an unfolded done group lists the done goals, and a past deadline reads late', () => {
  const late = G.addGoal(G.emptyStore(), 'Tax', now - 60000, now - 120000, 'x');
  assert.deepEqual(rows(G.toggleGoal(late, 'x', now), {}, true, now), [
    { kind: 'done', id: 'done', goal: '', text: 'done · 1' },
    { kind: 'goal', id: 'x', goal: 'x', text: 'Tax', done: true, count: '0/0', due: 'late · Sun 18 Oct' },
  ]);
});

test('an empty store has no rows', () => {
  assert.deepEqual(rows(G.emptyStore(), {}, false, now), []);
});

test('blocks group each goal with the tasks under it, by row index', () => {
  const list = rows(store, { b: true }, false, now);
  assert.deepEqual(
    blocks(list).map((b) => [b.row, b.tasks.map((t) => t.row)]),
    [
      [0, []],
      [1, [2, 3]],
      [4, []],
    ],
  );
});

test('findRow finds a row by kind and id, or -1', () => {
  const list = rows(store, { b: true }, false, now);
  assert.equal(findRow(list, 'task', 't2'), 3);
  assert.equal(findRow(list, 'goal', 't2'), -1);
});

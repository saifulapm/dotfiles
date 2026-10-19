import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  emptyStore,
  parseStore,
  addGoal,
  addTask,
  toggleGoal,
  toggleTask,
  editGoal,
  editTask,
  deleteGoal,
  deleteTask,
  moveGoal,
  moveTask,
  activeGoals,
  doneGoals,
  liveTasks,
  parseDeadline,
  countdown,
  marginGoal,
  mergeStores,
} from './goals.mjs';

const T = 1760000000000;
const H = 3600000;
const D = 24 * H;

const titles = (goals) => goals.map((g) => g.title);

test('a new store has no goals, and a broken file reads as null so it is never saved over', () => {
  assert.deepEqual(emptyStore(), { version: 1, goals: [] });
  for (const t of ['', '{', '[]', 'null', '{"version":1}', '{"goals":[{"title":"x"}]}', '{"goals":[{"id":"a","title":"x","tasks":[{"text":"t"}]}]}']) assert.equal(parseStore(t), null);
  const s = parseStore('{"version":1,"goals":[{"id":"a","title":"x"}]}');
  assert.deepEqual(s.goals, [{ id: 'a', title: 'x', deadline: null, order: 0, done: false, doneAt: null, updatedAt: 0, deleted: false, tasks: [] }]);
});

test('two goals added in turn are both active, in that order, with the deadline kept', () => {
  let s = addGoal(emptyStore(), 'Ship v2', T + 3 * D, T, 'g1');
  s = addGoal(s, 'Read', null, T + 1, 'g2');
  assert.deepEqual(titles(activeGoals(s)), ['Ship v2', 'Read']);
  assert.equal(activeGoals(s)[0].deadline, T + 3 * D);
  assert.equal(activeGoals(s)[1].deadline, null);
  assert.deepEqual(parseStore(JSON.stringify(s)), s);
});

test('a task goes under its own goal only', () => {
  let s = addGoal(addGoal(emptyStore(), 'Ship v2', null, T, 'g1'), 'Read', null, T, 'g2');
  s = addTask(s, 'g2', 'ch 1', T + 1, 't1');
  assert.deepEqual(liveTasks(activeGoals(s)[0]), []);
  assert.deepEqual(liveTasks(activeGoals(s)[1]).map((t) => t.text), ['ch 1']);
  assert.equal(addTask(s, 'g2', '  ', T, 't2'), s);
});

test('moving a goal up swaps it with the one above, and the top one stays put', () => {
  let s = addGoal(addGoal(emptyStore(), 'Ship v2', null, T, 'g1'), 'Read', null, T, 'g2');
  s = moveGoal(s, 'g2', -1, T + 5);
  assert.deepEqual(titles(activeGoals(s)), ['Read', 'Ship v2']);
  assert.equal(moveGoal(s, 'g2', -1, T + 6), s);
  assert.equal(s.goals.find((g) => g.id === 'g2').updatedAt, T + 5);
});

test('Space on a goal moves it to done, and again brings it back to the end of the active list', () => {
  let s = addGoal(addGoal(emptyStore(), 'Ship v2', null, T, 'g1'), 'Read', null, T, 'g2');
  s = toggleGoal(s, 'g1', T + 9);
  assert.deepEqual(titles(activeGoals(s)), ['Read']);
  assert.deepEqual(titles(doneGoals(s)), ['Ship v2']);
  assert.equal(doneGoals(s)[0].doneAt, T + 9);
  s = toggleGoal(s, 'g1', T + 10);
  assert.deepEqual(titles(activeGoals(s)), ['Read', 'Ship v2']);
  assert.equal(s.goals[0].doneAt, null);
});

test('a task ticks and unticks, moves within its goal and is edited and deleted', () => {
  let s = addGoal(emptyStore(), 'Read', null, T, 'g1');
  s = addTask(addTask(s, 'g1', 'ch 1', T, 't1'), 'g1', 'ch 2', T, 't2');
  s = toggleTask(s, 'g1', 't1', T + 1);
  assert.deepEqual(liveTasks(s.goals[0]).map((t) => [t.text, t.done]), [['ch 1', true], ['ch 2', false]]);
  s = moveTask(s, 'g1', 't2', -1, T + 2);
  assert.deepEqual(liveTasks(s.goals[0]).map((t) => t.text), ['ch 2', 'ch 1']);
  s = editTask(s, 'g1', 't2', 'chapter 2', T + 3);
  s = deleteTask(s, 'g1', 't1', T + 4);
  assert.deepEqual(liveTasks(s.goals[0]).map((t) => t.text), ['chapter 2']);
  assert.equal(s.goals[0].tasks.find((t) => t.id === 't1').deleted, true);
});

test('editing a goal sets its title and deadline; a blank title changes nothing', () => {
  let s = addGoal(emptyStore(), 'Ship', null, T, 'g1');
  s = editGoal(s, 'g1', 'Ship v2', T + D, T + 1);
  assert.deepEqual([s.goals[0].title, s.goals[0].deadline, s.goals[0].updatedAt], ['Ship v2', T + D, T + 1]);
  assert.equal(editGoal(s, 'g1', ' ', null, T + 2), s);
});

test('a deleted goal leaves a tombstone and no longer lists', () => {
  let s = addTask(addGoal(emptyStore(), 'Ship v2', T + D, T, 'g1'), 'g1', 'x', T, 't1');
  s = deleteGoal(s, 'g1', T + 1);
  assert.deepEqual(activeGoals(s), []);
  assert.deepEqual(doneGoals(s), []);
  assert.deepEqual(s.goals[0], { id: 'g1', title: '', deadline: null, order: 0, done: false, doneAt: null, updatedAt: T + 1, deleted: true, tasks: [] });
});

test('a deadline is typed as Nd, Nh or a date; empty is none and anything else is refused', () => {
  // From the start of the minute, since the margin's clock only moves on the minute: typed at 14:32:45, 3d still reads 3d.
  const M0 = new Date(2026, 9, 18, 14, 32).getTime();
  assert.deepEqual(parseDeadline('3d', M0 + 45000), { deadline: M0 + 3 * D });
  assert.deepEqual(parseDeadline(' 5h ', M0 + 45000), { deadline: M0 + 5 * H });
  assert.equal(countdown(parseDeadline('3d', M0 + 45000).deadline, M0), '3d');
  assert.deepEqual(parseDeadline('', T), { deadline: null });
  assert.deepEqual(parseDeadline('2026-10-21', T), { deadline: new Date(2026, 9, 21, 23, 59).getTime() });
  for (const t of ['3', 'd', '0d', '2026-02-30', '2026-13-01', 'tomorrow', '3 d']) assert.equal(parseDeadline(t, T), null);
  // A deadline past ten years is refused, so a typo like 99999999d never reaches a date the clock cannot draw.
  for (const t of ['99999999d', '3651d', '87601h', '9999-01-01']) assert.equal(parseDeadline(t, T), null);
  assert.notEqual(parseDeadline('3650d', T), null);
});

test('the countdown rounds up, switches to hours under a day, and reads late once past', () => {
  assert.equal(countdown(T + 3 * D - 1000, T), '3d');
  assert.equal(countdown(T + 12 * D, T), '12d');
  assert.equal(countdown(T + D + 1, T), '2d');
  assert.equal(countdown(T + 5 * H, T), '5h');
  assert.equal(countdown(T + 4.5 * H, T), '5h');
  assert.equal(countdown(T, T), 'late');
});

test('the margin shows the active goal with the nearest deadline', () => {
  let s = addGoal(emptyStore(), 'Docs', T + 12 * D, T, 'g1');
  s = addGoal(s, 'Ship v2', T + 3 * D, T, 'g2');
  assert.equal(marginGoal(s, T + 60000), 'Ship v2 · 3d');
  assert.equal(marginGoal(addGoal(emptyStore(), 'Ship v2', T + 5 * H, T, 'g1'), T), 'Ship v2 · 5h');
});

test('with no deadline the margin shows the first active goal bare, and with none active nothing', () => {
  let s = addGoal(addGoal(emptyStore(), 'Ship v2', null, T, 'g1'), 'Read', null, T, 'g2');
  assert.equal(marginGoal(moveGoal(s, 'g2', -1, T), T), 'Read');
  assert.equal(marginGoal(toggleGoal(toggleGoal(s, 'g1', T), 'g2', T), T), '');
  assert.equal(marginGoal(emptyStore(), T), '');
});

test('a merge takes the newer copy of each goal and of each task, and keeps tombstones', () => {
  const base = addTask(addGoal(emptyStore(), 'Read', null, T, 'g1'), 'g1', 'ch 1', T, 't1');
  // A renames the goal; B ticks the task and adds a goal of its own; then A deletes the goal B added.
  const a = editGoal(base, 'g1', 'Read more', null, T + 10);
  const b = addGoal(toggleTask(base, 'g1', 't1', T + 20), 'X', null, T + 21, 'g2');
  const merged = mergeStores(a, b);
  assert.deepEqual(titles(activeGoals(merged)), ['Read more', 'X']);
  assert.equal(liveTasks(merged.goals[0])[0].done, true);
  const gone = mergeStores(merged, deleteGoal(merged, 'g2', T + 30));
  assert.deepEqual(titles(activeGoals(gone)), ['Read more']);
  assert.equal(gone.goals.find((g) => g.id === 'g2').deleted, true);
  // An older copy of a deleted goal does not bring it back.
  assert.deepEqual(titles(activeGoals(mergeStores(gone, b))), ['Read more']);
});

test('a merge gives the same store whichever side comes first', () => {
  const a = addGoal(emptyStore(), 'A', null, T, 'g1');
  const b = addGoal(emptyStore(), 'B', null, T, 'g1');
  assert.deepEqual(mergeStores(a, b), mergeStores(b, a));
  const m = mergeStores(a, b);
  assert.deepEqual(mergeStores(m, m), m);
});

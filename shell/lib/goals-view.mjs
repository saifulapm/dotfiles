// The Goals window's rows, from the store and the window's own fold state; j/k step over these.
import { activeGoals, doneGoals, liveTasks, countdown } from './goals.mjs';

// A deadline is danger on its own calendar day and once it has passed.
const onTheDay = (deadline, now) => deadline <= now || new Date(deadline).toDateString() === new Date(now).toDateString();

function goalRow(g, now) {
  const chip = g.deadline === null ? null : countdown(g.deadline, now);
  const chipTone = g.deadline === null ? null : onTheDay(g.deadline, now) ? 'danger' : 'muted';
  return { kind: 'goal', id: g.id, goal: g.id, text: g.title, done: g.done, chip, chipTone };
}

function withTasks(out, g, unfolded, now) {
  out.push(goalRow(g, now));
  if (unfolded[g.id]) liveTasks(g).forEach((t) => out.push({ kind: 'task', id: t.id, goal: g.id, text: t.text, done: t.done }));
}

// unfolded maps a goal id to true; the done group shows only when a goal is done.
export function rows(store, unfolded, doneOpen, now) {
  const out = [];
  activeGoals(store).forEach((g) => withTasks(out, g, unfolded, now));
  const done = doneGoals(store);
  if (done.length) {
    out.push({ kind: 'done', id: 'done', goal: '', text: 'Done · ' + done.length });
    if (doneOpen) done.forEach((g) => withTasks(out, g, unfolded, now));
  }
  return out;
}

// Each goal or done row with the task rows under it, as row indexes, so a card can draw a goal and its tasks together.
export function blocks(list) {
  const out = [];
  list.forEach((r, i) => {
    if (r.kind === 'task') out[out.length - 1].tasks.push(Object.assign({ row: i }, r));
    else out.push({ row: i, head: r, tasks: [] });
  });
  return out;
}

export const findRow = (list, kind, id) => list.findIndex((r) => r.kind === kind && r.id === id);


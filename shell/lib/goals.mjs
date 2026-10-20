// The goals store and its rules, shared by the Goals window, the margin and the sync merge; kept pure so node can test them.

const H = 3600000;
const D = 24 * H;

const set = (o, fields) => Object.assign({}, o, fields);
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const str = (v) => typeof v === 'string';
const num = (v, fallback) => (typeof v === 'number' ? v : fallback);

export const emptyStore = () => ({ version: 1, goals: [] });

// Each field carries the time it was last set, so a merge takes every field from the machine that changed it last; doneAt goes with done.
const GOAL_FIELDS = ['title', 'deadline', 'order', 'done', 'deleted'];
const TASK_FIELDS = ['text', 'done', 'order', 'deleted'];

const newest = (stamps) => Object.keys(stamps).reduce((max, f) => Math.max(max, stamps[f]), 0);

// A record from before the stamps has only updatedAt, which then stands for every field.
function readStamps(x, fields) {
  const from = isObject(x.stamps) ? x.stamps : {};
  const updatedAt = num(x.updatedAt, 0);
  return fields.reduce((s, f) => set(s, { [f]: num(from[f], updatedAt) }), {});
}

// updatedAt stays the newest stamp, so a machine still on the whole-record merge picks the newest copy, and a stamp far ahead is caught by it.
function readTask(t, i) {
  const stamps = readStamps(t, TASK_FIELDS);
  return { id: t.id, text: t.text, done: t.done === true, order: num(t.order, i), updatedAt: Math.max(num(t.updatedAt, 0), newest(stamps)), deleted: t.deleted === true, stamps };
}

function readGoal(g, i) {
  const stamps = readStamps(g, GOAL_FIELDS);
  return {
    id: g.id,
    title: g.title,
    deadline: num(g.deadline, null),
    order: num(g.order, i),
    done: g.done === true,
    doneAt: num(g.doneAt, null),
    updatedAt: Math.max(num(g.updatedAt, 0), newest(stamps)),
    deleted: g.deleted === true,
    tasks: (g.tasks ?? []).map(readTask),
    stamps,
  };
}

// Sets the fields and stamps those that carry a stamp with now.
function touch(x, keys, fields, now) {
  const stamps = Object.keys(fields).reduce((s, f) => (keys.indexOf(f) >= 0 ? set(s, { [f]: now }) : s), readStamps(x, keys));
  return set(x, Object.assign({}, fields, { stamps, updatedAt: newest(stamps) }));
}

const touchGoal = (g, fields, now) => touch(g, GOAL_FIELDS, fields, now);
const touchTask = (t, fields, now) => touch(t, TASK_FIELDS, fields, now);

const validTask = (t) => isObject(t) && str(t.id) && str(t.text);
const validGoal = (g) => isObject(g) && str(g.id) && str(g.title) && (g.tasks === undefined || (Array.isArray(g.tasks) && g.tasks.every(validTask)));

// A file that is empty, broken or the wrong shape is null, so nothing ever saves over the goals it holds.
export function parseStore(text) {
  let data = null;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return null;
  }
  if (!isObject(data) || !Array.isArray(data.goals) || !data.goals.every(validGoal)) return null;
  return { version: 1, goals: data.goals.map(readGoal) };
}

// QML's sort is not promised to be stable, so ties break on id.
const byOrder = (a, b) => a.order - b.order || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

export const activeGoals = (store) => store.goals.filter((g) => !g.deleted && !g.done).sort(byOrder);

export const doneGoals = (store) => store.goals.filter((g) => !g.deleted && g.done).sort((a, b) => b.doneAt - a.doneAt || byOrder(a, b));

export const liveTasks = (goal) => goal.tasks.filter((t) => !t.deleted).sort(byOrder);

const nextOrder = (items) => items.reduce((max, x) => Math.max(max, x.order + 1), 0);

const changeGoal = (store, id, fn) => set(store, { goals: store.goals.map((g) => (g.id === id ? fn(g) : g)) });

const changeTask = (store, goalId, taskId, fn) => changeGoal(store, goalId, (g) => set(g, { tasks: g.tasks.map((t) => (t.id === taskId ? fn(t) : t)) }));

export function addGoal(store, title, deadline, now, id) {
  if (!title.trim()) return store;
  const goal = touchGoal({ id, title: title.trim(), deadline, order: nextOrder(activeGoals(store)), done: false, doneAt: null, updatedAt: now, deleted: false, tasks: [] }, {}, now);
  return set(store, { goals: store.goals.concat([goal]) });
}

export function addTask(store, goalId, text, now, id) {
  if (!text.trim()) return store;
  return changeGoal(store, goalId, (g) => set(g, { tasks: g.tasks.concat([touchTask({ id, text: text.trim(), done: false, order: nextOrder(liveTasks(g)), updatedAt: now, deleted: false }, {}, now)]) }));
}

// A goal brought back from done goes to the end of the active list.
export const toggleGoal = (store, id, now) =>
  changeGoal(store, id, (g) => (g.done ? touchGoal(g, { done: false, doneAt: null, order: nextOrder(activeGoals(store)) }, now) : touchGoal(g, { done: true, doneAt: now }, now)));

export const toggleTask = (store, goalId, taskId, now) => changeTask(store, goalId, taskId, (t) => touchTask(t, { done: !t.done }, now));

export const editGoal = (store, id, title, deadline, now) => (title.trim() ? changeGoal(store, id, (g) => touchGoal(g, { title: title.trim(), deadline }, now)) : store);

export const editTask = (store, goalId, taskId, text, now) => (text.trim() ? changeTask(store, goalId, taskId, (t) => touchTask(t, { text: text.trim() }, now)) : store);

export const deleteGoal = (store, id, now) => changeGoal(store, id, (g) => touchGoal(g, { title: '', deadline: null, done: false, doneAt: null, tasks: [], deleted: true }, now));

export const deleteTask = (store, goalId, taskId, now) => changeTask(store, goalId, taskId, (t) => touchTask(t, { text: '', done: false, deleted: true }, now));

// Swaps the item with its neighbour, then numbers the list 0..n; an item whose number changed is stamped, so a merge carries it.
function reorder(list, id, dir, now, touchIt) {
  const i = list.findIndex((x) => x.id === id);
  const j = i + dir;
  if (i < 0 || j < 0 || j >= list.length) return null;
  const moved = list.slice();
  moved[i] = list[j];
  moved[j] = list[i];
  const changed = {};
  moved.forEach((x, k) => {
    if (x.order !== k) changed[x.id] = k;
  });
  return (x) => (x.id in changed ? touchIt(x, { order: changed[x.id] }, now) : x);
}

export function moveGoal(store, id, dir, now) {
  const fn = reorder(activeGoals(store), id, dir, now, touchGoal);
  return fn ? set(store, { goals: store.goals.map(fn) }) : store;
}

export function moveTask(store, goalId, taskId, dir, now) {
  const goal = store.goals.find((g) => g.id === goalId);
  const fn = goal ? reorder(liveTasks(goal), taskId, dir, now, touchTask) : null;
  return fn ? changeGoal(store, goalId, (g) => set(g, { tasks: g.tasks.map(fn) })) : store;
}

// Ten years out is the furthest deadline taken, so a typo like 99999999d never reaches a date the clock cannot draw.
const FURTHEST = 3650 * D;

function dueAt(t, now) {
  const rel = t.match(/^([1-9][0-9]*)([dh])$/);
  if (rel) return now - (now % 60000) + Number(rel[1]) * (rel[2] === 'd' ? D : H);
  const date = t.match(/^([0-9]{4})-([0-9]{2})-([0-9]{2})$/);
  if (!date) return null;
  const d = new Date(Number(date[1]), Number(date[2]) - 1, Number(date[3]), 23, 59);
  return d.getMonth() === Number(date[2]) - 1 && d.getDate() === Number(date[3]) ? d.getTime() : null;
}

// The prompt takes Nd or Nh from the start of this minute (the margin's clock moves only on the minute), or a date due 23:59 local; null refuses.
export function parseDeadline(text, now) {
  const t = text.trim();
  if (!t) return { deadline: null };
  const deadline = dueAt(t, now);
  return deadline !== null && deadline - now <= FURTHEST ? { deadline } : null;
}

// Rounded up, so a goal due in 3 days still reads 3d a minute later.
export function countdown(deadline, now) {
  const left = deadline - now;
  if (left <= 0) return 'late';
  return left < D ? Math.ceil(left / H) + 'h' : Math.ceil(left / D) + 'd';
}

// The goal the margin names, as { title, left }: the nearest deadline and its countdown, else the first goal with left null; null with no goal.
export function marginGoalParts(store, now) {
  const active = activeGoals(store);
  const due = active.filter((g) => g.deadline !== null).sort((a, b) => a.deadline - b.deadline || byOrder(a, b));
  if (due.length) return { title: due[0].title, left: countdown(due[0].deadline, now) };
  return active.length ? { title: active[0].title, left: null } : null;
}

export function marginGoal(store, now) {
  const g = marginGoalParts(store, now);
  return g === null ? '' : g.left === null ? g.title : g.title + ' · ' + g.left;
}

// The copy that set the field later wins it; a tie goes to the larger value's text, so both machines pick the same one.
function later(a, b, f) {
  if (a.stamps[f] !== b.stamps[f]) return a.stamps[f] > b.stamps[f] ? a : b;
  const value = (x) => JSON.stringify(f === 'done' ? [x.done, x.doneAt] : x[f]);
  return value(a) >= value(b) ? a : b;
}

// Builds the record field by field from whichever copy set each one later.
function mergeFields(a, b, fields, base) {
  const stamps = {};
  const out = Object.assign({}, base);
  fields.forEach((f) => {
    const from = later(a, b, f);
    out[f] = from[f];
    if (f === 'done') out.doneAt = from.doneAt;
    stamps[f] = from.stamps[f];
  });
  return Object.assign(out, { updatedAt: Math.max(a.updatedAt, b.updatedAt), stamps });
}

const mergeTask = (a, b) => mergeFields(a, b, TASK_FIELDS, { id: a.id, text: '', done: false, order: 0, updatedAt: 0, deleted: false });

function mergeById(xs, ys, fn) {
  const byId = {};
  xs.concat(ys).forEach((x) => {
    byId[x.id] = byId[x.id] ? fn(byId[x.id], x) : x;
  });
  return Object.keys(byId).sort().map((id) => byId[id]);
}

// Goal and task fields merge one by one, so a tick on one machine and a deadline edit on another both survive.
const mergeGoal = (a, b) => {
  const g = mergeFields(a, b, GOAL_FIELDS, { id: a.id, title: '', deadline: null, order: 0, done: false, doneAt: null, updatedAt: 0, deleted: false, tasks: [] });
  return set(g, { tasks: g.deleted ? [] : mergeById(a.tasks, b.tasks, mergeTask) });
};

export const mergeStores = (a, b) => ({ version: 1, goals: mergeById(a.goals, b.goals, mergeGoal) });

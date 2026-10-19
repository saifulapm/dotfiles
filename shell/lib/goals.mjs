// The goals store and its rules, shared by the Goals window, the margin and the sync merge; kept pure so node can test them.

const H = 3600000;
const D = 24 * H;

const set = (o, fields) => Object.assign({}, o, fields);
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const str = (v) => typeof v === 'string';
const num = (v, fallback) => (typeof v === 'number' ? v : fallback);

export const emptyStore = () => ({ version: 1, goals: [] });

const readTask = (t, i) => ({ id: t.id, text: t.text, done: t.done === true, order: num(t.order, i), updatedAt: num(t.updatedAt, 0), deleted: t.deleted === true });

const readGoal = (g, i) => ({
  id: g.id,
  title: g.title,
  deadline: num(g.deadline, null),
  order: num(g.order, i),
  done: g.done === true,
  doneAt: num(g.doneAt, null),
  updatedAt: num(g.updatedAt, 0),
  deleted: g.deleted === true,
  tasks: (g.tasks ?? []).map(readTask),
});

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
  const goal = { id, title: title.trim(), deadline, order: nextOrder(activeGoals(store)), done: false, doneAt: null, updatedAt: now, deleted: false, tasks: [] };
  return set(store, { goals: store.goals.concat([goal]) });
}

export function addTask(store, goalId, text, now, id) {
  if (!text.trim()) return store;
  return changeGoal(store, goalId, (g) => set(g, { tasks: g.tasks.concat([{ id, text: text.trim(), done: false, order: nextOrder(liveTasks(g)), updatedAt: now, deleted: false }]) }));
}

// A goal brought back from done goes to the end of the active list.
export const toggleGoal = (store, id, now) =>
  changeGoal(store, id, (g) => (g.done ? set(g, { done: false, doneAt: null, order: nextOrder(activeGoals(store)), updatedAt: now }) : set(g, { done: true, doneAt: now, updatedAt: now })));

export const toggleTask = (store, goalId, taskId, now) => changeTask(store, goalId, taskId, (t) => set(t, { done: !t.done, updatedAt: now }));

export const editGoal = (store, id, title, deadline, now) => (title.trim() ? changeGoal(store, id, (g) => set(g, { title: title.trim(), deadline, updatedAt: now })) : store);

export const editTask = (store, goalId, taskId, text, now) => (text.trim() ? changeTask(store, goalId, taskId, (t) => set(t, { text: text.trim(), updatedAt: now })) : store);

export const deleteGoal = (store, id, now) => changeGoal(store, id, (g) => set(g, { title: '', deadline: null, done: false, doneAt: null, tasks: [], deleted: true, updatedAt: now }));

export const deleteTask = (store, goalId, taskId, now) => changeTask(store, goalId, taskId, (t) => set(t, { text: '', done: false, deleted: true, updatedAt: now }));

// Swaps the item with its neighbour, then numbers the list 0..n; an item whose number changed is stamped, so a merge carries it.
function reorder(list, id, dir, now) {
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
  return (x) => (x.id in changed ? set(x, { order: changed[x.id], updatedAt: now }) : x);
}

export function moveGoal(store, id, dir, now) {
  const fn = reorder(activeGoals(store), id, dir, now);
  return fn ? set(store, { goals: store.goals.map(fn) }) : store;
}

export function moveTask(store, goalId, taskId, dir, now) {
  const goal = store.goals.find((g) => g.id === goalId);
  const fn = goal ? reorder(liveTasks(goal), taskId, dir, now) : null;
  return fn ? changeGoal(store, goalId, (g) => set(g, { tasks: g.tasks.map(fn) })) : store;
}

// The prompt takes Nd or Nh from the start of this minute (the margin's clock moves only on the minute), or a date due 23:59 local; null refuses.
export function parseDeadline(text, now) {
  const t = text.trim();
  if (!t) return { deadline: null };
  const rel = t.match(/^([1-9][0-9]*)([dh])$/);
  if (rel) return { deadline: now - (now % 60000) + Number(rel[1]) * (rel[2] === 'd' ? D : H) };
  const date = t.match(/^([0-9]{4})-([0-9]{2})-([0-9]{2})$/);
  if (!date) return null;
  const d = new Date(Number(date[1]), Number(date[2]) - 1, Number(date[3]), 23, 59);
  return d.getMonth() === Number(date[2]) - 1 && d.getDate() === Number(date[3]) ? { deadline: d.getTime() } : null;
}

// Rounded up, so a goal due in 3 days still reads 3d a minute later.
export function countdown(deadline, now) {
  const left = deadline - now;
  if (left <= 0) return 'late';
  return left < D ? Math.ceil(left / H) + 'h' : Math.ceil(left / D) + 'd';
}

export function marginGoal(store, now) {
  const active = activeGoals(store);
  const due = active.filter((g) => g.deadline !== null).sort((a, b) => a.deadline - b.deadline || byOrder(a, b));
  if (due.length) return due[0].title + ' · ' + countdown(due[0].deadline, now);
  return active.length ? active[0].title : '';
}

// The newer copy wins; a tie goes to the larger text, so both machines pick the same one.
function newer(a, b) {
  if (a.updatedAt !== b.updatedAt) return a.updatedAt > b.updatedAt ? a : b;
  return JSON.stringify(a) >= JSON.stringify(b) ? a : b;
}

function mergeById(xs, ys, fn) {
  const byId = {};
  xs.concat(ys).forEach((x) => {
    byId[x.id] = byId[x.id] ? fn(byId[x.id], x) : x;
  });
  return Object.keys(byId).sort().map((id) => byId[id]);
}

// Goal fields come from the newer goal and each task from its newer copy, so a rename on one machine and a tick on another both survive.
const mergeGoal = (a, b) => {
  const g = newer(a, b);
  return set(g, { tasks: g.deleted ? [] : mergeById(a.tasks, b.tasks, newer) });
};

export const mergeStores = (a, b) => ({ version: 1, goals: mergeById(a.goals, b.goals, mergeGoal) });

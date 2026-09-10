// Store semantics for the Goals widget — pure JS with no QML types, so the
// shapes run headlessly under node (GoalsModel.test.js is the runner, and
// bin/goals-merge requires this file for the cross-machine merge), exactly
// the split NotesModel.js uses.
//
// WHAT THIS IS FOR. One goal at a time, with a deadline and a finite task
// list, so the bar can show "SplitRoute 3/7 · 19h" without anything being
// opened. The task ratio is the motivator and the clock is the pressure;
// neither is shown alone (a naked countdown reads as dread, and a ratio with
// no deadline is just a todo list).
//
// Schema version 1. A goal is
//
//     { id, name, due, state, tasks, createdAt, updatedAt }      live
//     { id, name:"", due:"", state:"", tasks:[],
//       createdAt, updatedAt, deletedAt }                        tombstone
//
// and a task is { id, text, done, updatedAt }. `state` is "active" (at most
// one, ever), "queued" or "shipped"; `due` is a UTC ISO instant.
//
// ------------------------------------------------------------------- ids
// `id` is a string unique across machines: 9 base36 chars of creation-time
// milliseconds plus a random suffix, the NotesModel idiom, so two machines
// minting in the same millisecond still cannot collide.
//
// An item that arrives WITHOUT an id — the store is meant to be hand-editable
// in an editor, and typing `{ "text": "Submit for review" }` is the whole
// point of that — gets one derived from its content instead of minted:
// "h" + hash(parentId + "|" + text). Deterministic, so two machines parsing
// the same hand-added line agree on the id and the merge dedupes them. A
// minted id here would give each machine a different one and the next sync
// would triplicate every hand-typed task.
//
// ---------------------------------------------------------------- merging
// Per-GOAL last-write-wins would lose data the moment it matters: tick task 3
// on the laptop, tick task 5 on the mini, and one tick vanishes. So the merge
// is two-level — goals union by id, and within a surviving goal the TASKS
// union by their own id with their own updatedAt. Scalar goal fields (name,
// due, state) still take the newer goal's value as a set.
//
// "At most one active" is an invariant the merge has to restore, not assume:
// two machines can each activate a different goal while apart. resolveActive()
// keeps the newest-updated active and demotes the rest to "queued",
// deterministically, so every machine lands on the same winner.
//
// Shipping deliberately does NOT auto-promote the next queued goal. Two
// machines shipping in the same window would each promote a different
// successor and the merge would have to arbitrate a decision the user never
// made. Promotion is a button. It also earns a beat to notice the win before
// the next deadline starts ticking, which is the entire point of the thing.

var EPOCH = "1970-01-01T00:00:00.000Z";
var TOMBSTONE_TTL_MS = 30 * 24 * 60 * 60 * 1000;

var MINUTE_MS = 60 * 1000;
var HOUR_MS = 60 * MINUTE_MS;
var DAY_MS = 24 * HOUR_MS;

function nowIso() {
    return new Date().toISOString();
}

function newId() {
    var t = Date.now().toString(36);
    while (t.length < 9)
        t = "0" + t;
    return t + "-" + Math.random().toString(36).slice(2, 6);
}

// FNV-1a over the parent id and the text, base36. Only ever used to give a
// hand-written item a stable identity; collisions mean "same text under the
// same goal", which is the one case where sharing an id is correct anyway.
function derivedId(parentId, text) {
    var s = String(parentId) + "|" + String(text);
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
    }
    return "h" + h.toString(36);
}

// ------------------------------------------------------------ normalization
// One key order everywhere: the merge tie-break and the persist-echo check
// both compare serialized forms, so field order is part of the contract.
function normalizeTask(t, goalId) {
    var text = String(t.text || "").trim();
    return {
        id: String(t.id || "") || derivedId(goalId, text),
        text: text,
        done: !!t.done,
        updatedAt: String(t.updatedAt || EPOCH)
    };
}

function normalizeGoal(g) {
    var id = String(g.id || "") || derivedId("goal", String(g.name || ""));
    var state = String(g.state || "queued");
    if (state !== "active" && state !== "queued" && state !== "shipped")
        state = "queued";
    var tasks = (Array.isArray(g.tasks) ? g.tasks : []).filter(function (t) {
        return t && typeof t === "object";
    }).map(function (t) {
        return normalizeTask(t, id);
    });
    var out = {
        id: id,
        name: String(g.name || ""),
        due: String(g.due || ""),
        state: state,
        tasks: tasks,
        createdAt: String(g.createdAt || EPOCH),
        updatedAt: String(g.updatedAt || EPOCH)
    };
    if (g.shippedAt)
        out.shippedAt = String(g.shippedAt);
    if (g.deletedAt)
        out.deletedAt = String(g.deletedAt);
    return out;
}

// Tolerant on purpose: this file is meant to survive being hand-edited, so a
// goal missing every optional field still parses. Only a total loss (no JSON,
// no goals array) yields the empty store, which reads as "no goals yet"
// rather than as an error — on a fresh machine that is exactly what it is.
function parseStore(raw) {
    var text = String(raw || "").trim();
    if (!text)
        return [];
    try {
        var parsed = JSON.parse(text);
        if (parsed && Array.isArray(parsed.goals))
            return parsed.goals.filter(function (g) {
                return g && typeof g === "object" && (g.deletedAt || g.name);
            }).map(normalizeGoal);
    } catch (e) {}
    return [];
}

function serialize(goals) {
    return JSON.stringify({
        version: 1,
        goals: goals
    }, null, 2) + "\n";
}

// ------------------------------------------------------------------ writing
function makeGoal(name, dueIso, state) {
    var at = nowIso();
    return normalizeGoal({
        id: newId(),
        name: String(name || "").trim(),
        due: String(dueIso || ""),
        state: state || "queued",
        tasks: [],
        createdAt: at,
        updatedAt: at
    });
}

function makeTask(text) {
    return {
        id: newId(),
        text: String(text || "").trim(),
        done: false,
        updatedAt: nowIso()
    };
}

function touch(goal, changes) {
    return normalizeGoal(Object.assign({}, goal, changes, {
        updatedAt: nowIso()
    }));
}

function mapGoal(goals, id, fn) {
    return goals.map(function (g) {
        return g.id === id ? fn(g) : g;
    });
}

function addGoal(goals, goal) {
    return goals.concat([goal]);
}

function addTask(goals, goalId, task) {
    return mapGoal(goals, goalId, function (g) {
        return touch(g, {
            tasks: g.tasks.concat([task])
        });
    });
}

// Only the task's own updatedAt moves. The goal's does NOT: a tick is a task
// edit, and bumping the goal too would let a stale machine's unrelated name
// or due change ride in on it during the merge's scalar-field set.
function toggleTask(goals, goalId, taskId) {
    return mapGoal(goals, goalId, function (g) {
        return normalizeGoal(Object.assign({}, g, {
            tasks: g.tasks.map(function (t) {
                return t.id === taskId ? {
                    id: t.id,
                    text: t.text,
                    done: !t.done,
                    updatedAt: nowIso()
                } : t;
            })
        }));
    });
}

// A removed task leaves no tombstone: tasks only exist inside a goal, and a
// goal is short-lived by construction (that is what a deadline is). The
// realistic cost of a resurrection is one stale row the user unticks; the
// realistic cost of per-task tombstones is a store nobody can hand-edit.
function removeTask(goals, goalId, taskId) {
    return mapGoal(goals, goalId, function (g) {
        return touch(g, {
            tasks: g.tasks.filter(function (t) {
                return t.id !== taskId;
            })
        });
    });
}

function removeGoal(goals, goalId) {
    var at = nowIso();
    return mapGoal(goals, goalId, function (g) {
        return normalizeGoal({
            id: g.id,
            name: "",
            due: "",
            state: "",
            tasks: [],
            createdAt: g.createdAt,
            updatedAt: at,
            deletedAt: at
        });
    });
}

function shipGoal(goals, goalId) {
    var at = nowIso();
    return mapGoal(goals, goalId, function (g) {
        return touch(g, {
            state: "shipped",
            shippedAt: at
        });
    });
}

// Promotion demotes whoever is active first, so the invariant holds even if
// the caller aims this at a second goal by mistake.
//
// Works on a goal in ANY state, which is what makes a mis-ship recoverable:
// starting a shipped goal again clears its shippedAt, because a goal you are
// working on has not shipped. Leaving the stamp would keep it in the ledger's
// sort key and claim a win that is back in progress.
function activateGoal(goals, goalId) {
    return goals.map(function (g) {
        if (g.id === goalId)
            return touch(g, {
                state: "active",
                shippedAt: undefined
            });
        if (g.state === "active")
            return touch(g, {
                state: "queued"
            });
        return g;
    });
}

// Missing a deadline has to be a normal, cheap event. If the bar went red and
// stayed red the widget would become the thing you avoid looking at, and it
// would be dead inside a week — so extending is one click and costs nothing.
// The extension is from NOW, not from the old due date: a goal three days
// overdue that you extend by a day means a day from here.
function extendDue(goals, goalId, ms, nowMs) {
    var base = typeof nowMs === "number" ? nowMs : Date.now();
    return mapGoal(goals, goalId, function (g) {
        var from = Math.max(base, Date.parse(g.due) || base);
        return touch(g, {
            due: new Date(from + ms).toISOString()
        });
    });
}

// ------------------------------------------------------------------ reading
function liveGoals(goals) {
    return goals.filter(function (g) {
        return !g.deletedAt;
    });
}

function byState(goals, state) {
    return liveGoals(goals).filter(function (g) {
        return g.state === state;
    });
}

function activeGoal(goals) {
    var found = byState(goals, "active");
    return found.length > 0 ? found[0] : null;
}

function queuedGoals(goals) {
    return byState(goals, "queued").sort(function (a, b) {
        return a.createdAt < b.createdAt ? -1 : (a.createdAt > b.createdAt ? 1 : 0);
    });
}

// Newest first: the panel shows the most recent wins, and the most recent win
// is the one that still feels like one. Ties fall back to creation time and
// then to the id — two goals shipped in the same millisecond is a real
// possibility once "ship" is one click, and the ledger has to read the same
// on every machine or the merge has nothing stable to converge on.
function shippedGoals(goals) {
    return byState(goals, "shipped").sort(function (a, b) {
        var ka = String(a.shippedAt || a.updatedAt) + "|" + a.createdAt + "|" + a.id;
        var kb = String(b.shippedAt || b.updatedAt) + "|" + b.createdAt + "|" + b.id;
        return ka > kb ? -1 : (ka < kb ? 1 : 0);
    });
}

function shippedCount(goals) {
    return byState(goals, "shipped").length;
}

function findGoal(goals, id) {
    for (var i = 0; i < goals.length; i++)
        if (goals[i].id === id)
            return goals[i];
    return null;
}

function progress(goal) {
    var tasks = goal && goal.tasks ? goal.tasks : [];
    var done = tasks.filter(function (t) {
        return t.done;
    }).length;
    return {
        done: done,
        total: tasks.length,
        ratio: tasks.length > 0 ? done / tasks.length : 0
    };
}

// The first unticked task. This is what the panel points at with "▸" — the
// question a goal tracker actually has to answer is "what do I do next",
// and a flat list of seven items does not answer it.
function nextTask(goal) {
    var tasks = goal && goal.tasks ? goal.tasks : [];
    for (var i = 0; i < tasks.length; i++)
        if (!tasks[i].done)
            return tasks[i];
    return null;
}

function timeLeftMs(goal, nowMs) {
    if (!goal || !goal.due)
        return null;
    var due = Date.parse(goal.due);
    if (isNaN(due))
        return null;
    return due - (typeof nowMs === "number" ? nowMs : Date.now());
}

// Bar-width: one unit, two at most, never a clause. "19h", "2d 4h", "46m",
// and past the deadline the same shape with a minus, which reads as a fact
// rather than an alarm.
function formatShort(ms) {
    if (ms === null || ms === undefined)
        return "";
    var sign = ms < 0 ? "-" : "";
    var abs = Math.abs(ms);
    if (abs >= DAY_MS) {
        var days = Math.floor(abs / DAY_MS);
        var hours = Math.floor((abs % DAY_MS) / HOUR_MS);
        return sign + days + "d" + (hours > 0 ? " " + hours + "h" : "");
    }
    if (abs >= HOUR_MS) {
        var h = Math.floor(abs / HOUR_MS);
        var m = Math.floor((abs % HOUR_MS) / MINUTE_MS);
        return sign + h + "h" + (m > 0 ? " " + m + "m" : "");
    }
    var mins = Math.floor(abs / MINUTE_MS);
    return sign + Math.max(mins, 0) + "m";
}

// A hand-typed duration, in hours, from the panel's custom box. Tolerant on
// purpose: "36", "36h", "36 hours" and " 36 " all mean the same thing to
// whoever typed them, and a field that refuses one of those is a field people
// stop using. A fraction is honoured — "1.5" is 90 minutes, a real size for a
// small goal.
//
// Returns milliseconds, or 0 when there is no positive number in the string.
// Callers treat 0 as "do nothing": inventing a deadline out of typing noise
// would be worse than ignoring it, because the deadline is the one field the
// whole widget is built to be honest about.
function parseHours(raw) {
    var digits = String(raw === undefined || raw === null ? "" : raw).replace(/[^0-9.]/g, "");
    var hours = parseFloat(digits);
    if (!isFinite(hours) || !(hours > 0))
        return 0;
    return Math.round(hours * HOUR_MS);
}

// What the bar renders, as three parts rather than one joined string: the
// widget weights the name and colours the clock differently, and building
// that out of markup would mean handing a Text a rich-text string (which
// StyledText refuses by design, for good reason). An absent part is "" and
// the widget simply does not draw it — which is how the invariant holds that
// the clock never appears without the name and ratio beside it.
function barParts(goal, nowMs) {
    if (!goal)
        return {
            name: "",
            ratio: "",
            time: ""
        };
    var p = progress(goal);
    return {
        name: goal.name,
        ratio: p.total > 0 ? p.done + "/" + p.total : "",
        time: formatShort(timeLeftMs(goal, nowMs))
    };
}

function isOverdue(goal, nowMs) {
    var left = timeLeftMs(goal, nowMs);
    return left !== null && left < 0;
}

// Rows for the panel's ListModel. Role names are prefixed — `id` itself is
// unusable as a role (it collides with the QML id keyword in a required
// property), the NotesModel lesson.
function taskRows(goal) {
    var tasks = goal && goal.tasks ? goal.tasks : [];
    var next = nextTask(goal);
    return tasks.map(function (t) {
        return {
            taskId: t.id,
            taskText: t.text,
            taskDone: !!t.done,
            taskIsNext: !!next && next.id === t.id
        };
    });
}

// ------------------------------------------------------------------- merge
// Newest updatedAt wins (both writers stamp UTC ISO of one length, so string
// order IS time order). Ties break deterministically — tombstone first, then
// the larger serialized form — so every machine resolves the same pair the
// same way and the fleet converges instead of ping-ponging.
function wins(a, b) {
    if (a.updatedAt !== b.updatedAt)
        return a.updatedAt > b.updatedAt;
    if (!!a.deletedAt !== !!b.deletedAt)
        return !!a.deletedAt;
    return JSON.stringify(a) > JSON.stringify(b);
}

function mergeTasks(a, b) {
    var byId = {};
    var order = [];
    var take = function (list) {
        for (var i = 0; i < list.length; i++) {
            var t = list[i];
            if (!byId[t.id])
                order.push(t.id);
            if (!byId[t.id] || t.updatedAt > byId[t.id].updatedAt || (t.updatedAt === byId[t.id].updatedAt && JSON.stringify(t) > JSON.stringify(byId[t.id])))
                byId[t.id] = t;
        }
    };
    take(a);
    take(b);
    return order.map(function (id) {
        return byId[id];
    });
}

// Scalars from the newer goal as a set; tasks unioned per id regardless of
// which side is newer, so simultaneous ticks on two machines both survive.
function mergeGoal(a, b) {
    var newer = wins(a, b) ? a : b;
    if (newer.deletedAt)
        return newer;
    return normalizeGoal(Object.assign({}, newer, {
        tasks: mergeTasks(a.tasks || [], b.tasks || [])
    }));
}

// At most one active, chosen the same way on every machine.
function resolveActive(goals) {
    var actives = goals.filter(function (g) {
        return !g.deletedAt && g.state === "active";
    });
    if (actives.length < 2)
        return goals;
    var keep = actives[0];
    for (var i = 1; i < actives.length; i++)
        if (wins(actives[i], keep))
            keep = actives[i];
    return goals.map(function (g) {
        if (g.state !== "active" || g.deletedAt || g.id === keep.id)
            return g;
        return normalizeGoal(Object.assign({}, g, {
            state: "queued"
        }));
    });
}

function mergeStores(lists, nowMs) {
    var at = typeof nowMs === "number" ? nowMs : Date.now();
    var byId = {};
    for (var i = 0; i < lists.length; i++) {
        var list = lists[i] || [];
        for (var j = 0; j < list.length; j++) {
            var g = normalizeGoal(list[j]);
            byId[g.id] = byId[g.id] ? mergeGoal(g, byId[g.id]) : g;
        }
    }
    var out = [];
    for (var id in byId) {
        var goal = byId[id];
        if (goal.deletedAt && at - Date.parse(goal.deletedAt) > TOMBSTONE_TTL_MS)
            continue;
        out.push(goal);
    }
    // Creation order, so every machine renders the same list.
    out.sort(function (a, b) {
        var ka = a.createdAt + "|" + a.id, kb = b.createdAt + "|" + b.id;
        return ka < kb ? -1 : (ka > kb ? 1 : 0);
    });
    return resolveActive(out);
}

if (typeof module !== "undefined") {
    module.exports = {
        DAY_MS: DAY_MS,
        EPOCH: EPOCH,
        HOUR_MS: HOUR_MS,
        MINUTE_MS: MINUTE_MS,
        TOMBSTONE_TTL_MS: TOMBSTONE_TTL_MS,
        activateGoal: activateGoal,
        activeGoal: activeGoal,
        addGoal: addGoal,
        addTask: addTask,
        barParts: barParts,
        derivedId: derivedId,
        extendDue: extendDue,
        findGoal: findGoal,
        formatShort: formatShort,
        isOverdue: isOverdue,
        liveGoals: liveGoals,
        makeGoal: makeGoal,
        makeTask: makeTask,
        mergeStores: mergeStores,
        newId: newId,
        nextTask: nextTask,
        normalizeGoal: normalizeGoal,
        normalizeTask: normalizeTask,
        parseHours: parseHours,
        parseStore: parseStore,
        progress: progress,
        queuedGoals: queuedGoals,
        removeGoal: removeGoal,
        removeTask: removeTask,
        resolveActive: resolveActive,
        serialize: serialize,
        shipGoal: shipGoal,
        shippedCount: shippedCount,
        shippedGoals: shippedGoals,
        taskRows: taskRows,
        timeLeftMs: timeLeftMs,
        toggleTask: toggleTask
    };
}

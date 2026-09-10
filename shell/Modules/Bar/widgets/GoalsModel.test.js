// Unit tests for GoalsModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/GoalsModel.test.js
//
// The weight is on the merge and on the hand-edit path, because those are the
// two places a bug is silent: a lost tick looks like "I must have imagined
// ticking that", and a duplicated hand-typed task looks like the file was
// edited twice. Formatting bugs, by contrast, announce themselves in the bar.

const assert = require("node:assert/strict");
const Model = require("./GoalsModel.js");

let failures = 0;
function test(name, fn) {
    try {
        fn();
        console.log(`  ok  ${name}`);
    } catch (error) {
        failures += 1;
        console.log(`FAIL  ${name}\n      ${error.message}`);
    }
}

// A fixed clock so the deadline arithmetic is not a race. This is the real
// SplitRoute shape: due tomorrow afternoon, seven tasks, three done.
const NOW = Date.parse("2026-09-10T19:00:00.000Z");
const DUE = "2026-09-11T14:00:00.000Z";

const T11 = "2026-09-10T11:00:00.000Z";
const T12 = "2026-09-10T12:00:00.000Z";
const T13 = "2026-09-10T13:00:00.000Z";

// Restamp a goal, and optionally one of its tasks, so a test can say "this
// edit happened later" outright. Without it the writers all stamp Date.now()
// and a whole test body runs inside one millisecond — every cross-machine
// comparison would collapse onto the deterministic tie-break and prove
// nothing about which edit actually won.
function stamp(goals, goalId, at, taskId) {
    return goals.map(g => {
        if (g.id !== goalId)
            return g;
        const next = Object.assign({}, g, { updatedAt: at });
        if (taskId)
            next.tasks = g.tasks.map(t => t.id === taskId ? Object.assign({}, t, { updatedAt: at }) : t);
        return next;
    });
}

function actives(goals) {
    return Model.liveGoals(goals).filter(g => g.state === "active");
}

function fixture() {
    return Model.parseStore(JSON.stringify({
        version: 1,
        goals: [{
            id: "g1",
            name: "SplitRoute",
            due: DUE,
            state: "active",
            createdAt: "2026-09-10T06:00:00.000Z",
            updatedAt: "2026-09-10T06:00:00.000Z",
            tasks: [
                { id: "t1", text: "OAuth flow", done: true, updatedAt: "2026-09-10T08:00:00.000Z" },
                { id: "t2", text: "Billing API", done: true, updatedAt: "2026-09-10T09:00:00.000Z" },
                { id: "t3", text: "Webhook handler", done: true, updatedAt: "2026-09-10T10:00:00.000Z" },
                { id: "t4", text: "Listing screenshots", done: false, updatedAt: Model.EPOCH },
                { id: "t5", text: "Privacy policy page", done: false, updatedAt: Model.EPOCH },
                { id: "t6", text: "App store copy", done: false, updatedAt: Model.EPOCH },
                { id: "t7", text: "Submit for review", done: false, updatedAt: Model.EPOCH }
            ]
        }]
    }));
}

// --------------------------------------------------------------- reading

test("progress counts ticks, not tasks", () => {
    const p = Model.progress(Model.activeGoal(fixture()));
    assert.equal(p.done, 3);
    assert.equal(p.total, 7);
    assert.ok(Math.abs(p.ratio - 3 / 7) < 1e-9);
});

test("the bar shows name, ratio and clock together — never the clock alone", () => {
    const parts = Model.barParts(Model.activeGoal(fixture()), NOW);
    assert.equal(parts.name, "SplitRoute");
    assert.equal(parts.ratio, "3/7");
    assert.equal(parts.time, "19h");
});

test("next task is the first unticked one", () => {
    assert.equal(Model.nextTask(Model.activeGoal(fixture())).text, "Listing screenshots");
});

test("a goal with every task ticked has no next task", () => {
    let goals = fixture();
    for (const t of ["t4", "t5", "t6", "t7"])
        goals = Model.toggleTask(goals, "g1", t);
    assert.equal(Model.nextTask(Model.activeGoal(goals)), null);
    assert.equal(Model.progress(Model.activeGoal(goals)).done, 7);
});

test("taskRows marks exactly one row as next", () => {
    const rows = Model.taskRows(Model.activeGoal(fixture()));
    assert.equal(rows.filter(r => r.taskIsNext).length, 1);
    assert.equal(rows.find(r => r.taskIsNext).taskText, "Listing screenshots");
});

// -------------------------------------------------------------- the clock

test("formatShort keeps to one or two units", () => {
    assert.equal(Model.formatShort(19 * Model.HOUR_MS), "19h");
    assert.equal(Model.formatShort(19 * Model.HOUR_MS + 24 * Model.MINUTE_MS), "19h 24m");
    assert.equal(Model.formatShort(46 * Model.MINUTE_MS), "46m");
    assert.equal(Model.formatShort(2 * Model.DAY_MS), "2d");
    assert.equal(Model.formatShort(2 * Model.DAY_MS + 4 * Model.HOUR_MS), "2d 4h");
});

test("overdue reads as a fact, not an alarm", () => {
    assert.equal(Model.formatShort(-6 * Model.HOUR_MS), "-6h");
    const goals = fixture();
    const late = Date.parse(DUE) + 6 * Model.HOUR_MS;
    assert.ok(Model.isOverdue(Model.activeGoal(goals), late));
    assert.ok(!Model.isOverdue(Model.activeGoal(goals), NOW));
});

// The panel's custom-duration box. Nonsense must produce 0 (do nothing)
// rather than a goal with a garbage deadline.
test("a typed duration in hours parses however it was written", () => {
    assert.equal(Model.parseHours("36"), 36 * Model.HOUR_MS);
    assert.equal(Model.parseHours("36h"), 36 * Model.HOUR_MS);
    assert.equal(Model.parseHours("36 hours"), 36 * Model.HOUR_MS);
    assert.equal(Model.parseHours("  8 "), 8 * Model.HOUR_MS);
    assert.equal(Model.parseHours("1.5"), 90 * Model.MINUTE_MS, "fractions are real goal sizes");
});

test("a typed duration that means nothing sets no deadline", () => {
    for (const junk of ["", "   ", "abc", "0", "0.0", "h", ".", null, undefined])
        assert.equal(Model.parseHours(junk), 0, `expected 0 for ${JSON.stringify(junk)}`);
});

test("a typed duration survives the round trip into a real deadline", () => {
    const ms = Model.parseHours("36h");
    let goals = Model.addGoal([], Model.makeGoal("Custom", new Date(NOW + ms).toISOString(), "active"));
    assert.equal(Model.formatShort(Model.timeLeftMs(Model.activeGoal(goals), NOW)), "1d 12h");
});

test("a goal with no deadline still renders, without a clock", () => {
    const goals = Model.addGoal([], Model.makeGoal("Someday", "", "active"));
    assert.equal(Model.timeLeftMs(Model.activeGoal(goals), NOW), null);
    const parts = Model.barParts(Model.activeGoal(goals), NOW);
    assert.equal(parts.name, "Someday");
    assert.equal(parts.time, "", "no deadline means no clock is drawn");
    assert.equal(parts.ratio, "", "no tasks means no ratio is drawn");
});

test("extending runs from now, not from a deadline already blown", () => {
    const late = Date.parse(DUE) + 3 * Model.DAY_MS;
    const goals = Model.extendDue(fixture(), "g1", Model.DAY_MS, late);
    const left = Model.timeLeftMs(Model.activeGoal(goals), late);
    assert.ok(Math.abs(left - Model.DAY_MS) < 1000, `expected ~24h left, got ${Model.formatShort(left)}`);
});

// The queued-goal path: a goal parked with no deadline gets one when it is
// started, rather than burning a clock nobody was watching.
test("extending a goal with no deadline starts its clock from now", () => {
    let goals = Model.addGoal([], Model.makeGoal("Pawsome", "", "active"));
    const id = Model.activeGoal(goals).id;
    assert.equal(Model.timeLeftMs(Model.activeGoal(goals), NOW), null, "no clock to begin with");
    goals = Model.extendDue(goals, id, 2 * Model.DAY_MS, NOW);
    const left = Model.timeLeftMs(Model.activeGoal(goals), NOW);
    assert.ok(Math.abs(left - 2 * Model.DAY_MS) < 1000, `expected ~2d, got ${Model.formatShort(left)}`);
});

test("extending a goal that is still in the future adds to the deadline", () => {
    const goals = Model.extendDue(fixture(), "g1", Model.DAY_MS, NOW);
    const left = Model.timeLeftMs(Model.activeGoal(goals), NOW);
    assert.ok(Math.abs(left - (19 * Model.HOUR_MS + Model.DAY_MS)) < 1000);
});

// ------------------------------------------------------------- one active

test("activating a second goal demotes the first", () => {
    let goals = Model.addGoal(fixture(), Model.makeGoal("Pawsome", "", "queued"));
    const pawsome = goals.find(g => g.name === "Pawsome");
    goals = Model.activateGoal(goals, pawsome.id);
    assert.equal(Model.activeGoal(goals).name, "Pawsome");
    assert.equal(Model.queuedGoals(goals).map(g => g.name).join(), "SplitRoute");
});

test("shipping does not auto-promote — the next goal is a decision", () => {
    let goals = Model.addGoal(fixture(), Model.makeGoal("Pawsome", "", "queued"));
    goals = Model.shipGoal(goals, "g1");
    assert.equal(Model.activeGoal(goals), null);
    assert.equal(Model.shippedCount(goals), 1);
    assert.equal(Model.queuedGoals(goals).length, 1);
});

// The mis-ship path: ship is one click by design, so undoing it has to be
// one click too, and the restarted goal must stop counting as a win.
test("a shipped goal can be started again and stops counting as shipped", () => {
    let goals = Model.shipGoal(fixture(), "g1");
    assert.equal(Model.shippedCount(goals), 1);
    assert.equal(Model.activeGoal(goals), null);
    goals = Model.activateGoal(goals, "g1");
    assert.equal(Model.activeGoal(goals).name, "SplitRoute");
    assert.equal(Model.shippedCount(goals), 0, "it is back in progress, not a win");
    assert.equal(Model.activeGoal(goals).shippedAt, undefined, "the ship stamp must be cleared");
    assert.equal(Model.progress(Model.activeGoal(goals)).done, 3, "its ticks survive the round trip");
});

test("the shipped ledger survives and lists newest first", () => {
    let goals = Model.addGoal(fixture(), Model.makeGoal("Pawsome", "", "queued"));
    const pawsome = goals.find(g => g.name === "Pawsome");
    goals = Model.shipGoal(goals, "g1");
    goals = Model.shipGoal(goals, pawsome.id);
    goals = goals.map(g => Object.assign({}, g, {
        shippedAt: g.id === "g1" ? "2026-09-11T09:00:00.000Z" : "2026-09-12T09:00:00.000Z"
    }));
    assert.equal(Model.shippedCount(goals), 2);
    assert.equal(Model.shippedGoals(goals)[0].name, "Pawsome");
});

test("two goals shipped in the same millisecond still order identically everywhere", () => {
    let goals = Model.addGoal(fixture(), Model.makeGoal("Pawsome", "", "queued"));
    const pawsome = goals.find(g => g.name === "Pawsome");
    goals = Model.shipGoal(Model.shipGoal(goals, "g1"), pawsome.id);
    const at = "2026-09-11T09:00:00.000Z";
    goals = goals.map(g => Object.assign({}, g, { shippedAt: at }));
    const forward = Model.shippedGoals(goals).map(g => g.id);
    const reversed = Model.shippedGoals(goals.slice().reverse()).map(g => g.id);
    assert.deepEqual(forward, reversed, "the ledger must not depend on store order");
});

// ------------------------------------------------------------ hand editing

test("a hand-typed task with no id gets a stable id, not a minted one", () => {
    const raw = JSON.stringify({
        version: 1,
        goals: [{ id: "g1", name: "SplitRoute", state: "active", tasks: [{ text: "Submit for review" }] }]
    });
    const a = Model.parseStore(raw);
    const b = Model.parseStore(raw);
    assert.equal(a[0].tasks[0].id, b[0].tasks[0].id, "two machines must derive the same id");
    assert.equal(a[0].tasks[0].id, Model.derivedId("g1", "Submit for review"));
});

test("the same hand-typed task on two machines merges to one row", () => {
    const raw = JSON.stringify({
        version: 1,
        goals: [{ id: "g1", name: "SplitRoute", state: "active", tasks: [{ text: "Submit for review" }] }]
    });
    const merged = Model.mergeStores([Model.parseStore(raw), Model.parseStore(raw)], NOW);
    assert.equal(merged.length, 1);
    assert.equal(merged[0].tasks.length, 1, "a hand-typed task must not triplicate across the fleet");
});

test("junk and empty input read as an empty store, not a crash", () => {
    assert.deepEqual(Model.parseStore(""), []);
    assert.deepEqual(Model.parseStore("not json at all"), []);
    assert.deepEqual(Model.parseStore('{"version":1}'), []);
    assert.deepEqual(Model.parseStore('{"version":1,"goals":"nope"}'), []);
});

test("a goal survives being stripped to just a name", () => {
    const goals = Model.parseStore('{"version":1,"goals":[{"name":"SplitRoute"}]}');
    assert.equal(goals.length, 1);
    assert.equal(goals[0].state, "queued", "an unstated state must not silently become active");
    assert.deepEqual(goals[0].tasks, []);
});

test("a store round-trips through serialize unchanged", () => {
    const goals = fixture();
    assert.deepEqual(Model.parseStore(Model.serialize(goals)), goals);
});

// ------------------------------------------------------------------ merge

test("two machines ticking different tasks keep both ticks", () => {
    const laptop = Model.toggleTask(fixture(), "g1", "t4");
    const mini = Model.toggleTask(fixture(), "g1", "t5");
    const merged = Model.mergeStores([laptop, mini], NOW);
    const p = Model.progress(Model.activeGoal(merged));
    assert.equal(p.done, 5, "a tick made on the other machine must not vanish");
});

test("the newer edit of one task wins", () => {
    // Ticked on the laptop at 12:00. On the mini it was ticked and then
    // unticked, last touched at 13:00 — so the untick is the live answer.
    const laptop = stamp(Model.toggleTask(fixture(), "g1", "t4"), "g1", T12, "t4");
    const twice = Model.toggleTask(Model.toggleTask(fixture(), "g1", "t4"), "g1", "t4");
    const mini = stamp(twice, "g1", T13, "t4");
    const merged = Model.mergeStores([laptop, mini], NOW);
    const t4 = Model.activeGoal(merged).tasks.find(t => t.id === "t4");
    assert.equal(t4.done, false, "the untick came later, so it wins");
});

test("a task added on one machine appears on both", () => {
    const laptop = Model.addTask(fixture(), "g1", Model.makeTask("App store banner"));
    const merged = Model.mergeStores([laptop, fixture()], NOW);
    assert.equal(Model.activeGoal(merged).tasks.length, 8);
});

test("merging is order-independent and idempotent", () => {
    const laptop = Model.toggleTask(fixture(), "g1", "t4");
    const mini = Model.toggleTask(fixture(), "g1", "t5");
    const ab = Model.mergeStores([laptop, mini], NOW);
    const ba = Model.mergeStores([mini, laptop], NOW);
    assert.deepEqual(ab, ba, "every machine must land on the same store");
    assert.deepEqual(Model.mergeStores([ab], NOW), ab, "a second round must change nothing");
});

test("two machines each activating a different goal converge on one", () => {
    const base = Model.addGoal(fixture(), Model.makeGoal("Pawsome", "", "queued"));
    const pawsome = base.find(g => g.name === "Pawsome");
    // The laptop switches to Pawsome at 12:00. The mini, still offline,
    // re-starts SplitRoute at 13:00 — so both machines think they have an
    // active goal, and they disagree about which.
    let laptop = Model.activateGoal(base, pawsome.id);
    laptop = stamp(stamp(laptop, pawsome.id, T12), "g1", T12);
    let mini = Model.activateGoal(base, "g1");
    mini = stamp(stamp(mini, "g1", T13), pawsome.id, T11);
    const ab = Model.mergeStores([laptop, mini], NOW);
    const ba = Model.mergeStores([mini, laptop], NOW);
    assert.equal(actives(ab).length, 1, "exactly one active goal survives");
    assert.equal(actives(ab)[0].name, "SplitRoute", "the later activation is the live one");
    assert.deepEqual(ab, ba, "both machines must pick the same winner");
});

test("a deletion propagates instead of resurrecting", () => {
    const laptop = Model.removeGoal(fixture(), "g1");
    const merged = Model.mergeStores([laptop, fixture()], NOW);
    assert.equal(Model.liveGoals(merged).length, 0, "the untouched machine must not bring it back");
});

test("a tombstone is pruned once every machine has had the TTL to hear it", () => {
    const laptop = Model.removeGoal(fixture(), "g1");
    const later = NOW + Model.TOMBSTONE_TTL_MS + Model.DAY_MS;
    assert.equal(Model.mergeStores([laptop], later).length, 0);
    assert.equal(Model.mergeStores([laptop], NOW).length, 1, "…but not before");
});

test("a machine with no store yet adopts the others", () => {
    const merged = Model.mergeStores([[], fixture()], NOW);
    assert.equal(Model.activeGoal(merged).name, "SplitRoute");
    assert.equal(Model.progress(Model.activeGoal(merged)).done, 3);
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

import QtQuick
import Quickshell
import Quickshell.Io
import "GoalsModel.js" as Model

// Goals service — everything the goals widget and its panel read, for the one
// active goal this machine is working toward. In the shape of the notes store
// and the hub-sync service: GoalsModel.js owns every semantic, this owns the
// file and the clock, and nothing here decides what a goal means.
//
// There is no polling and no process. The store is a single JSON file watched
// by a FileView, so a tick made in the panel, a task typed into the file in an
// editor, and a merge landed by a sync round all light up the bar identically
// and live.
//
// The one clock is a 60-second tick that only re-stamps `nowMs` — the same
// allowance HubSyncService's clock takes, and for the same reason: it starts
// no process and touches no network. It exists because "19h 24m" stops being
// true a minute after the bar draws it, and a countdown that lies is worse
// than no countdown.
QtObject {
    id: root

    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/qshell/goals";
    }
    readonly property string storePath: stateDir + "/goals.json"

    property var goals: []
    property bool loaded: false
    property real nowMs: Date.now()

    // ------------------------------------------------------------- reading
    readonly property var active: Model.activeGoal(goals)
    readonly property var queued: Model.queuedGoals(goals)
    readonly property var shipped: Model.shippedGoals(goals)
    readonly property int shippedCount: Model.shippedCount(goals)

    readonly property bool hasActive: !!active
    readonly property var activeProgress: Model.progress(active)
    readonly property int doneCount: activeProgress.done
    readonly property int totalCount: activeProgress.total
    readonly property real ratio: activeProgress.ratio

    // What the bar renders, split so the widget can weight the name and
    // colour the clock. Each part is "" when it has nothing to say, and the
    // widget drops the ones that are empty.
    readonly property var barParts: Model.barParts(active, nowMs)
    readonly property string barName: barParts.name
    readonly property string barRatio: barParts.ratio
    readonly property string barTime: barParts.time

    readonly property bool overdue: hasActive && Model.isOverdue(active, nowMs)

    // A goal can be active with no deadline at all — one started from the
    // queue before anyone decided how long it gets. The bar simply omits the
    // clock in that case, so the panel has to be the place that offers one.
    readonly property bool hasDeadline: hasActive && barTime !== ""
    readonly property string timeLeftText: Model.formatShort(Model.timeLeftMs(active, nowMs))

    readonly property var nextTask: Model.nextTask(active)
    readonly property string nextText: nextTask ? nextTask.text : ""

    readonly property string tooltip: {
        if (!hasActive)
            return shippedCount > 0 ? "No active goal — " + shippedCount + " shipped" : "No active goal";
        const lines = [active.name];
        if (totalCount > 0)
            lines.push(doneCount + " of " + totalCount + " done");
        if (timeLeftText !== "")
            lines.push(overdue ? timeLeftText.replace("-", "") + " overdue" : timeLeftText + " left");
        const head = lines.join(" — ");
        return nextText !== "" ? head + "\nNext: " + nextText : head;
    }

    function rowsForActive() {
        return Model.taskRows(active);
    }

    // ------------------------------------------------------------- writing
    // Every mutation goes through here: the model returns a new store, this
    // swaps it in and writes. Keeping the write in one place is what makes
    // the echo guard in load() enough.
    function apply(next) {
        goals = next;
        storeFile.setText(Model.serialize(goals));
    }

    function toggleTask(taskId) {
        if (active)
            apply(Model.toggleTask(goals, active.id, taskId));
    }

    function addTask(text) {
        const t = String(text || "").trim();
        if (t !== "" && active)
            apply(Model.addTask(goals, active.id, Model.makeTask(t)));
    }

    function removeTask(taskId) {
        if (active)
            apply(Model.removeTask(goals, active.id, taskId));
    }

    // Shipping is the whole point of the widget, so it is deliberately not
    // guarded on every task being ticked: shipping with two chores unticked
    // is a real thing that happens, and a tracker that refuses to record the
    // win because its own checklist disagrees is a tracker you stop using.
    function ship() {
        if (active)
            apply(Model.shipGoal(goals, active.id));
    }

    function startGoal(goalId) {
        apply(Model.activateGoal(goals, goalId));
    }

    function extend(ms) {
        if (active)
            apply(Model.extendDue(goals, active.id, ms, nowMs));
    }

    function addGoal(name, dueIso, activateNow) {
        const n = String(name || "").trim();
        if (n === "")
            return;
        const goal = Model.makeGoal(n, dueIso, "queued");
        const next = Model.addGoal(goals, goal);
        apply(activateNow ? Model.activateGoal(next, goal.id) : next);
    }

    function removeGoal(goalId) {
        apply(Model.removeGoal(goals, goalId));
    }

    function load(raw) {
        // Our own atomic write echoes back through the watcher. Rebuilding on
        // it would reset the panel's scroll position for nothing, and — once
        // the sync unit lands — would fight a merge that has not changed
        // anything.
        if (loaded && String(raw || "") === Model.serialize(goals))
            return;
        goals = Model.parseStore(raw);
        loaded = true;
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

    // -------------------------------------------------------------- sources
    readonly property FileView storeFile: FileView {
        path: root.storePath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.load(text())
        // No file yet is the fresh-machine case, not a failure: an empty
        // store reads as "no goals", which is exactly what it is.
        onLoadFailed: root.load("")
        onFileChanged: reload()
        onSaveFailed: error => console.warn("Goals: store write failed:", error)
    }

    readonly property Timer clock: Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
    }
}

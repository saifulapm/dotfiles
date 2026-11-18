import Quickshell
import Quickshell.Io
import QtQuick
import ".." as Root
import "../lib/notes.mjs" as N
import "../lib/reminders.mjs" as R

// The launcher's reminders, in this machine's file of the synced store, so every machine holds the same pending list.
Scope {
    id: reminders

    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/dots/reminders"
    readonly property string machine: N.machineId(Quickshell.env("DOTS_MACHINE"), chezmoiFile.text(), hostnameFile.text())
    readonly property string path: dir + "/" + machine + ".json"
    // Where reminders lived before they synced; its list moves into the store once.
    readonly property string oldPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/reminders.json"

    property var store: R.emptyStore()
    // Pending ones, soonest first, each {id, text, due, created}.
    readonly property var list: R.pendingList(store)
    property bool ready: false
    // Set while the store file does not parse; saving then would replace every reminder in it.
    property bool storeBroken: false
    // Set while the old file does not parse; it is left as it is until fixed by hand.
    property bool oldBroken: false
    // What the launcher's r row says while nothing can be set, or "".
    readonly property string brokenText: oldBroken ? R.BROKEN : storeBroken ? R.brokenStore(machine) : ""
    readonly property bool broken: brokenText !== ""
    // The text this shell last wrote, so the reload its own write triggers is skipped.
    property string written: ""
    // The old file's list, held until the store has loaded.
    property var oldList: null
    // The Clock service's minute; each tick rings what has come due.
    property var now: null

    onNowChanged: ring()

    // The soonest reminder rings at its own second, not at the next minute tick; the timer runs only while one waits.
    readonly property real soonest: list.length ? Math.min(...list.map(r => r.due)) : 0
    onSoonestChanged: {
        dueTick.stop();
        if (soonest) {
            dueTick.interval = Math.max(0, Math.min(soonest - Date.now(), 2147483647));
            dueTick.start();
        }
    }

    // A coarse timer may fire a little early, so one that finds nothing due yet waits the rest.
    Root.Tick {
        id: dueTick
        onTriggered: {
            reminders.ring();
            if (reminders.soonest > Date.now()) {
                interval = reminders.soonest - Date.now() + 50;
                start();
            }
        }
    }

    // Rings what came due under a minute ago; one due longer ago waits for a reminders round, which may bring it back rung by another machine.
    function ring() {
        if (!ready)
            return;
        const t = Date.now();
        const due = R.dueSplit(list, t);
        notify(due.fresh, [], t);
        if (due.stale.length && !round.running)
            round.running = true;
    }

    // After a round: each due reminder still pending rings, and one overdue rings late when the round could not pull.
    function settle() {
        const pulled = roundResult === "pulled";
        roundResult = "";
        const t = Date.now();
        const due = R.dueSplit(list, t);
        if (pulled)
            notify(due.fresh.concat(due.stale), [], t);
        else
            notify(due.fresh, due.stale, t);
    }

    // Marks each rung in the store, then raises its notification, so a crash between the two never rings it twice.
    function notify(plain, late, t) {
        const all = plain.concat(late);
        if (!all.length || !save(all.reduce((s, r) => R.endReminder(s, r.id, "rung", t), store)))
            return;
        for (const r of plain) {
            const f = R.firedText(r, t);
            Quickshell.execDetached(["notify-send", "-a", "Reminders", f.summary, f.body]);
        }
        for (const r of late) {
            const f = R.lateText(r, t);
            Quickshell.execDetached(["notify-send", "-a", "Reminders", f.summary, f.body]);
        }
    }

    // "pulled" or "failed" once a round ends, until the store it left is read.
    property string roundResult: ""

    // A round that waits on the sync lock or a dead network still lets the reminder ring, late, within 30 s.
    Process {
        id: round
        command: ["timeout", "30", Quickshell.shellDir + "/bin/dots", "sync", "--only", "reminders"]
        stdout: StdioCollector {
            id: roundOut
        }
        onExited: code => {
            reminders.roundResult = R.roundPulled(code, roundOut.text) ? "pulled" : "failed";
            storeFile.reload();
        }
    }

    // Sets a parsed reminder as of now; returns why it was not set, or "".
    function add(remind, now) {
        if (broken)
            return brokenText;
        const r = R.setReminder(store, remind, now);
        if (r.error)
            return r.error;
        save(r.store);
        return "";
    }

    function remove(id) {
        save(R.endReminder(store, id, "removed", Date.now()));
    }

    // False when nothing was saved.
    function save(next) {
        if (storeBroken || !ready)
            return false;
        store = next;
        written = JSON.stringify(next) + "\n";
        storeFile.setText(written);
        return true;
    }

    // The old list joins whatever the store already holds, then the old file is renamed, so a second start finds nothing to move.
    function migrate() {
        if (!ready || storeBroken || oldList === null)
            return;
        save(R.migrateOld(store, oldList));
        oldList = null;
        mover.running = true;
    }

    Process {
        id: mover
        command: ["mv", "-f", reminders.oldPath, reminders.oldPath + ".migrated"]
    }

    FileView {
        id: chezmoiFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/chezmoi/chezmoi.toml"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: hostnameFile
        path: "/etc/hostname"
        blockLoading: true
        printErrors: false
    }

    // The store's folder may not exist yet, and a write into a missing folder fails.
    Process {
        running: true
        command: ["mkdir", "-p", reminders.dir]
        onExited: storeFile.path = reminders.path
    }

    FileView {
        id: storeFile
        // A ring is marked on disk before its notification runs.
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const own = text() === reminders.written && reminders.ready && !reminders.storeBroken;
            if (!own) {
                const parsed = R.parseStore(text());
                reminders.storeBroken = parsed === null;
                if (parsed === null)
                    console.warn("reminders: " + reminders.path + " does not parse; nothing is saved until it does");
                else
                    reminders.store = parsed;
                reminders.ready = true;
                reminders.migrate();
            }
            if (reminders.roundResult)
                reminders.settle();
            else if (!own)
                // One that came due while the shell was stopped rings now, or after its round.
                reminders.ring();
        }
        onLoadFailed: {
            reminders.ready = true;
            reminders.migrate();
            if (reminders.roundResult)
                reminders.settle();
        }
    }

    FileView {
        id: oldFile
        path: reminders.oldPath
        printErrors: false
        // A file fixed by hand is read again at once.
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const r = R.readReminders(text());
            reminders.oldBroken = r.broken;
            if (r.broken) {
                console.warn("reminders: " + reminders.oldPath + " does not parse; leaving it as it is");
                return;
            }
            reminders.oldList = r.list;
            reminders.migrate();
        }
        onLoadFailed: reminders.oldBroken = false
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/reminders.mjs" as R

// The launcher's reminders, kept in the state dir so they outlive a restart or a reboot.
Scope {
    id: reminders

    // Soonest first, each {id, text, due, created}.
    property var list: []
    // A file that does not parse is left as it is, and nothing is set over it.
    property bool broken: false
    // The Clock service's minute; each tick rings what has come due.
    property var now: null

    onNowChanged: ring()

    // Rings each due reminder as an ordinary notification, after dropping it from the file, so a crash between the two never rings it twice.
    function ring() {
        const due = R.dueReminders(list, Date.now());
        if (!due.fire.length)
            return;
        list = due.keep;
        save();
        for (const r of due.fire) {
            const t = R.firedText(r, Date.now());
            Quickshell.execDetached(["notify-send", "-a", "Reminders", t.summary, t.body]);
        }
    }

    // Sets a parsed reminder as of now; returns why it was not set, or "".
    function add(remind, now) {
        if (broken)
            return "reminders.json does not parse; fix or remove it first";
        const r = R.addReminder(list, remind, now);
        if (r.error)
            return r.error;
        list = r.list;
        save();
        return "";
    }

    function remove(id) {
        list = list.filter(r => r.id !== id);
        save();
    }

    function save() {
        store.setText(JSON.stringify(list) + "\n");
    }

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/reminders.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                reminders.broken = false;
                const l = JSON.parse(text());
                reminders.list = Array.isArray(l) ? l.filter(r => r && typeof r.text === "string" && typeof r.due === "number") : [];
                // One that came due while the shell was stopped rings now.
                reminders.ring();
            } catch (e) {
                reminders.broken = true;
                console.warn("reminders: " + store.path + " does not parse; leaving it as it is: " + e.message);
            }
        }
    }
}

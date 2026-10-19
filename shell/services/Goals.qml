import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/goals.mjs" as G
import "../lib/notes.mjs" as N

// The goals store; it loads with the shell, so the margin shows the active goal without the Goals window.
Scope {
    id: goals

    // What a refusal says in the island.
    signal toast(string text)

    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/dots/goals"
    readonly property string machine: N.machineId(Quickshell.env("DOTS_MACHINE"), chezmoiFile.text(), hostnameFile.text())
    readonly property string path: dir + "/" + machine + ".json"
    property var store: G.emptyStore()
    property bool ready: false
    // Set while the store file does not parse; saving then would replace every goal in it.
    property bool broken: false
    // The text this shell last wrote, so the reload its own write triggers is skipped.
    property string written: ""

    function newId() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
    }

    // False when nothing was saved, so the caller keeps what was typed.
    function save(next) {
        if (next === store)
            return true;
        if (broken) {
            toast("Goals store unreadable");
            return false;
        }
        store = next;
        written = JSON.stringify(next, null, 1) + "\n";
        storeFile.setText(written);
        return true;
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
        command: ["mkdir", "-p", goals.dir]
        onExited: storeFile.path = goals.path
    }

    FileView {
        id: storeFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (text() === goals.written && goals.ready && !goals.broken)
                return;
            const parsed = G.parseStore(text());
            goals.broken = parsed === null;
            if (goals.broken) {
                console.warn("goals: " + goals.path + " does not parse; nothing is saved until it does");
                goals.ready = true;
                return;
            }
            goals.store = parsed;
            goals.ready = true;
        }
        onLoadFailed: goals.ready = true
    }
}

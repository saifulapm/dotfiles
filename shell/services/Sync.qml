import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/control-system.mjs" as Lib

// What the last dots sync round left in sync.json; Control's Route reads it, and a unit that starts to fail is told once.
Scope {
    id: sync

    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots"
    property var units: ({})

    // The watch needs the folder, and dots sync makes it only on its first round.
    Process {
        running: true
        command: ["mkdir", "-p", sync.dir]
        onExited: statusFile.path = sync.dir + "/sync.json"
    }

    FileView {
        id: statusFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const units = Lib.parseSync(text());
            // With the margins gone a failed round would show only in Control's Route, so it says so once.
            const failed = Lib.newlyFailing(sync.units, units);
            if (failed.length > 0)
                Quickshell.execDetached(["notify-send", "-a", "Sync", "Sync failed", failed.join(", ")]);
            sync.units = units;
        }
        onLoadFailed: sync.units = {}
    }
}

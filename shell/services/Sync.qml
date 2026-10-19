import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/control-system.mjs" as Lib

// What the last dots sync round left in sync.json; the margin and Control's Route read it.
Scope {
    id: sync

    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots"
    property var units: ({})
    readonly property bool failing: Lib.syncFailing(units)

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
        onLoaded: sync.units = Lib.parseSync(text())
        onLoadFailed: sync.units = {}
    }
}

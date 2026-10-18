import Quickshell
import Quickshell.Io
import QtQuick

// The active theme: its name from $XDG_STATE_HOME/dots/theme and its tokens from the
// renderer's theme-out/shell.json. Both files are watched, so a switch needs no restart.
Scope {
    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots"
    readonly property string name: nameFile.text().trim()
    readonly property var tokens: tokensFile.text() ? JSON.parse(tokensFile.text()) : null
    readonly property var color: tokens ? tokens.color : ({})

    FileView {
        id: nameFile
        path: dir + "/theme"
        watchChanges: true
        onFileChanged: reload()
    }

    FileView {
        id: tokensFile
        path: dir + "/theme-out/shell.json"
        watchChanges: true
        onFileChanged: reload()
    }
}

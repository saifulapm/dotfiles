import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/theme.mjs" as T

// Both files are watched, so a theme switch needs no restart.
Scope {
    id: theme

    // A failed switch's reason, for the island to show.
    signal notice(string text)

    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots"
    readonly property string name: nameFile.text().trim()
    // Only tokens that pass the theme check replace the last good ones, so a bad file never blanks the screen.
    property var tokens: null
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
        onLoaded: {
            try {
                tokens = T.checkTokens(JSON.parse(text()));
            } catch (e) {
                console.warn("theme: keeping the last good tokens: " + e.message);
            }
        }
    }

    // The file exists before the shell starts, so its first load is the state at start, never news.
    FileView {
        id: noticeFile
        property bool armed: false
        path: dir + "/theme-out/notice"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const text = noticeFile.text().trim();
            if (armed && text)
                theme.notice(text);
            armed = true;
        }
    }
}

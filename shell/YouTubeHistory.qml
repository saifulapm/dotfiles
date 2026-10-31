import Quickshell
import Quickshell.Io
import QtQuick
import "lib/youtube-history.mjs" as H

// The YouTube App's History, XDG_STATE_HOME/dots/youtube/history.json: the single videos played, newest first; it stays on this machine, so dots sync never sees it.
Scope {
    id: history

    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/youtube"
    property var entries: H.empty()
    readonly property var rows: H.rows(entries)
    // Set while the file does not parse; saving then would replace every entry in it.
    property bool broken: false
    // Set once the file is read, or found missing; a save before then would write an empty History over it.
    property bool ready: false

    // video is a row as youtube.mjs rows() makes it; a replay moves its entry to the top.
    function add(video) {
        if (!ready || broken)
            return;
        entries = H.add(entries, video, Date.now());
        historyFile.setText(H.serialize(entries));
    }

    // The folder may not exist yet, and a write into a missing folder fails.
    Process {
        running: true
        command: ["mkdir", "-p", history.dir]
        onExited: historyFile.path = history.dir + "/history.json"
    }

    FileView {
        id: historyFile
        printErrors: false
        onLoaded: {
            const parsed = H.parse(text());
            history.broken = parsed === null;
            if (history.broken)
                console.warn("youtube: " + path + " does not parse; nothing is added to History until it does");
            else
                history.entries = parsed;
            history.ready = true;
        }
        onLoadFailed: history.ready = true
    }
}

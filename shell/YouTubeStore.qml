import Quickshell
import Quickshell.Io
import QtQuick
import "lib/notes.mjs" as N
import "lib/youtube-playlists.mjs" as P

// The YouTube App's Playlists store, XDG_DATA_HOME/dots/youtube/<machine>.json, named per machine as the notes store is so dots sync can merge it.
Scope {
    id: store

    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/dots/youtube"
    readonly property string machine: N.machineId(Quickshell.env("DOTS_MACHINE"), chezmoiFile.text(), hostnameFile.text())
    property var playlists: P.emptyStore()
    // Set while the file does not parse; saving then would replace every Playlist in it.
    property bool broken: false
    // Set once the file is read, or found missing; a save before then would write an empty store over it.
    property bool ready: false
    readonly property var saved: P.items(playlists, "saved")

    // video is a row as youtube.mjs rows() makes it; a video already in Saved stays one copy.
    function save(video) {
        if (!ready || broken)
            return;
        const next = P.add(playlists, "saved", {
            id: video.id,
            title: video.title,
            channel: video.channel,
            duration: video.secs,
            thumb: video.thumb
        }, Date.now());
        if (next === playlists)
            return;
        playlists = next;
        storeFile.setText(P.serialize(next));
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
        command: ["mkdir", "-p", store.dir]
        onExited: storeFile.path = store.dir + "/" + store.machine + ".json"
    }

    FileView {
        id: storeFile
        printErrors: false
        onLoaded: {
            const parsed = P.parse(text());
            store.broken = parsed === null;
            if (store.broken)
                console.warn("youtube: " + path + " does not parse; nothing is saved until it does");
            else
                store.playlists = parsed;
            store.ready = true;
        }
        onLoadFailed: store.ready = true
    }
}

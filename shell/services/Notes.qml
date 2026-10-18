import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/notes.mjs" as N

// The notes store; it loads with the shell, so a capture never waits on the Notes window.
Scope {
    id: notes

    // What a capture or a refusal says in the island.
    signal toast(string text)

    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/dots/notes"
    readonly property string machine: N.machineId(Quickshell.env("DOTS_MACHINE"), chezmoiFile.text(), hostnameFile.text())
    readonly property string path: dir + "/" + machine + ".json"
    readonly property string attachments: dir + "/attachments"
    property var store: N.emptyStore()
    property bool ready: false
    // The text of the last capture, so the same primary selection twice makes one note.
    property string last: ""

    function newId() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
    }

    function save(next) {
        if (next === store)
            return;
        store = next;
        storeFile.setText(JSON.stringify(next, null, 1) + "\n");
    }

    function capture() {
        if (!ready || primary.running)
            return;
        primary.running = true;
    }

    // wl-copy serves the copy itself, so it works whichever window has focus.
    function copyText(text) {
        copier.command = ["wl-copy", "--", text];
        copier.running = true;
    }

    function copyFile(attachment) {
        copier.command = ["sh", "-c", 'exec wl-copy --type "$1" < "$2"', "sh", attachment.mime, attachments + "/" + N.attachmentFile(attachment)];
        copier.running = true;
    }

    // Onto the note with this id, or onto a new note when id is null.
    function attachClipboard(id) {
        if (attacher.running)
            return;
        attacher.target = id;
        attacher.running = true;
    }

    Process {
        id: copier
    }

    Process {
        id: attacher
        property var target: null
        command: ["dots-notes-attach", notes.attachments]
        stdout: StdioCollector {
            id: attached
        }
        onExited: code => {
            let found = [];
            try {
                found = JSON.parse(attached.text);
            } catch (e) {
                console.warn("notes: dots-notes-attach exited " + code + ": " + e.message);
            }
            const refused = found.filter(a => a.refused);
            notes.save(N.attachTo(notes.store, target, found.filter(a => !a.refused), Date.now(), notes.newId()));
            if (refused.length)
                notes.toast(refused[0].refused);
        }
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
        command: ["mkdir", "-p", notes.dir + "/attachments"]
        onExited: storeFile.path = notes.path
    }

    FileView {
        id: storeFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            notes.store = N.parseStore(text());
            if (!notes.ready)
                notes.last = N.lastCapture(notes.store);
            notes.ready = true;
        }
        onLoadFailed: notes.ready = true
    }

    // wl-paste reads the primary selection without taking or changing the clipboard.
    Process {
        id: primary
        command: ["wl-paste", "--primary", "--no-newline", "--type", "text"]
        stdout: StdioCollector {
            id: selection
        }
        onExited: code => {
            const r = N.capture(notes.store, code === 0 ? selection.text : "", notes.last, Date.now(), notes.newId());
            notes.last = r.last;
            notes.save(r.store);
            notes.toast(r.toast);
        }
    }
}

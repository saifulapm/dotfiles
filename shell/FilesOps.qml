import Quickshell
import Quickshell.Io
import QtQuick

// Runs bin/dots-files-op for a paste or a drop, off the render loop, and keeps what its JSON lines say: the progress, the file that failed, how it ended.
Scope {
    id: ops

    property bool running: false
    property string mode: ""
    // Each source as { path, name, size, dir }, in the order the op takes them.
    property var items: []
    property string from: ""
    property string target: ""
    // The target as the boards name it: its drive's label, else its folder's name.
    property string to: ""
    property real done: 0
    property real total: 0
    property real rate: 0
    property var copied: []
    // The failed event while the op waits for r, s or esc; null otherwise.
    property var failed: null
    // How it ended: the op's last event (done, cancelled, refused), or null when it died without one.
    signal ended(var last)

    // Beside the shell's bin/, as Share finds dots-taildrop-send.
    readonly property string bin: Quickshell.shellDir + "/../bin/dots-files-op"

    function start(how, list, fromDir, dest, name) {
        if (running || !list.length)
            return false;
        mode = how;
        items = list;
        from = fromDir;
        target = dest;
        to = name;
        done = 0;
        total = 0;
        rate = 0;
        copied = [];
        failed = null;
        proc.last = null;
        proc.command = [bin, how, dest].concat(list.map(i => i.path));
        running = true;
        proc.running = true;
        return true;
    }

    // ctrl+c: the op deletes the file it was writing and says cancelled.
    function cancel() {
        if (proc.running)
            proc.signal(15);
    }

    function answer(word) {
        if (!failed)
            return;
        failed = null;
        proc.write(word + "\n");
    }

    Process {
        id: proc
        property var last: null
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let e;
                try {
                    e = JSON.parse(line);
                } catch (x) {
                    return;
                }
                proc.last = e;
                if (e.event === "start")
                    ops.total = e.bytes;
                else if (e.event === "progress") {
                    ops.done = e.done;
                    ops.total = e.total;
                    ops.rate = e.rate;
                } else if (e.event === "item")
                    ops.copied = ops.copied.concat([e.index]);
                else if (e.event === "failed")
                    ops.failed = e;
            }
        }
        onExited: {
            ops.running = false;
            ops.failed = null;
            ops.ended(proc.last);
        }
    }
}

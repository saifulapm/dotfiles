import Quickshell
import Quickshell.Io
import QtQuick
import "lib/files.mjs" as F
import "lib/picker.mjs" as P

// The drives udiskie mounted under /run/media/$USER, read again on each mount or unmount findmnt reports; eject unmounts one and powers it off.
Scope {
    id: watch

    property string voice
    readonly property string user: Quickshell.env("USER")
    property string mounts: ""
    readonly property var drives: F.drives(voice, mounts, user)
    // Mounts that change while they are being read are read again.
    property bool stale: false
    // Why the last eject failed, on one line; a failed drive stays listed.
    property string error: ""

    function read() {
        if (reader.running) {
            stale = true;
            return;
        }
        reader.running = true;
    }

    function eject(path) {
        error = "";
        ejecter.command = ["udiskie-umount", "--detach", path];
        ejecter.running = true;
    }

    Component.onCompleted: read()

    // One line a mount or unmount, so the list follows without a timer.
    Process {
        running: true
        command: ["findmnt", "--poll", "-n", "-o", "ACTION"]
        stdout: SplitParser {
            onRead: watch.read()
        }
    }

    Process {
        id: reader
        command: ["findmnt", "--list", "--json", "-b", "-o", "TARGET,LABEL,SIZE"]
        stdout: StdioCollector {
            id: readOut
        }
        onExited: {
            if (watch.stale) {
                watch.stale = false;
                Qt.callLater(watch.read);
                return;
            }
            watch.mounts = readOut.text;
        }
    }

    Process {
        id: ejecter
        stderr: StdioCollector {
            id: ejectErr
        }
        onExited: code => {
            if (code !== 0)
                watch.error = P.oneLine(ejectErr.text.trim().split("\n").pop() || "eject failed");
        }
    }
}

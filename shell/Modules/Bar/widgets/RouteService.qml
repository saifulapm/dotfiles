import QtQuick
import Quickshell
import Quickshell.Io
import "RouteModel.js" as Model
import "QuestionsModel.js" as QuestionsModel

// Question-route service: where the workflow hub sends its questions, Phone
// or this Device, and how many wait. ONE instance however many screens carry
// the widget.
//
// This machine's local hub owns the truth and writes it to
// $XDG_RUNTIME_DIR/workflow-route.json at its start and on every change; this
// service only watches that file. Setting the route runs `workflow route
// <choice>`, which tells the local hub, and the hub rewrites the same file, so
// the glyph changes when the file does and never on the click alone.
QtObject {
    id: root

    // This machine's id, bound by the bar to Sync's ~/.config/qshell/machine
    // read, so "Device" names the same machine every other widget does.
    property string machine: ""

    readonly property string statePath: Quickshell.env("XDG_RUNTIME_DIR") + "/workflow-route.json"

    property var state: Model.parseState("")
    // The local hub's questions, bound by the bar. Their count wins over the
    // route file's while the hub writes its question file.
    property var questions: null
    readonly property int waiting: QuestionsModel.waitingCount(questions ? questions.state : null, state)
    property bool present: false
    property string lastError: ""

    function setRoute(choice) {
        if (routeProcess.running)
            return;
        lastError = "";
        routeProcess.command = ["setpriv", "--pdeathsig", "TERM", "--"].concat(Model.commandFor(choice));
        routeProcess.running = true;
    }

    function openHub() {
        const hub = Model.hubUrl(state);
        if (hub !== "")
            Quickshell.execDetached(["xdg-open", hub]);
    }

    readonly property FileView stateFile: FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.present = true;
            root.state = Model.parseState(text());
        }
        // No file means the local hub is not running here, which hides the glyph.
        onLoadFailed: {
            root.present = false;
            root.state = Model.parseState("");
        }
        onFileChanged: reload()
    }

    // A FileView on a path that does not exist yet never sees it appear, and
    // the local hub may start after the shell. So while the file is absent it
    // is re-read every 5 s; once it exists the watch takes
    // over and this stops. A file read, no process.
    readonly property Timer absentPoll: Timer {
        interval: 5000
        repeat: true
        running: !root.present
        onTriggered: root.stateFile.reload()
    }

    readonly property Process routeProcess: Process {
        running: false
        command: []
        stderr: StdioCollector {
            id: routeStderr
            waitForEnd: true
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                const err = String(routeStderr.text || "").replace(/\s+/g, " ").trim();
                root.lastError = err !== "" ? err : "workflow route exited " + exitCode;
            }
            root.stateFile.reload();
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "QuestionsModel.js" as Model

// Open questions from the local hub: the waiting count the route widget
// shows, a popup for each question that rings on this machine, and the Reply
// modal. ONE instance however many screens carry the widget.
//
// The local hub owns the truth and writes it to
// $XDG_RUNTIME_DIR/hub-questions.json; this service only watches that file.
// Answering runs `mem answer`, and a popup leaves when the hub drops its
// question from the file, never on the click alone.
QtObject {
    id: root

    required property var theme

    readonly property string statePath: Quickshell.env("XDG_RUNTIME_DIR") + "/hub-questions.json"

    property var state: Model.parseState("")
    property bool present: false

    // Ids closed with the x, in memory only: a closed question still waits,
    // and a restart rings it again.
    property var dismissed: ({})
    readonly property var popups: Model.popups(state, dismissed)

    // The Reply modal: which question, and the png attached to the reply.
    property string modalId: ""
    readonly property var modalQuestion: Model.modalFor(modalId, state)
    property string screenshot: ""
    // The modal steps aside while slurp or the file dialog is up, so it is
    // neither in the shot nor over the dialog.
    property bool capturing: false

    property string answeringId: ""
    property string errorId: ""
    property string lastError: ""

    onStateChanged: dismissed = Model.pruneDismissed(dismissed, state)
    // The question left the file (answered elsewhere, or routed to Phone).
    onModalQuestionChanged: if (modalQuestion === null && modalId !== "")
        closeModal()

    function dismiss(id) {
        dismissed = Model.dismiss(dismissed, id);
    }

    function openModal(id) {
        if (modalId !== id)
            screenshot = "";
        modalId = id;
        // A file dialog that never answers would leave the modal hidden;
        // Reply... brings it back.
        capturing = false;
    }

    function closeModal() {
        modalId = "";
        screenshot = "";
        capturing = false;
        errorId = "";
    }

    function answer(id, text, screenshotPath) {
        if (answerProcess.running)
            return;
        answeringId = id;
        errorId = "";
        lastError = "";
        answerProcess.command = ["setpriv", "--pdeathsig", "TERM", "--"].concat(Model.answerArgv(id, text, screenshotPath));
        answerProcess.running = true;
    }

    // One png per question in the runtime dir; the id is reduced to its
    // letters and digits so a strange id cannot name another path.
    function shotPath() {
        return Quickshell.env("XDG_RUNTIME_DIR") + "/qshell-question-" + modalId.replace(/[^A-Za-z0-9]/g, "") + ".png";
    }

    function grabRegion() {
        if (capturing)
            return;
        errorId = "";
        // Cleared first: a new shot reuses the path, and the thumbnail only
        // reloads when its source changes.
        screenshot = "";
        capturing = true;
        slurpProcess.running = true;
    }

    // wl-paste writes only to stdout, and a png is binary, so a fixed sh
    // script redirects it. Its one argument is the path shotPath() built.
    function pasteImage() {
        if (pasteProcess.running)
            return;
        errorId = "";
        screenshot = "";
        pasteProcess.command = ["sh", "-c", 'wl-paste --type image/png > "$1" || { rm -f "$1"; exit 1; }', "qshell-question", shotPath()];
        pasteProcess.running = true;
    }

    function pickedFile(path) {
        capturing = false;
        if (path !== "")
            screenshot = path;
    }

    function fail(id, message) {
        errorId = id;
        lastError = message;
    }

    readonly property FileView stateFile: FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.present = true;
            root.state = Model.parseState(text());
        }
        // No file means no hub runs here: no popups, and the bar counts from
        // the route file instead.
        onLoadFailed: {
            root.present = false;
            root.state = Model.parseState("");
        }
        onFileChanged: reload()
    }

    // A FileView on a path that does not exist yet never sees it appear, and
    // the hub may start after the shell, so the file is re-read every 5 s
    // while it is absent.
    readonly property Timer absentPoll: Timer {
        interval: 5000
        repeat: true
        running: !root.present
        onTriggered: root.stateFile.reload()
    }

    readonly property Process answerProcess: Process {
        running: false
        command: []
        stderr: StdioCollector {
            id: answerStderr
            waitForEnd: true
        }
        onExited: exitCode => {
            const id = root.answeringId;
            root.answeringId = "";
            if (exitCode !== 0) {
                const err = String(answerStderr.text || "").replace(/\s+/g, " ").trim();
                root.fail(id, err !== "" ? err : "mem answer exited " + exitCode);
            } else if (root.modalId === id) {
                root.closeModal();
            }
            root.stateFile.reload();
        }
    }

    readonly property Process slurpProcess: Process {
        running: false
        command: ["slurp"]
        stdout: StdioCollector {
            id: slurpOut
            waitForEnd: true
        }
        // slurp exits 1 when the selection is cancelled with Esc.
        onExited: exitCode => {
            const geometry = String(slurpOut.text || "").trim();
            if (exitCode !== 0 || geometry === "") {
                root.capturing = false;
                return;
            }
            root.grimProcess.command = ["grim", "-g", geometry, root.shotPath()];
            root.grimProcess.running = true;
        }
    }

    readonly property Process grimProcess: Process {
        running: false
        command: []
        onExited: exitCode => {
            root.capturing = false;
            if (exitCode === 0)
                root.screenshot = command[command.length - 1];
            else
                root.fail(root.modalId, "grim exited " + exitCode);
        }
    }

    readonly property Process pasteProcess: Process {
        running: false
        command: []
        onExited: exitCode => {
            if (exitCode === 0)
                root.screenshot = command[command.length - 1];
            else
                root.fail(root.modalId, "no image on the clipboard");
        }
    }

    // The popup window and the modal exist only while something rings.
    readonly property LazyLoader popupLoader: LazyLoader {
        active: root.popups.length > 0 || root.modalId !== ""

        QuestionPopups {
            theme: root.theme
            questions: root
        }
    }
}

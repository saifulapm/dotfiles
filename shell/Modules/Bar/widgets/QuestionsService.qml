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
    // shell.qml, for its own FilePicker.
    property var shellRoot: null

    readonly property string statePath: Quickshell.env("XDG_RUNTIME_DIR") + "/hub-questions.json"

    property var state: Model.parseState("")
    property bool present: false

    // Ids closed with the x, in memory only: a closed question still waits,
    // and a restart rings it again.
    property var dismissed: ({})
    readonly property var popups: Model.popups(state, dismissed)

    // The Reply modal: which question, and the image attached to the reply.
    property string modalId: ""
    readonly property var modalQuestion: Model.modalFor(modalId, state)
    property string screenshot: ""
    // The modal steps aside while the file picker is up.
    property bool capturing: false
    // Where a pasted image is being written.
    property string pendingShot: ""

    // Ctrl+V found text: the modal's text box pastes it at the cursor.
    signal textPasteWanted

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
        // A picker that never answers would leave the modal hidden;
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

    // Ctrl+V in the modal: an image on the clipboard, or a copied png or
    // jpeg file, becomes the attachment; anything else pastes as text.
    function paste() {
        if (pasteTypes.running || pasteSave.running || pasteUri.running)
            return;
        errorId = "";
        pasteTypes.running = true;
    }

    function pickFile() {
        if (!shellRoot || capturing)
            return;
        const id = modalId;
        capturing = true;
        shellRoot.pickFile(Model.pickerRequest(), paths => {
            capturing = false;
            const path = Model.pickedImage(paths);
            if (path !== "" && modalId === id)
                screenshot = path;
        });
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

    readonly property Process pasteTypes: Process {
        running: false
        command: ["wl-paste", "--list-types"]
        stdout: StdioCollector {
            id: pasteTypesOut
            waitForEnd: true
        }
        // wl-paste exits 1 on an empty clipboard: nothing to paste.
        onExited: exitCode => {
            if (exitCode !== 0)
                return;
            const action = Model.pasteAction(pasteTypesOut.text);
            if (action.kind === "image") {
                root.pendingShot = Model.shotPath(Quickshell.env("XDG_RUNTIME_DIR"), root.modalId, action.mime);
                root.pasteSave.command = ["sh", "-c", root.saveScript, "qshell-question", root.pendingShot, action.mime];
                root.pasteSave.running = true;
            } else if (action.kind === "file") {
                root.pasteUri.running = true;
            } else if (action.kind === "text") {
                root.textPasteWanted();
            }
        }
    }

    // wl-paste writes only to stdout and an image is binary, so a fixed sh
    // script redirects it. Its arguments are the shot path and the type the
    // clipboard offered.
    readonly property string saveScript: 'wl-paste --type "$2" > "$1" || { rm -f "$1"; exit 1; }'

    readonly property Process pasteSave: Process {
        running: false
        command: []
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fail(root.modalId, "could not read the image on the clipboard");
                return;
            }
            // Cleared first: a second paste reuses the path, and the
            // thumbnail reloads only when its source changes.
            root.screenshot = "";
            root.screenshot = root.pendingShot;
        }
    }

    readonly property Process pasteUri: Process {
        running: false
        command: ["wl-paste", "--no-newline", "--type", "text/uri-list"]
        stdout: StdioCollector {
            id: pasteUriOut
            waitForEnd: true
        }
        onExited: exitCode => {
            const path = exitCode === 0 ? Model.imageFromUriList(pasteUriOut.text) : "";
            if (path !== "")
                root.screenshot = path;
            else
                root.textPasteWanted();
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

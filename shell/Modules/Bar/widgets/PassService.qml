import QtQuick
import Quickshell
import Quickshell.Io
import "PassModel.js" as Model

// Password-store service — the entry list behind the pass widget and panel.
// ONE instance however many screens carry the widget (S2); created at the bar
// root.
//
// NO SECRET EVER ENTERS THIS PROCESS. Every action is a bin/pass-store verb,
// which hands the work to `pass` itself: `pass -c` puts a password on the
// clipboard and clears it after 45 s without anything here seeing it, and
// `pass show | wtype -` types it over a private pipe. The shell holds names
// and nothing else — which is also why a crash dump or a QML console log of
// this object can never leak a password.
//
// That holds for the QR capture too, and it is the reason the capture is
// three processes rather than one. screenshot-qr puts the otpauth:// URI on
// the clipboard; `pass-store otp-scan` reads it there and answers with the
// four fields that describe the code but are not it; `pass-store otp-save`
// reads it there again and pipes it into `pass otp`. A TOTP seed is the one
// secret in a password store that a person cannot re-derive, and it never
// crosses this boundary in either direction.
//
// Nothing polls. The store is a git repo that changes when someone edits it,
// so a FileView watcher on its directory plus the usual probes at startup and
// panel open is the whole cadence.
QtObject {
    id: root

    property bool probed: false
    // There is a store with at least one entry.
    property bool available: false

    property var entries: []
    // From `pass-store caps`: which actions this machine can actually do.
    // pass-otp and wtype are both optional, and an unavailable action is not
    // offered rather than offered and refused.
    property var caps: []

    readonly property int entryCount: entries.length
    readonly property string tooltip: Model.tooltipText(entryCount)
    readonly property bool canOtp: caps.indexOf("otp") !== -1
    readonly property bool canType: caps.indexOf("type") !== -1
    // screenshot-qr + zbarimg + pass-otp, decided in one place by
    // bin/pass-store's qr_available.
    readonly property bool canQr: caps.indexOf("qr") !== -1

    // What the last captured QR SAYS IT IS — {issuer, account, type, digits},
    // which is the whole of `pass-store otp-scan`'s output. The URI itself
    // stays on the clipboard until `pass` takes it off; this object could not
    // leak it if the whole shell were dumped to a file.
    //
    // It outlives the panel on purpose. The capture happens while the panel is
    // SHUT — it has to, see startCapture — so the panel reads this when it
    // reopens; and a save that failed leaves it here, so opening the panel
    // again resumes rather than losing the code.
    property var capture: null
    property bool capturing: false

    signal captureReady
    signal captureCancelled
    signal captureFailed

    readonly property string storePath: (Quickshell.env("PASSWORD_STORE_DIR") || (Quickshell.env("HOME") + "/.password-store"))

    property bool refreshing: false
    property string lastError: ""

    property string _output: ""
    property string _error: ""

    function refresh() {
        if (listProcess.running)
            return;
        _output = "";
        _error = "";
        refreshing = true;
        listProcess.running = true;
        capsProcess.running = true;
    }

    function applyList(raw) {
        const parsed = Model.parseEntries(raw);
        probed = true;
        available = parsed.length > 0;
        entries = parsed;
        lastError = "";
    }

    function ranked(query) {
        return Model.rank(entries, query);
    }

    function hints() {
        return Model.actionHints(caps);
    }

    // ------------------------------------------------------------- actions
    // Every one of these is one bin/pass-store verb with the entry name as a
    // positional argument. The name is never concatenated into a command
    // string, and no output is collected — a gpg failure surfaces through the
    // action process's stderr, never through a value this object holds.
    //
    // Which verb ran is remembered because exactly one caller cares: a
    // successful otp-save is what retires a capture.
    property string _pending: ""

    function runAction(verb, args) {
        _pending = verb;
        actionProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "pass-store"].concat(args);
        actionProcess.running = true;
    }

    function act(verb, entry) {
        if (!entry || !entry.name)
            return;
        if (verb === "otp" && !canOtp)
            return;
        if ((verb === "type" || verb === "type-user") && !canType)
            return;
        runAction(verb, [verb, String(entry.name)]);
    }

    function copyPassword(entry) {
        act("copy", entry);
    }
    function copyUsername(entry) {
        act("user", entry);
    }
    function copyOtp(entry) {
        act("otp", entry);
    }
    function typePassword(entry) {
        act("type", entry);
    }
    function typeUsername(entry) {
        act("type-user", entry);
    }
    function edit(entry) {
        act("edit", entry);
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // Every action closes the panel, which leaves a failure with nowhere to
    // appear — so it says so out loud instead. The message is always
    // bin/pass-store's own, and that script never puts a secret on stderr: it
    // names the FIELD or the ENTRY, never what either contains.
    function reportFailure(message) {
        const text = elideStatus(message || "pass refused that");
        lastError = text;
        Quickshell.execDetached(["notify-send", "-a", "qshell", "-t", "4000", "Passwords", text.replace(/^pass-store: /, "")]);
    }

    // ------------------------------------------------------- capturing a QR
    //
    // THE PANEL MUST ALREADY BE SHUT WHEN THIS RUNS. It holds
    // WlrKeyboardFocus.Exclusive, and screenshot-qr runs wayfreeze and slurp,
    // both of which need the pointer and the keyboard; with the panel up the
    // region selection cannot happen at all. The panel therefore closes
    // itself, waits for its surface to actually go away, and only then calls
    // this — see PassPanel.beginCapture.
    // A capture already waiting for a region does NOT block a new one, and
    // that is a correction rather than a nicety: `capturing` used to make the
    // chip inert, so a selection the user never noticed — one dropped click
    // on the wrong window is enough — left the whole feature dead with a
    // greyed-out button as the only explanation (reported 2026-08-21, with a
    // slurp four minutes old still holding the screen). Pressing it again now
    // means what a person means by it: start over.
    property bool _abandoned: false
    property bool _restart: false

    function startCapture() {
        if (!canQr)
            return;
        capture = null;
        lastError = "";
        _captureOut = "";
        _captureError = "";
        capturing = true;
        if (captureProcess.running) {
            // A Process cannot be restarted before it has actually gone, so
            // the abandoned one's exit launches the replacement. Its TERM
            // takes slurp with it — see the trap in bin/screenshot-qr.
            _abandoned = true;
            _restart = true;
            captureProcess.running = false;
            return;
        }
        captureProcess.running = true;
    }

    function clearCapture() {
        capture = null;
    }

    // insert = a new entry, append = a code added to one that exists. Both
    // read the URI from the clipboard inside bin/pass-store; the only thing
    // crossing this boundary is a NAME, which was never secret.
    function saveCapture(mode, name) {
        if (!canQr || !capture)
            return;
        const path = String(name || "").trim();
        if (path === "" || (mode !== "insert" && mode !== "append"))
            return;
        runAction("otp-save", ["otp-save", mode, path]);
    }

    // --------------------------------------------------------- the processes
    readonly property Process listProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "pass-store", "list"]
        stdout: StdioCollector {
            id: listStdout
            waitForEnd: true
            onStreamFinished: root._output = text
        }
        stderr: StdioCollector {
            id: listStderr
            waitForEnd: true
            onStreamFinished: root._error = text
        }
        onExited: exitCode => {
            root.refreshing = false;
            const out = String(listStdout.text || root._output || "");
            const err = String(listStderr.text || root._error || "");
            if (exitCode === 0)
                root.applyList(out);
            else {
                root.probed = true;
                root.available = false;
                root.lastError = root.elideStatus(err || "Could not read the password store");
            }
        }
    }

    readonly property Process capsProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "pass-store", "caps"]
        stdout: StdioCollector {
            id: capsStdout
            waitForEnd: true
            onStreamFinished: root.caps = Model.parseCaps(capsStdout.text)
        }
    }

    // Actions collect stderr but never stdout: stdout is where a secret would
    // be if anything went wrong, and this object must not be able to hold one
    // even by accident.
    readonly property Process actionProcess: Process {
        running: false
        command: []
        stderr: StdioCollector {
            id: actionStderr
            waitForEnd: true
            onStreamFinished: root._error = text
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                // Without this, Alt+U on an entry that has no username line
                // was completely silent: the correct verb ran, failed for a
                // correct reason, and nothing reached the screen (measured
                // 2026-08-21). A failed otp-save is the same shape — the
                // panel closed on the keypress, and the refusal it needs to
                // show ("that entry already has a code") arrives afterwards.
                root.reportFailure(root._error);
            } else {
                root.lastError = "";
                // The code is in the store now, so the panel must not offer to
                // file it a second time.
                if (root._pending === "otp-save")
                    root.clearCapture();
            }
            root._pending = "";
            // A use reorders the list, so re-read it.
            root.refresh();
        }
    }

    // screenshot-qr freezes the screen, takes a region, decodes the QR in it
    // and puts the payload on the clipboard with `wl-copy --sensitive`. Its
    // stdout is not read here and there is nothing on it to read: the whole
    // design is that the URI goes clipboard -> bin/pass-store -> `pass`,
    // never through this process.
    property string _captureOut: ""
    property string _captureError: ""

    readonly property Process captureProcess: Process {
        running: false
        // --exit-codes so that a cancelled selection (2) is not read as a
        // successful capture. Without it slurp's Escape and a decoded code
        // both exit 0, and the panel would reopen showing whatever the
        // clipboard happened to hold from an earlier capture.
        command: ["setpriv", "--pdeathsig", "TERM", "--", "screenshot-qr", "--exit-codes"]
        onExited: exitCode => {
            // We killed this one to make room for another. Its exit is not
            // news, and neither the panel nor a notification hears about it.
            if (root._abandoned) {
                root._abandoned = false;
                if (root._restart) {
                    root._restart = false;
                    captureProcess.running = true;
                } else {
                    root.capturing = false;
                }
                return;
            }
            if (exitCode === 0) {
                // Still capturing: the clipboard has something, but only
                // bin/pass-store can say whether it is a one-time code.
                scanProcess.running = true;
                return;
            }
            root.capturing = false;
            if (exitCode === 2) {
                // Escape is not a failure and gets no notification.
                root.captureCancelled();
                return;
            }
            // 1 is screenshot-qr's own "no QR code found here" / "zbar is not
            // installed", and it has already put both on screen itself.
            // Anything else means it could not run at all, which would
            // otherwise be completely silent.
            if (exitCode !== 1)
                root.reportFailure("the QR capture could not run");
            root.captureFailed();
        }
    }

    readonly property Process scanProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "pass-store", "otp-scan"]
        stdout: StdioCollector {
            id: scanStdout
            waitForEnd: true
            onStreamFinished: root._captureOut = text
        }
        stderr: StdioCollector {
            id: scanStderr
            waitForEnd: true
            onStreamFinished: root._captureError = text
        }
        onExited: exitCode => {
            root.capturing = false;
            const out = String(scanStdout.text || root._captureOut || "");
            const err = String(scanStderr.text || root._captureError || "");
            // Four tab-separated fields or nothing — parseCapture refuses
            // anything else rather than displaying it, which is what keeps a
            // URI from ever being rendered as if it were an issuer.
            const parsed = exitCode === 0 ? Model.parseCapture(out) : null;
            if (!parsed) {
                root.reportFailure(err || "that QR is not a one-time code");
                root.captureFailed();
                return;
            }
            root.capture = parsed;
            root.captureReady();
        }
    }

    // The cadence, such as it is: the store's git index.
    //
    // The obvious thing — watching the store DIRECTORY — does not work:
    // FileView reads files, and pointing it at ~/.password-store logs
    // "Read of … failed: Not a file" on every start (observed 2026-08-21) and
    // then watches nothing. The index is the right file anyway. `pass`
    // auto-commits every insert, edit and removal, so .git/index is touched
    // by exactly the events that change this list — including a `pass git
    // pull` bringing entries from the phone or another machine.
    //
    // A store that is not a git repo simply has no watcher; probe-on-open
    // still keeps the panel correct, which is the only place it is read.
    readonly property FileView storeIndex: FileView {
        path: root.storePath + "/.git/index"
        watchChanges: true
        onFileChanged: {
            reload();
            root.refresh();
        }
        onLoadFailed: root.probed = true
        Component.onCompleted: reload()
    }

    Component.onCompleted: refresh()
}

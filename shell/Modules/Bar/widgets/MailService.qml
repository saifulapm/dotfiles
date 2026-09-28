import QtQuick
import Quickshell
import Quickshell.Io

// Mail service — the reader half of the HEY-style mail setup that lives in
// ~/.config/emacs (lisp/hey-notmuch.md): everything the bar mark and the panel
// know about the boxes. ONE instance however many screens carry the widget
// (S2).
//
// The counts are NOT measured here, and they never were. The notmuch post-new
// hook runs `notmuch count` once per box after every sync and writes the
// answers to ~/.local/state/qshell/mail.json — into a temp file and renamed
// over, so a reader can never observe half a JSON. This file watches that one
// file and parses it. The split is deliberate on both sides: the hook already
// has the index open and the box queries in front of it (they have to match
// hey-notmuch.el's saved searches EXACTLY, or the bar says 7 next to a box
// showing 5, and then you stop believing the bar), and a shell that shelled out
// to `notmuch count` nine times would be spending nine processes on a question
// whose answer cannot have changed since the hook answered it.
//
// Nothing polls, and nothing here may start polling. goimapnotify holds an IMAP
// IDLE connection, so mail is fetched, routed and counted within about a second
// of arriving — measured end to end at 10s from send to counted. A timer would
// either lag that push or wake up to learn nothing. The FileView watcher is the
// same contract DufsService has with its flag file, and SystemUpdate, Reminder,
// ScreenRecording and AiClaude have with theirs.
//
// The only processes started here are the ones a click asks for: one presence
// probe at startup, `mail-sync` on demand, and the mail-open that opens a box.
QtObject {
    id: root

    // ---------------------------------------------------------- is mail here
    // The presence probe has answered at least once. Until then the widget
    // draws nothing at all rather than flashing a mark it will take back
    // (DufsService's rule).
    property bool probed: false
    // Mail is set up on this machine. Two ways to be true, because the two
    // fail in opposite directions: ~/.mbsyncrc says "this machine syncs mail"
    // on a fresh install where no sync has published any counts yet, and the
    // state file says "the hook has run here" on a machine whose mbsync config
    // lives somewhere else. The Mac mini and the NUC have neither and must
    // render nothing — an envelope reading 0 on a machine with no mailbox is a
    // widget lying about a feature it does not have.
    property bool installed: false

    // ------------------------------------------------------------ the counts
    // The parsed file. Empty until something reads, which is NOT the same as
    // "every box is 0" — `haveCounts` is the difference, and the panel draws
    // em-dashes rather than zeros the hook never measured.
    property var counts: ({})
    property bool haveCounts: false
    // The hook's own `date -Is` stamp. Kept as the raw string: the panel is the
    // only reader and it wants to format it against the moment it opened.
    property string updatedIso: ""

    property string lastError: ""
    property string actionStatus: ""

    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell/mail.json"
    readonly property string mbsyncPath: Quickshell.env("HOME") + "/.mbsyncrc"
    readonly property string syncBin: Quickshell.env("HOME") + "/.dotfiles/bin/mail-sync"

    // The boxes, in the order hey-notmuch.el lists them — HEY's own order, so
    // this panel and the notmuch hello screen read alike, and the Imbox's two
    // halves ("New for You" and "Previously Seen") stay adjacent the way HEY
    // draws them. Three fields, and each is a contract with a different file:
    //
    //   key     the field in mail.json, written by the post-new hook
    //   search  the box name in BOXES in bin/kak-mail, which is what
    //           mail-open looks the query up by. It must match to the
    //           character — "Prev. Seen", not "Previously Seen" — because a
    //           miss is read as a raw notmuch query and lists nothing.
    //   label   what this panel calls it, which is free to be the longer word
    //
    // `bundled` is in mail.json and is deliberately NOT a row. A bundled sender
    // has no saved search to open: bundling draws one row per SENDER in the
    // hello screen's Bundles section instead of a box of its own (hey-flow.el),
    // so a "Bundled" row would be a destination that does not exist. It is
    // reported in the panel footer, where it can be a number without
    // pretending to be somewhere you can go.
    readonly property var boxes: [
        {
            "key": "imbox",
            "search": "Imbox",
            "label": "Imbox"
        },
        {
            "key": "seen",
            "search": "Prev. Seen",
            "label": "Previously Seen"
        },
        {
            "key": "screener",
            "search": "Screener",
            "label": "Screener"
        },
        {
            "key": "feed",
            "search": "The Feed",
            "label": "The Feed"
        },
        {
            "key": "papertrail",
            "search": "Paper Trail",
            "label": "Paper Trail"
        },
        {
            "key": "replylater",
            "search": "Reply Later",
            "label": "Reply Later"
        },
        {
            "key": "setaside",
            "search": "Set Aside",
            "label": "Set Aside"
        },
        {
            "key": "bubbled",
            "search": "Bubbled Up",
            "label": "Bubbled Up"
        },
        {
            "key": "muted",
            "search": "Muted",
            "label": "Muted"
        }
    ]

    // The three the bar mark and the tooltip read directly.
    readonly property int imbox: countOf("imbox")
    readonly property int screener: countOf("screener")
    readonly property int bundled: countOf("bundled")

    function countOf(key) {
        const value = counts ? counts[String(key || "")] : undefined;
        return typeof value === "number" && value >= 0 ? Math.round(value) : 0;
    }

    readonly property bool syncing: syncProcess.running

    // quickshell does not signal a Process child when the shell exits, so every
    // child is wrapped (the house `cmd` helper, from DufsService).
    function cmd(args) {
        return ["setpriv", "--pdeathsig", "TERM", "--"].concat(args);
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // ------------------------------------------------------------ refreshing
    // The cheap questions only: is there a mailbox on this machine, and what
    // does the state file say right now. There is no timer in this file.
    function refresh() {
        if (!probeProcess.running) {
            probeProcess.command = cmd(["test", "-f", root.mbsyncPath, "-o", "-f", root.statePath]);
            probeProcess.running = true;
        }
        // Re-read even before the probe answers: a reload on a missing file
        // costs one failed stat and squares the counts with the file in the one
        // case the watcher cannot cover — an inotify event that arrived while
        // the shell was starting up.
        stateFile.reload();
    }

    function parseCounts(raw) {
        const text = String(raw || "").trim();
        if (text === "") {
            haveCounts = false;
            return;
        }
        try {
            const data = JSON.parse(text);
            counts = data;
            updatedIso = String(data.updated || "");
            haveCounts = true;
            lastError = "";
        } catch (e) {
            // A parse failure means the hook wrote something new and this file
            // has not caught up — say so rather than showing the last good
            // numbers as though they were current.
            haveCounts = false;
            lastError = "mail.json did not parse";
        }
    }

    // -------------------------------------------------------------- the sync
    // The one "get mail now" entry point, the same script imapnotify and the
    // 15-minute timer call, flock-serialised — so a second caller while a sync
    // is running is safe and simply logs that it left. NOT --quiet: the script
    // reports what it did on stdout ("done in 12s", "another sync is running —
    // skipping"), and that sentence is better in the panel than anything this
    // file could invent. Reminder.qml takes the same view of its CLI's wording.
    function sync() {
        if (syncProcess.running)
            return;
        lastError = "";
        // Deliberately NOT "Syncing…": `syncing` already says that, and the
        // hero's own meta line reads it — the first version put the word on
        // screen twice, once in the hero and once in the status line directly
        // under it. The status line is for what came BACK.
        actionStatus = "";
        _syncOutput = "";
        syncProcess.command = cmd([root.syncBin]);
        syncProcess.running = true;
    }

    property string _syncOutput: ""
    property string _syncError: ""

    // ------------------------------------------------------- opening a box
    // The mail UI is Kakoune (kak/autoload/tools/mail.kak); bin/mail-open
    // raises its window (app-id "kak-mail") or starts one, and switches it to
    // the box. The names in `boxes` are the box names kak-mail knows (BOXES in
    // bin/kak-mail), so a box is opened by name and its query and threading
    // stay defined in one place.
    //
    // The window is started through footclient, so it belongs to the foot
    // server rather than to this Process: restarting the shell does not take
    // the mail window down with it.
    function openBox(box) {
        if (!installed || !box)
            return;
        _open([String(box.search || "")]);
    }

    // The box list with every count.
    function openHome() {
        if (!installed)
            return;
        _open([]);
    }

    // The panel closes the instant a row is activated, so there is no progress
    // line; `lastError` survives to the next panel open instead.
    function _open(args) {
        if (openProcess.running)
            return;
        lastError = "";
        _openError = "";
        openProcess.command = cmd(["mail-open"].concat(args));
        openProcess.running = true;
    }

    property string _openError: ""

    // ------------------------------------------------------------ the clocks
    // The only clock in this file, and it measures nothing: it retires the one
    // transient line the panel shows, a finished sync's own summary.
    //
    // 5s rather than the family's 2200–2600: those clear the result of an
    // INSTANT action (Dufs's "Copied", hub sync's), where the reader is still
    // looking at the thing they just clicked. A sync takes about 14 seconds on
    // this mailbox, so its "done in 14s" arrives long after attention has
    // wandered and needs longer on screen to be read at all.
    readonly property Timer actionStatusTimer: Timer {
        interval: 5000
        repeat: false
        onTriggered: root.actionStatus = ""
    }

    // --------------------------------------------------------- the processes
    // Presence, the Dufs shape: `test` exits 0 when either file is there. One
    // exec at startup and one per panel open, which is what a stat costs when
    // FileView has no way to ask for one.
    readonly property Process probeProcess: Process {
        running: false
        command: []
        onExited: exitCode => {
            root.probed = true;
            root.installed = exitCode === 0;
        }
    }

    readonly property Process syncProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: syncStdout
            waitForEnd: true
            onStreamFinished: root._syncOutput = text
        }
        stderr: StdioCollector {
            id: syncStderr
            waitForEnd: true
            onStreamFinished: root._syncError = text
        }
        onExited: exitCode => {
            // The last log line is the script's own summary of the run, and it
            // is the honest thing to show: "done in 12s" on a good sync,
            // "another sync is running — skipping" when the flock said no.
            const lines = String(syncStdout.text || root._syncOutput || "").trim().split("\n").filter(line => line.trim() !== "");
            const last = lines.length > 0 ? lines[lines.length - 1].replace(/^mail-sync:\s*/, "") : "";
            if (exitCode !== 0) {
                root.actionStatus = "";
                root.lastError = root.elideStatus(last || String(syncStderr.text || root._syncError || "") || "mail-sync exited " + exitCode);
            } else {
                root.actionStatus = root.elideStatus(last || "Synced");
                root.actionStatusTimer.restart();
            }
            // The hook has already rewritten mail.json by now and the watcher
            // has already seen it; this only covers a sync that changed nothing
            // and so wrote an identical file.
            root.stateFile.reload();
        }
    }

    readonly property Process openProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: openStderr
            waitForEnd: true
            onStreamFinished: root._openError = text
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.actionStatus = "";
                root.lastError = root.elideStatus(String(openStderr.text || root._openError || "") || "could not open mail (exit " + exitCode + ")");
            }
        }
    }

    // The hook's publication, and the whole event source. `reload()` at startup
    // matters: the view stays unloaded until something reads it, and neither
    // `loaded` nor `loadFailed` ever fires until then (DufsService learned this
    // the same way). printErrors off because "not there" is the ordinary state
    // on a machine with no mail, not a fault worth a log line.
    readonly property FileView stateFile: FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseCounts(text())
        onLoadFailed: {
            root.haveCounts = false;
            root.updatedIso = "";
        }
        Component.onCompleted: reload()
    }

    Component.onCompleted: refresh()
}

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
// probe at startup, `mail-sync` on demand, and the emacsclient that opens a box.
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
    //   search  the :name in `notmuch-saved-searches`, which is what the
    //           emacsclient form looks the query up by. It must match the
    //           elisp string to the character — "Prev. Seen", not "Previously
    //           Seen" — because a miss falls back to the hello screen.
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
    // Open a box in the running Emacs daemon (emacs.service) and raise its
    // window. Worked out and measured on this machine, 2026-08-17 — none of
    // this is guessed at:
    //
    //  * There is no CLI for "open saved search X". `notmuch-jump-search` is
    //    the interactive `J`, and it reads a key from the user. So the form
    //    does what notmuch-jump does: find the box in `notmuch-saved-searches`
    //    by :name and dispatch on its :search-type, which is why this file
    //    stores the search NAME and not the query — the query would have to be
    //    kept in step with the elisp by hand, and the :search-type would be
    //    lost (the Screener is unthreaded, alone among the boxes, and drawing
    //    it as a tree buries fifteen read advisories on top of four unread
    //    ones). Verified: the four boxes tried land in
    //    *notmuch-saved-tree-Imbox*, *notmuch-saved-unthreaded-Screener*,
    //    *notmuch-saved-search-Paper Trail* and *notmuch-saved-tree-Bubbled
    //    Up* — the same buffers `J i`, `J s`, `J p` and `J b` produce, named by
    //    notmuch itself from the saved search it matched.
    //
    //  * The daemon normally has NO graphical frame: its one frame is the
    //    initial terminal, `display-graphic-p` nil. `(make-frame
    //    '((window-system . pgtk)))` makes one that outlives the client.
    //    `emacsclient --reuse-frame --no-wait --eval` also makes one, and then
    //    the server deletes it the instant the client exits — the frame flashed
    //    up and was gone before the eval's value reached the terminal.
    //
    //  * `select-frame-set-input-focus` does NOT raise the niri window.
    //    Measured: focus was on a foot terminal, the form ran and reported the
    //    Emacs frame selected, and focus was still on foot. That is the same
    //    finding the Mod+N bind records in niri/config.kdl, and the reason it
    //    reaches for the compositor as well. So the second half of the script
    //    asks niri.
    //
    //  * bin/launch-or-focus is that bind's helper and its window lookup is the
    //    line below (newest matching window wins), but the tool itself is not
    //    used here: its other half launches `emacsclient --reuse-frame` when it
    //    finds no window, and by that point the eval has already guaranteed a
    //    frame — the launch would only leave a second, blocking emacsclient
    //    behind. The app_id match is exact rather than launch-or-focus's
    //    word-bounded regex because the pattern is not user input here: a pgtk
    //    Emacs frame is app_id "emacs", verified in `niri msg -j windows`.
    //
    // What this does NOT beat, and cannot: focus-follows-mouse. Traced on the
    // event stream — `Window focus changed: Some(37)` lands, the Emacs window is
    // scrolled into view, and then focusing a column moved a DIFFERENT window
    // under the still-stationary pointer, so niri handed focus straight back to
    // it (`Window focus changed: Some(36)`). The window is raised and on screen
    // either way; whether it keeps the keyboard depends on where the pointer was
    // left, which is the same deal every focus-window action on this desktop
    // gets. Warping the pointer from a bar widget would be a worse cure than the
    // disease. Activating a row from the keyboard (Enter) has no such problem.
    //
    //  * The daemon is started through SYSTEMD, and emacsclient is explicitly
    //    stopped from starting one. Two versions of this were wrong before it,
    //    both found by stopping emacs.service and clicking a row:
    //
    //      1. `emacsclient --alternate-editor=` — which runs `emacs --daemon`
    //         from PATH. PATH's `emacs` here is the emacs-pgtk rpm (30.2) while
    //         emacs.service runs %h/.local/bin/emacs (the 31 build from
    //         bin/rebuild-emacs), so a click forked a SECOND, older Emacs beside
    //         the one this config targets — and without the login-shell
    //         environment the unit's own comment explains it needs. Worse, it
    //         was born in qshell.service's cgroup, where KillMode=control-group
    //         SIGTERMs it on the next `qshell-relaunch`: a bar widget would have
    //         become the owner of the user's editor, and restarting the shell
    //         would have taken Emacs down with it.
    //      2. Dropping the flag — which changed nothing, because
    //         ALTERNATE_EDITOR="" is exported session-wide
    //         (fish/conf.d/00-env.fish, and niri-session imports it into the
    //         user manager's environment) precisely so that a bare emacsclient
    //         auto-starts a daemon. Verified: emacs.service stayed inactive and
    //         a rogue `emacs --daemon` appeared anyway.
    //
    //    Hence `env -u ALTERNATE_EDITOR`: the fallback has to be taken away
    //    before systemd can be the only thing that owns the daemon. `systemctl
    //    --user start` is unconditional and idempotent — 8 ms of D-Bus on an
    //    already-running unit, measured — so there is no branch to get wrong,
    //    and a unit that genuinely cannot start reports that on the panel's
    //    error line instead of quietly forking an Emacs nobody asked for.
    readonly property string raiseScript: ["systemctl --user start emacs.service >/dev/null 2>&1", 'env -u ALTERNATE_EDITOR emacsclient --eval "$1" >/dev/null || exit 1', "id=$(niri msg --json windows | jq -r '[.[] | select(.app_id == \"emacs\")] | sort_by(.id) | last | .id // empty')", '[ -n "$id" ] && exec niri msg action focus-window --id "$id"'].join("\n")

    // One preamble, two bodies: "reuse the daemon's graphical frame or make
    // one, then select it" is the same for every destination, and only the last
    // form differs. `(require 'notmuch)` because the package is deferred behind
    // `:commands` — on a daemon nobody has pressed C-c m in yet, notmuch is not
    // loaded and `notmuch-unthreaded` is not defined.
    function frameForm(body) {
        return "(progn (require (quote notmuch)) (let ((f (or (seq-find (function display-graphic-p) (frame-list)) (make-frame (quote ((window-system . pgtk))))))) (select-frame-set-input-focus f) " + body + "))";
    }

    // The saved-search name is interpolated into an elisp string literal. It is
    // never shell-quoted and does not need to be: the form is handed to bash as
    // "$1" and to emacsclient as one argv entry, so elisp's own quoting is the
    // only layer there is — and the names are the nine literals in `boxes`
    // above, not anything a user can type.
    function boxForm(searchName) {
        return frameForm('(let* ((s (seq-find (lambda (e) (equal (plist-get e :name) "' + searchName + '")) notmuch-saved-searches)) (q (and s (plist-get s :query)))) (if (null s) (notmuch) (pcase (plist-get s :search-type) ((quote tree) (notmuch-tree q)) ((quote unthreaded) (notmuch-unthreaded q)) (_ (notmuch-search q)))))');
    }

    function openBox(box) {
        if (!installed || !box)
            return;
        _open(boxForm(String(box.search || "")));
    }

    // The hello screen — every box plus the Bundles section, which is the one
    // thing in mail.json that no row here can reach.
    function openHome() {
        if (!installed)
            return;
        _open(frameForm("(notmuch)"));
    }

    // No progress message, deliberately. The panel closes the instant a row is
    // activated — it has to, or the card would be left lying on top of the
    // window it just raised — so anything written here would be drawn for one
    // frame and then thrown away with the card. `lastError` is the exception and
    // is NOT cleared on success: it survives to the next panel open, so a click
    // that could not reach Emacs is answered the next time the panel is looked
    // at rather than silently.
    //
    // The cost of closing straight away is that a click which has to bring the
    // daemon up through systemd (about 9 seconds, measured) is nine silent
    // seconds before the window appears. Accepted: emacs.service is
    // session-tied and normally already running, so the ordinary click is a
    // couple of hundred milliseconds, and a card that hangs around waiting is
    // worse in the common case than a quiet one is in the rare case.
    function _open(form) {
        if (openProcess.running)
            return;
        lastError = "";
        _openError = "";
        openProcess.command = cmd(["bash", "-c", root.raiseScript, "hey-mail-open", form]);
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
                root.lastError = root.elideStatus(String(openStderr.text || root._openError || "") || "could not reach Emacs (exit " + exitCode + ")");
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

import QtQuick
import Quickshell
import Quickshell.Io
import "DropboxModel.js" as Model

// Dropbox service — port of omarchy's dropbox plugin Service.qml (CREDITS.md).
// It owns everything the widget and the panel read: whether the CLI exists at
// all, whether the daemon is running, the account's sync folder and plan, the
// stored bytes, the most recently synced files, and the start/stop/login
// commands.
//
// What is kept from theirs
//   * the optimistic `_desired` / `active` pair, so the icon and the hero
//     phrase flip the instant you click instead of waiting for dropboxd;
//   * the startup ramp (a 2 s retry for ~30 s) that covers the daemon still
//     respawning when the shell comes up after a fresh login;
//   * the settle re-polls after a stop/start, the 1 s delayed refresh after a
//     login, and the 2.2 s action-status expiry;
//   * their login flow: run the CLI's `start`, watch both streams for the
//     authentication URL and hand the first one found to the browser.
//
// What differs
//   * Nothing runs until the one presence probe answers, and everything stops
//     again the moment it answers "not installed" — that is the whole widget's
//     gate, and this machine (and every Asahi machine) is that case: Dropbox
//     ships no aarch64 daemon.
//   * The periodic refresh only asks the cheap question (`--probe`: is the CLI
//     there, is the daemon up, is an account attached). The full pass — which
//     walks the entire Dropbox folder for the stored total and the recent
//     files — runs when the panel opens or is refreshed by hand. Upstream
//     walks the tree on every 60 s tick whether or not anyone is looking.
//   * The timer only runs while the widget is actually on a visible bar. This
//     shell does not poll at idle; there is no event source for dropboxd's
//     status, so their cadence is kept, scoped to when it can be seen.
//   * Files open through `xdg-open`; upstream reveals them with
//     `uwsm-app -- nautilus --select <file uri>`, and neither uwsm nor
//     nautilus is part of this desktop.
//   * Every child process is wrapped in `setpriv --pdeathsig TERM`: quickshell
//     does not signal a Process child when the shell exits, and a first-run
//     `dropbox start` downloads the daemon, so it can outlive us by minutes.
QtObject {
    id: root

    property var settings: ({})
    // False while the widget is off-screen; the periodic refresh follows it.
    property bool pollingAllowed: false

    readonly property string helperPath: Quickshell.env("HOME") + "/.dotfiles/bin/dropbox-status"

    // The presence probe has answered at least once. Until then the widget
    // shows nothing at all, rather than flashing an icon it will take back.
    property bool probed: false
    property bool installed: false
    property bool running: false
    property bool authenticated: false
    // Which CLI the helper found: `dropbox-cli` upstream, `dropbox` on Fedora.
    property string cli: ""

    // Optimistic sync state so the UI reacts the instant you click, rather than
    // waiting for dropboxd to actually settle. _desired is -1 while we just
    // follow the real state, or 0/1 while a pause/resume is still catching up.
    property int _desired: -1
    readonly property bool active: _desired === -1 ? running : (_desired === 1)
    property bool refreshing: false
    property string statusText: "Checking…"
    property string accountPath: ""
    property string plan: ""
    property double usedBytes: 0
    property double quotaBytes: 0
    property double usagePercent: 0
    property bool quotaKnown: false
    property var files: []
    // A full pass has landed, so an empty file list means "none" and not "not
    // looked yet".
    property bool detailsLoaded: false
    property string actionStatus: ""
    property string lastError: ""

    readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)
    readonly property int fileLimit: intSetting("fileLimit", 25, 1, 100)
    readonly property bool busy: statusProcess.running || loginProcess.running || controlProcess.running

    property string _statusOutput: ""
    property string _statusError: ""
    property bool _pendingFull: false
    property string _loginOutput: ""
    property string _loginError: ""
    property bool _loginUrlOpened: false
    property string _controlOutput: ""
    property string _controlError: ""

    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function intSetting(name, fallback, min, max) {
        let n = parseInt(String(setting(name, fallback)), 10);
        if (!isFinite(n))
            n = fallback;
        if (n < min)
            n = min;
        if (n > max)
            n = max;
        return n;
    }

    // Presence + daemon state only. Cheap enough to run on a timer.
    function refresh() {
        run(false);
    }

    // Adds the folder walk: stored bytes and the recent-file list.
    function refreshDetails() {
        run(true);
    }

    function run(full) {
        if (statusProcess.running) {
            // A full pass asked for while the cheap one is still in flight is
            // remembered, not dropped: the panel opens on top of the startup
            // probe often enough, and upstream's plain "return" would leave it
            // reading "Reading…" until the next time it was opened.
            if (full)
                _pendingFull = true;
            return;
        }
        // Once the probe has said "no CLI here", nothing ever runs again.
        if (probed && !installed)
            return;
        _statusOutput = "";
        _statusError = "";
        refreshing = true;
        statusProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "python3", helperPath, full ? String(fileLimit) : "--probe"];
        statusProcess.running = true;
    }

    function applyStatus(raw) {
        const parsed = Model.parseStatus(raw);
        if (!parsed.ok) {
            lastError = parsed.lastError || "Failed to read Dropbox status";
            return;
        }
        probed = true;
        installed = parsed.installed === true;
        running = parsed.running === true;
        authenticated = parsed.authenticated === true;
        cli = String(parsed.cli || "");
        // Reality caught up to the pending pause/resume — stop overriding.
        if (_desired !== -1 && running === (_desired === 1))
            _desired = -1;
        statusText = String(parsed.statusText || (installed ? "Stopped" : "Not installed"));
        accountPath = String(parsed.accountPath || "");
        plan = String(parsed.plan || "");
        // A probe answers with zeroes for everything it did not measure, so it
        // must not be allowed to blank an open panel.
        if (parsed.probe !== true) {
            usedBytes = Number(parsed.usedBytes || 0);
            quotaBytes = Number(parsed.quotaBytes || 0);
            usagePercent = Number(parsed.usagePercent || 0);
            quotaKnown = parsed.quotaKnown === true;
            files = parsed.files || [];
            detailsLoaded = true;
        }
        if (!authenticated) {
            files = [];
            usedBytes = 0;
        }
        lastError = "";
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // The CLI's own name for itself, whichever package provided it.
    function cliCommand(verb) {
        return ["setpriv", "--pdeathsig", "TERM", "--", cli === "" ? "dropbox" : cli, verb];
    }

    function login() {
        if (!installed || loginProcess.running)
            return;
        _loginOutput = "";
        _loginError = "";
        _loginUrlOpened = false;
        actionStatus = "Starting Dropbox login…";
        loginProcess.command = cliCommand("start");
        loginProcess.running = true;
    }

    function pause() {
        runControl(cliCommand("stop"), 0);
    }

    function resume() {
        runControl(cliCommand("start"), 1);
    }

    function toggleRunning() {
        if (active)
            pause();
        else
            resume();
    }

    function runControl(command, desired) {
        // No progress status here — the greyed icon and hero phrase already
        // convey the pause/resume; only surface a message if the command fails.
        if (!installed || controlProcess.running)
            return;
        _desired = desired;
        _controlOutput = "";
        _controlError = "";
        controlProcess.command = command;
        controlProcess.running = true;
    }

    function openFile(file) {
        if (!file || !file.path)
            return;
        Quickshell.execDetached(["xdg-open", String(file.path)]);
    }

    function openFolder() {
        if (accountPath === "")
            return;
        Quickshell.execDetached(["xdg-open", accountPath]);
    }

    function openAuthUrlFrom(text) {
        if (_loginUrlOpened)
            return true;
        const match = String(text || "").match(/https?:\/\/\S+/);
        if (match && match[0]) {
            _loginUrlOpened = true;
            Qt.openUrlExternally(match[0]);
            actionStatus = "Opened Dropbox login";
            actionStatusTimer.restart();
            return true;
        }
        return false;
    }

    function handleLoginOutput(data, isError) {
        const text = String(data || "");
        if (isError)
            _loginError += text + "\n";
        else
            _loginOutput += text + "\n";
        openAuthUrlFrom(text);
    }

    // ------------------------------------------------------------ the clock
    // Their periodic refresh, scoped to a visible widget with a CLI behind it.
    readonly property Timer refreshTimer: Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: root.pollingAllowed && root.probed && root.installed
        onTriggered: root.refresh()
    }

    // After a fresh boot the startup poll usually lands before dropboxd has
    // finished its respawn dance, which left the icon stale until the next
    // periodic refresh. Poll quickly until the daemon shows up, or give up
    // after ~30 seconds.
    readonly property Timer startupRamp: Timer {
        property int ticks: 0
        interval: 2000
        repeat: true
        running: root.pollingAllowed && root.probed && root.installed && !root.running && ticks < 15
        onTriggered: {
            ticks += 1;
            if (!root.running)
                root.refresh();
        }
    }

    readonly property Timer delayedRefresh: Timer {
        interval: 1000
        repeat: false
        onTriggered: root.refresh()
    }

    readonly property Timer actionStatusTimer: Timer {
        interval: 2200
        repeat: false
        onTriggered: root.actionStatus = ""
    }

    // dropboxd takes a few (variable) seconds to settle after stop/start, so
    // re-poll a handful of times to reflect the new state without waiting for
    // the next periodic refresh.
    readonly property Timer settleTimer: Timer {
        property int ticks: 0
        interval: 1500
        repeat: true
        running: false
        onTriggered: {
            ticks += 1;
            root.refresh();
            if (ticks >= 4) {
                ticks = 0;
                running = false;
                root._desired = -1;
            }
        }
    }

    // --------------------------------------------------------- the processes
    readonly property Process statusProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: statusStdout
            waitForEnd: true
            onStreamFinished: root._statusOutput = text
        }
        stderr: StdioCollector {
            id: statusStderr
            waitForEnd: true
            onStreamFinished: root._statusError = text
        }
        onExited: exitCode => {
            root.refreshing = false;
            const out = String(statusStdout.text || root._statusOutput || "");
            const err = String(statusStderr.text || root._statusError || "");
            if (exitCode === 0)
                root.applyStatus(out);
            else {
                // A helper that cannot run at all must still settle the gate,
                // or the widget waits forever on a probe that never lands.
                root.probed = true;
                root.lastError = root.elideStatus(err || out || "Could not read Dropbox status");
            }
            if (root._pendingFull) {
                root._pendingFull = false;
                if (root.installed)
                    root.refreshDetails();
            }
        }
    }

    readonly property Process loginProcess: Process {
        running: false
        command: []
        stdout: SplitParser {
            onRead: data => root.handleLoginOutput(data, false)
        }
        stderr: SplitParser {
            onRead: data => root.handleLoginOutput(data, true)
        }
        onExited: exitCode => {
            const combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "");
            const opened = root.openAuthUrlFrom(combined);
            if (exitCode !== 0 && !opened) {
                root.lastError = root.elideStatus(combined || "Dropbox login failed");
                root.actionStatus = root.lastError;
            } else if (!opened) {
                root.actionStatus = "";
                root.lastError = "";
            }
            root.delayedRefresh.restart();
        }
    }

    readonly property Process controlProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: controlStdout
            waitForEnd: true
            onStreamFinished: root._controlOutput = text
        }
        stderr: StdioCollector {
            id: controlStderr
            waitForEnd: true
            onStreamFinished: root._controlError = text
        }
        onExited: exitCode => {
            const out = String(controlStdout.text || root._controlOutput || "");
            const err = String(controlStderr.text || root._controlError || "");
            if (exitCode !== 0) {
                root._desired = -1;
                root.lastError = root.elideStatus(err || out || "Dropbox command failed");
                root.actionStatus = root.lastError;
            } else {
                root.lastError = "";
                root.actionStatus = "";
            }
            root.settleTimer.ticks = 0;
            root.settleTimer.restart();
            root.delayedRefresh.restart();
        }
    }

    // The one question asked unconditionally: is Dropbox on this machine?
    Component.onCompleted: refresh()
}

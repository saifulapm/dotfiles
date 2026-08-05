import QtQuick
import Quickshell
import Quickshell.Io
import "ICloudModel.js" as Model

// iCloud service — ours, in the shape of DropboxService (CREDITS.md): it owns
// everything the widget and the panel read. The backend is rclone's
// iclouddrive remote, and that backend sets the rules:
//
//   * `rclone about` is unsupported, so there are no quota numbers and no
//     storage bar — reachability is the only question the network can answer;
//   * every network probe is a real API call against Apple, so the full probe
//     runs on panel open and explicit refresh ONLY. The periodic facts are the
//     free local ones (CLI present, remote configured, mountpoint state), read
//     by `bin/icloud-status --local`, and even those only re-run after our own
//     actions — there is no timer here at all;
//   * sessions expire, and the fix (`rclone config reconnect iCloud:`) is
//     interactive Apple 2FA. The shell never runs it; a failed probe raises a
//     copyable command row in the panel instead (the tailscale panel's
//     authorize-row precedent).
//
// The mount is a transient systemd user unit, as bin/reminder's timers are:
// systemd owns the rclone process, `systemctl --user stop` unmounts (rclone
// unmounts cleanly on SIGTERM), and `mountpoint -q` is the arbiter of state.
// The optimistic `_desired` / `mountActive` pair is DropboxService's, so the
// switch throws on the click rather than when the FUSE mount settles.
QtObject {
    id: root

    property var settings: ({})

    readonly property string helperPath: Quickshell.env("HOME") + "/.dotfiles/bin/icloud-status"

    // The local probe has answered at least once. Until then the widget shows
    // nothing at all, rather than flashing an icon it might take back.
    property bool probed: false
    property bool installed: false
    property bool configured: false
    property string remote: ""
    property string remoteType: ""
    property bool mounted: false
    property string mountPoint: ""
    property string mountUnit: "qshell-icloud-mount"

    // Reachability: 0 = never probed, 1 = the last probe answered, -1 = it
    // failed (probeError says why). Only a full probe moves it.
    property int reachState: 0
    property string probeError: ""
    readonly property bool lastProbeFailed: reachState === -1

    // Optimistic mount state so the switch reacts on the click. -1 while we
    // just follow mountpoint's answer, 0/1 while a mount/unmount settles.
    property int _desired: -1
    readonly property bool mountActive: _desired === -1 ? mounted : (_desired === 1)

    property bool refreshing: false
    // A network probe is in flight (they can take seconds against Apple).
    property bool checking: false
    property string actionStatus: ""
    property string lastError: ""

    readonly property bool busy: statusProcess.running || controlProcess.running

    readonly property string reauthCommand: "rclone config reconnect " + (remote === "" ? "iCloud" : remote) + ":"

    property bool _statusWasLocal: true
    property string _statusOutput: ""
    property string _statusError: ""
    property bool _pendingProbe: false
    property string _controlOutput: ""
    property string _controlError: ""

    // Local facts only — no network. Free to run after every action.
    function refreshLocal() {
        run(true);
    }

    // Adds the one reachability call against Apple. Panel open and explicit
    // refresh only.
    function probe() {
        run(false);
    }

    function run(localOnly) {
        if (statusProcess.running) {
            // A probe asked for while the local read is still in flight is
            // remembered, not dropped (DropboxService's pending-full rule).
            if (!localOnly)
                _pendingProbe = true;
            return;
        }
        // Once the local read has said "no rclone here", nothing ever runs
        // again — same gate as the dropbox widget's.
        if (probed && !installed)
            return;
        _statusWasLocal = localOnly;
        _statusOutput = "";
        _statusError = "";
        if (localOnly)
            refreshing = true;
        else
            checking = true;
        statusProcess.command = localOnly ? ["setpriv", "--pdeathsig", "TERM", "--", "bash", helperPath, "--local"] : ["setpriv", "--pdeathsig", "TERM", "--", "bash", helperPath];
        statusProcess.running = true;
    }

    function applyStatus(raw) {
        const parsed = Model.parseStatus(raw);
        if (!parsed.ok) {
            lastError = parsed.lastError || "Failed to read iCloud status";
            return;
        }
        probed = true;
        installed = parsed.installed === true;
        configured = parsed.configured === true;
        remote = String(parsed.remote || "");
        remoteType = String(parsed.remoteType || "");
        mounted = parsed.mounted === true;
        mountPoint = String(parsed.mountPoint || "");
        mountUnit = String(parsed.mountUnit || "qshell-icloud-mount");
        // Reality caught up to the pending mount/unmount — stop overriding.
        if (_desired !== -1 && mounted === (_desired === 1))
            _desired = -1;
        // A local answer never touches the network verdict (the helper's
        // `local` flag is the arbiter, not what we asked for).
        if (parsed.local !== true) {
            if (parsed.reachable === true) {
                reachState = 1;
                probeError = "";
            } else {
                reachState = -1;
                probeError = String(parsed.error || "iCloud did not answer");
            }
        } else if (String(parsed.error || "") !== "") {
            // A local error (listremotes itself failed) is still an error.
            lastError = String(parsed.error);
            return;
        }
        lastError = "";
    }

    function toggleMount() {
        if (mountActive)
            unmount();
        else
            mount();
    }

    function mount() {
        if (!installed || !configured || controlProcess.running)
            return;
        _desired = 1;
        _controlOutput = "";
        _controlError = "";
        // The unit is transient and --collect'ed: nothing survives a failure,
        // and systemd owns the rclone process, not the shell — a shell restart
        // must not take the user's mounted folder with it.
        controlProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", 'mkdir -p "$1" && exec systemd-run --user --quiet --collect --unit="$2" -- rclone mount "$3:" "$1" --vfs-cache-mode writes', "icloud-mount", mountPoint, mountUnit, remote];
        controlProcess.running = true;
    }

    function unmount() {
        if (controlProcess.running)
            return;
        _desired = 0;
        _controlOutput = "";
        _controlError = "";
        controlProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "systemctl", "--user", "stop", mountUnit];
        controlProcess.running = true;
    }

    function openFolder() {
        if (!mounted || mountPoint === "")
            return;
        Quickshell.execDetached(["xdg-open", mountPoint]);
    }

    function copyReauthCommand() {
        Quickshell.execDetached(["wl-copy", "--type", "text/plain", reauthCommand]);
        actionStatus = "Command copied — run it in a terminal";
        actionStatusTimer.restart();
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // ------------------------------------------------------------ the clocks
    // No periodic timer anywhere: the only clocks are the settle re-polls
    // after our own mount/unmount (a FUSE mount takes a moment to appear in
    // the mount table) and the action-status expiry.
    readonly property Timer settleTimer: Timer {
        property int ticks: 0
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            ticks += 1;
            root.refreshLocal();
            if (ticks >= 5 || root._desired === -1) {
                ticks = 0;
                running = false;
                root._desired = -1;
            }
        }
    }

    readonly property Timer actionStatusTimer: Timer {
        interval: 2200
        repeat: false
        onTriggered: root.actionStatus = ""
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
            root.checking = false;
            const out = String(statusStdout.text || root._statusOutput || "");
            const err = String(statusStderr.text || root._statusError || "");
            if (exitCode === 0)
                root.applyStatus(out);
            else {
                // A helper that cannot run at all must still settle the gate,
                // or the widget waits forever on a probe that never lands.
                root.probed = true;
                root.lastError = root.elideStatus(err || out || "Could not read iCloud status");
            }
            if (root._pendingProbe) {
                root._pendingProbe = false;
                if (root.installed && root.configured)
                    root.probe();
            }
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
                root.lastError = root.elideStatus(err || out || "iCloud mount command failed");
                root.actionStatus = root.lastError;
            } else {
                root.lastError = "";
                root.actionStatus = "";
            }
            root.settleTimer.ticks = 0;
            root.settleTimer.restart();
        }
    }

    // The one question asked unconditionally, and it costs no network: is
    // rclone on this machine, with an iCloud remote in its config?
    Component.onCompleted: refreshLocal()
}

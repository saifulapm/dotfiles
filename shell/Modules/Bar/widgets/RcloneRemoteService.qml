import QtQuick
import Quickshell
import Quickshell.Io
import "RcloneRemoteModel.js" as Model

// rclone-remote service — ours, in the shape of omarchy's dropbox Service.qml
// (CREDITS.md; our port of it is gone — rclone is the one Dropbox path now),
// grown out of the iCloud widget's service: it owns everything the widget and
// the panel read, for ONE rclone remote named by the instance's `config`
// (remote, remoteType, label, mountPoint, legacyUnit, glyph/drawnMark,
// phrases). The rclone backend sets the rules:
//
//   * every network probe is a real API call, so the full probe runs on panel
//     open and explicit refresh ONLY. The periodic facts are the free local
//     ones (CLI present, remote configured, mountpoint state), read by
//     `bin/rclone-remote-status --local`, and even those only re-run after
//     our own actions — there is no timer here at all;
//   * `rclone about` answers quota only on backends that support it (dropbox
//     does, iclouddrive does not), so the helper reports `quotaSupported` and
//     the panel shows a storage section exactly when it is true;
//   * sessions expire, and the fix (`rclone config reconnect <remote>:`) is
//     interactive — Apple 2FA, Dropbox browser OAuth. The shell never runs
//     it; a failed probe raises a copyable command row in the panel instead
//     (the tailscale panel's authorize-row precedent).
//
// The mount is a transient systemd user unit, as bin/reminder's timers are:
// systemd owns the rclone process, `systemctl --user stop` unmounts (rclone
// unmounts cleanly on SIGTERM), and `mountpoint -q` is the arbiter of state.
// The unit name is qshell-rclone-<remote>, reported by the helper — which
// keeps reporting an ACTIVE legacy-named unit (the pre-generalization
// qshell-icloud-mount) until it stops, so an existing mount is adopted, not
// stranded. The optimistic `_desired` / `mountActive` pair is
// their dropbox service's, so the switch throws on the click rather than when the
// FUSE mount settles.
QtObject {
    id: root

    property var config: ({})

    readonly property string cfgRemote: String((config && config.remote) || "")
    readonly property string cfgType: String((config && config.remoteType) || "")
    readonly property string cfgMountPoint: String((config && config.mountPoint) || "")
    readonly property string cfgLegacyUnit: String((config && config.legacyUnit) || "")
    readonly property string label: String((config && config.label) || cfgRemote || "Cloud")

    readonly property string helperPath: Quickshell.env("HOME") + "/.dotfiles/bin/rclone-remote-status"

    // The local probe has answered at least once. Until then the widget shows
    // nothing at all, rather than flashing an icon it might take back.
    property bool probed: false
    property bool installed: false
    property bool configured: false
    property string remote: ""
    property string remoteType: ""
    property bool mounted: false
    property string mountPoint: ""
    property string mountUnit: ""

    // Reachability: 0 = never probed, 1 = the last probe answered, -1 = it
    // failed (probeError says why). Only a full probe moves it.
    property int reachState: 0
    property string probeError: ""
    readonly property bool lastProbeFailed: reachState === -1

    // Quota, when the backend's `about` supports it. -1 = unknown.
    property bool quotaSupported: false
    property real quotaUsed: -1
    property real quotaTotal: -1
    property real quotaFree: -1

    // Optimistic mount state so the switch reacts on the click. -1 while we
    // just follow mountpoint's answer, 0/1 while a mount/unmount settles.
    property int _desired: -1
    readonly property bool mountActive: _desired === -1 ? mounted : (_desired === 1)

    property bool refreshing: false
    // A network probe is in flight (they can take seconds).
    property bool checking: false
    property string actionStatus: ""
    property string lastError: ""

    readonly property bool busy: statusProcess.running || controlProcess.running

    readonly property string reauthCommand: "rclone config reconnect " + (remote === "" ? cfgRemote : remote) + ":"

    property bool _statusWasLocal: true
    property string _statusOutput: ""
    property string _statusError: ""
    property bool _pendingLocal: false
    property bool _pendingProbe: false
    property string _controlOutput: ""
    property string _controlError: ""

    // Local facts only — no network. Free to run after every action.
    function refreshLocal() {
        run(true);
    }

    // Adds the one network call. Panel open and explicit refresh only.
    function probe() {
        run(false);
    }

    function run(localOnly) {
        if (statusProcess.running) {
            // A read asked for while another is still in flight is
            // remembered, not dropped (their dropbox service's pending-full rule).
            if (localOnly)
                _pendingLocal = true;
            else
                _pendingProbe = true;
            return;
        }
        // Once the local read has said "no rclone here", nothing ever runs
        // again — same gate as the dropbox widget's.
        if (probed && !installed)
            return;
        if (cfgRemote === "" || cfgType === "")
            return;
        _statusWasLocal = localOnly;
        _statusOutput = "";
        _statusError = "";
        if (localOnly)
            refreshing = true;
        else
            checking = true;
        const args = ["setpriv", "--pdeathsig", "TERM", "--", "bash", helperPath, "--remote", cfgRemote, "--type", cfgType];
        if (cfgMountPoint !== "")
            args.push("--mountpoint", cfgMountPoint);
        if (cfgLegacyUnit !== "")
            args.push("--legacy-unit", cfgLegacyUnit);
        if (localOnly)
            args.push("--local");
        statusProcess.command = args;
        statusProcess.running = true;
    }

    function applyStatus(raw) {
        const parsed = Model.parseStatus(raw);
        if (!parsed.ok) {
            lastError = parsed.lastError || "Failed to read rclone remote status";
            return;
        }
        probed = true;
        installed = parsed.installed === true;
        configured = parsed.configured === true;
        remote = String(parsed.remote || "");
        remoteType = String(parsed.remoteType || "");
        mounted = parsed.mounted === true;
        mountPoint = String(parsed.mountPoint || "");
        mountUnit = String(parsed.mountUnit || "");
        // Reality caught up to the pending mount/unmount — stop overriding.
        if (_desired !== -1 && mounted === (_desired === 1))
            _desired = -1;
        // A local answer never touches the network verdict (the helper's
        // `local` flag is the arbiter, not what we asked for).
        if (parsed.local !== true) {
            quotaSupported = parsed.quotaSupported === true;
            quotaUsed = Number(parsed.usedBytes !== undefined ? parsed.usedBytes : -1);
            quotaTotal = Number(parsed.totalBytes !== undefined ? parsed.totalBytes : -1);
            quotaFree = Number(parsed.freeBytes !== undefined ? parsed.freeBytes : -1);
            if (parsed.reachable === true) {
                reachState = 1;
                probeError = "";
            } else {
                reachState = -1;
                probeError = String(parsed.error || label + " did not answer");
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
        if (mountPoint === "" || mountUnit === "" || remote === "")
            return;
        _desired = 1;
        _controlOutput = "";
        _controlError = "";
        // The unit is transient and --collect'ed: nothing survives a failure,
        // and systemd owns the rclone process, not the shell — a shell restart
        // must not take the user's mounted folder with it.
        controlProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", 'mkdir -p "$1" && exec systemd-run --user --quiet --collect --unit="$2" -- rclone mount "$3:" "$1" --vfs-cache-mode writes', "rclone-remote-mount", mountPoint, mountUnit, remote];
        controlProcess.running = true;
    }

    function unmount() {
        if (controlProcess.running || mountUnit === "")
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

    // A live settings edit (a different remote, mountpoint…) re-reads the
    // local facts; the initial read is Component.onCompleted's.
    onConfigChanged: if (probed)
        refreshLocal()

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
                root.lastError = root.elideStatus(err || out || "Could not read rclone remote status");
            }
            if (root._pendingProbe) {
                root._pendingProbe = false;
                root._pendingLocal = false;
                if (root.installed && root.configured)
                    root.probe();
            } else if (root._pendingLocal) {
                root._pendingLocal = false;
                root.refreshLocal();
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
                root.lastError = root.elideStatus(err || out || "rclone mount command failed");
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
    // rclone on this machine, with this remote in its config?
    Component.onCompleted: refreshLocal()
}

import QtQuick
import Quickshell
import Quickshell.Io
import "WarpModel.js" as Model

// Cloudflare WARP service — port of tobi/omarchy-warp's Service.qml
// (CREDITS.md). It owns everything the widget and the panel read: whether the
// CLI exists, what `warp-cli status` says, the settings block behind the mode
// switcher and the split-tunnel readout, the registration record, the tunnel
// stats, and the connect/disconnect/mode/register commands.
//
// What is kept from theirs
//   * the optimistic `_desired` / `active` pair, so the bar mark and the hero
//     switch flip the instant you click instead of waiting for warp-svc;
//   * the chaining: `status` is the only unconditional read, and settings,
//     registration and stats hang off a status that came back healthy — asking
//     a daemon that is down four questions instead of one buys nothing;
//   * the 5-minute registration throttle (it changes when you register, and
//     that path refreshes explicitly) and stats only while connected;
//   * the startup ramp, because right after login warp-svc is usually still
//     coming up, and the 2.2 s action-status expiry;
//   * `--accept-tos --json --no-paginate --no-ansi` on every invocation: the
//     first keeps a fresh install off an interactive prompt, the rest keep the
//     output machine-readable.
//
// What differs
//   * Nothing runs until one presence probe answers, and nothing runs again
//     once it answers no — the widget takes no width at all in that case, which
//     is this bar's contract for every optional CLI (see Tailscale). Their
//     widget deliberately stays visible without the CLI so its panel can offer
//     to install it from the AUR; here the package is declared in
//     packages/manifest.toml and installed by the apply, so that whole path —
//     their install(), installProbe and the floating-terminal launcher — is
//     dropped rather than translated.
//   * The periodic refresh runs only while the widget is on a visible bar
//     (pollingAllowed). This shell does not poll at idle. warp-svc offers no
//     event source we can watch without holding its socket, so their cadence is
//     kept and scoped to when it can be seen.
//   * The watchdog reaps per launch rather than in a batch: a read started late
//     in the window keeps its own remainder instead of being killed with the
//     others and flashing a false "Disconnected". Same shape as Tailscale's.
//   * Every child is wrapped in `setpriv --pdeathsig TERM`, because quickshell
//     does not signal a Process child when the shell exits and `warp-cli
//     registration new` talks to the network.
//   * Clipboard goes through `wl-copy` directly instead of a `bash -c printf |
//     wl-copy`, so nothing needs shell quoting.
QtObject {
    id: root

    property var settings: ({})
    // False while the widget is off-screen; the periodic refresh follows it.
    property bool pollingAllowed: false

    // The presence probe has answered at least once. Until then the widget
    // shows nothing, rather than flashing a mark it will take back.
    property bool probed: false
    property bool installed: false

    property bool available: false
    property bool daemonDown: false
    property bool needsRegistration: false
    property bool needsTos: false
    property bool connected: false
    property bool connecting: false

    // Optimistic state so the UI reacts the instant you click. _desired is -1
    // while we follow reality, 0/1 while a connect/disconnect catches up.
    property int _desired: -1
    readonly property bool active: _desired === -1 ? connected : (_desired === 1)

    property bool refreshing: false
    property string status: "Unknown"
    property string statusText: "Checking…"
    property string reasonText: ""

    property string mode: ""
    property bool alwaysOn: false
    property bool switchLocked: false
    property string splitTunnelText: ""
    property var splitTunnel: ({})
    property bool disableForWifi: false
    property bool disableForEthernet: false
    property string familiesMode: ""

    property bool registered: false
    property string accountLabel: ""
    property string accountType: ""
    property string organization: ""
    property string deviceId: ""
    property string deviceName: ""

    property var tunnelStats: ({})
    property string settingMode: ""
    property string actionStatus: ""
    property string lastError: ""
    // A details pass has landed, so an empty split-tunnel list means "none" and
    // not "not looked yet".
    property bool detailsLoaded: false

    readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 20, 5, 3600)

    readonly property bool busy: presenceProcess.running || statusProcess.running || settingsProcess.running || registrationProcess.running || statsProcess.running || actionProcess.running || daemonProcess.running

    readonly property var modeRows: Model.modeRows(mode)
    readonly property bool tunnelMode: Model.isTunnelMode(mode)
    readonly property bool canToggle: installed && !daemonDown && !needsTos && !busy

    readonly property var splitTunnelEntries: splitTunnel && splitTunnel.entries ? splitTunnel.entries : []
    readonly property string splitTunnelSummary: splitTunnel && splitTunnel.summary ? splitTunnel.summary : ""

    // Ours, no upstream: WARP in a tunnel mode owns the default route, which is
    // also where the tailnet lives. Cloudflare's own default exclude list
    // carries Tailscale's CGNAT range, so the honest answer depends on the
    // machine — see Model.tailnetVerdict.
    readonly property string tailnetVerdict: Model.tailnetVerdict({
        ok: true,
        mode: mode
    }, splitTunnel)

    property string _statusOutput: ""
    property string _statusError: ""
    property string _settingsOutput: ""
    property string _registrationOutput: ""
    property string _statsOutput: ""
    property string _actionOutput: ""
    property string _actionError: ""
    property double _lastRegistrationMs: 0
    property bool _pendingDetails: false

    // ---------------------------------------------------------------- settings
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

    // ----------------------------------------------------------- model facades
    function modeLabel(value) {
        return Model.modeLabel(value);
    }

    function modeDescription(value) {
        return Model.modeDescription(value);
    }

    function copyToClipboard(value) {
        const text = String(value || "");
        if (text === "")
            return;
        Quickshell.execDetached(["wl-copy", "--type", "text/plain", text]);
        flash("Copied");
    }

    function flash(message) {
        actionStatus = Model.elide(message);
        actionStatusTimer.restart();
    }

    // quickshell does not signal a Process child when the shell exits, and
    // `warp-cli registration new` talks to the network.
    function cmd(args) {
        return ["setpriv", "--pdeathsig", "TERM", "--"].concat(args);
    }

    // --accept-tos keeps a fresh install off the interactive prompt; the rest
    // keep the output machine-readable.
    function warpCommand(args) {
        return cmd(["warp-cli", "--accept-tos", "--json", "--no-paginate", "--no-ansi"].concat(args));
    }

    // -------------------------------------------------------------- refreshing
    // The cheap question the bar mark is drawn from.
    function refresh() {
        run(false);
    }

    // Adds settings, registration and stats, which only the panel shows.
    function refreshDetails() {
        run(true);
    }

    function run(full) {
        if (!probed) {
            if (full)
                _pendingDetails = true;
            if (!presenceProcess.running) {
                refreshing = true;
                presenceProcess.command = cmd(["bash", "-c", "command -v warp-cli >/dev/null 2>&1"]);
                presenceProcess.running = true;
            }
            return;
        }
        // Once the probe has said "no CLI here", nothing ever runs again.
        if (!installed)
            return;
        if (full)
            _pendingDetails = true;
        refreshStatus();
    }

    function refreshStatus() {
        if (statusProcess.running)
            return;
        _statusOutput = "";
        _statusError = "";
        refreshing = true;
        _statusLaunchMs = Date.now();
        statusProcess.command = warpCommand(["status"]);
        statusProcess.running = true;
        pollWatchdog.restart();
    }

    // Everything except `status` only makes sense once the daemon answers, so
    // the follow-ups are chained off a status read that came back healthy.
    function launchDetailReads() {
        if (!settingsProcess.running) {
            _settingsOutput = "";
            _settingsLaunchMs = Date.now();
            settingsProcess.command = warpCommand(["settings"]);
            settingsProcess.running = true;
        }
        const now = Date.now();
        if (!registrationProcess.running && (!registered || now - _lastRegistrationMs > 300000)) {
            _lastRegistrationMs = now;
            _registrationOutput = "";
            _registrationLaunchMs = now;
            registrationProcess.command = warpCommand(["registration", "show"]);
            registrationProcess.running = true;
        }
        if (connected && !statsProcess.running) {
            _statsOutput = "";
            _statsLaunchMs = Date.now();
            statsProcess.command = warpCommand(["tunnel", "stats"]);
            statsProcess.running = true;
        } else if (!connected) {
            tunnelStats = ({});
        }
        pollWatchdog.restart();
    }

    function resetUnavailable(message) {
        available = false;
        connected = false;
        connecting = false;
        _desired = -1;
        status = "Unavailable";
        statusText = message;
        reasonText = "";
        tunnelStats = ({});
    }

    // ------------------------------------------------------------- applying it
    function applyStatus(raw, exitCode, stderr) {
        const parsed = Model.parseStatus(raw, exitCode, stderr);
        daemonDown = parsed.daemonDown === true;
        needsTos = parsed.needsTos === true;
        needsRegistration = parsed.needsRegistration === true;
        available = parsed.available === true;
        status = parsed.status;
        statusText = parsed.statusText;
        reasonText = parsed.reasonText || "";

        if (!parsed.ok) {
            lastError = parsed.error || "Could not read warp-cli status";
            connected = false;
            connecting = false;
            _desired = -1;
            return;
        }

        connected = parsed.connected === true;
        connecting = parsed.connecting === true;
        // Reality caught up with the pending toggle — stop overriding it.
        if (_desired !== -1 && connected === (_desired === 1))
            _desired = -1;
        if (parsed.available)
            lastError = "";

        if (daemonDown || needsTos) {
            registered = false;
            mode = "";
            accountLabel = "";
            tunnelStats = ({});
            splitTunnel = ({});
            detailsLoaded = false;
            return;
        }
        launchDetailReads();
    }

    function applySettings(raw) {
        const parsed = Model.parseSettings(raw);
        if (parsed.ok !== true)
            return;
        splitTunnel = Model.parseSplitTunnel(raw);
        mode = parsed.mode;
        alwaysOn = parsed.alwaysOn;
        switchLocked = parsed.switchLocked;
        splitTunnelText = Model.splitTunnelText(parsed);
        disableForWifi = parsed.disableForWifi;
        disableForEthernet = parsed.disableForEthernet;
        familiesMode = parsed.familiesMode;
        detailsLoaded = true;
    }

    function applyRegistration(raw) {
        const parsed = Model.parseRegistration(raw);
        registered = parsed.registered === true;
        accountType = parsed.accountType;
        accountLabel = parsed.accountLabel;
        organization = parsed.organization;
        deviceId = parsed.deviceId;
        deviceName = parsed.deviceName;
        if (!registered)
            needsRegistration = true;
    }

    // ----------------------------------------------------------------- actions
    function toggleConnection() {
        if (!canToggle)
            return;
        if (active)
            disconnect();
        else
            connect();
    }

    function connect() {
        if (!canToggle)
            return;
        if (!registered) {
            register();
            return;
        }
        _desired = 1;
        runAction(["connect"], "Connecting…");
    }

    function disconnect() {
        if (!canToggle)
            return;
        _desired = 0;
        runAction(["disconnect"], "Disconnecting…");
    }

    function register() {
        if (!installed || daemonDown || actionProcess.running)
            return;
        _desired = -1;
        // The next details pass has to re-read the registration rather than sit
        // on the 5-minute throttle.
        _lastRegistrationMs = 0;
        runAction(["registration", "new"], "Registering this device…");
    }

    function setMode(value) {
        const next = String(value || "");
        if (!installed || daemonDown || next === "" || actionProcess.running)
            return;
        if (switchLocked) {
            lastError = "Mode is locked by your organization";
            flash(lastError);
            return;
        }
        if (next === mode)
            return;
        settingMode = next;
        runAction(["mode", next], "Switching to " + Model.modeLabel(next) + "…");
    }

    // Consumer-only on this build (`warp-cli dns families`), and absent from the
    // settings block, so the panel only offers it once something reports a mode.
    function setFamiliesMode(value) {
        const next = String(value || "");
        if (!installed || daemonDown || next === "" || actionProcess.running)
            return;
        runAction(["dns", "families", next], "DNS filtering: " + next);
    }

    // warp-svc is enabled by the package's own systemd preset, so this is a
    // recovery row rather than a normal path. pkexec, and deliberately not
    // wrapped in setpriv: the kernel clears a pending pdeathsig across the
    // setuid exec, and the prompt outliving the shell is the point.
    function startDaemon() {
        if (daemonProcess.running)
            return;
        actionStatus = "Starting the WARP daemon…";
        daemonProcess.command = ["pkexec", "systemctl", "start", "warp-svc"];
        daemonProcess.running = true;
    }

    function runAction(args, label) {
        if (actionProcess.running)
            return;
        actionStatus = label || "";
        _actionOutput = "";
        _actionError = "";
        actionProcess.command = warpCommand(args);
        actionProcess.running = true;
    }

    function finishAction(exitCode) {
        settingMode = "";
        // warp-cli reports failure in the payload at exit 0 as readily as by
        // status, so both have to be checked (see WarpModel.js).
        const message = Model.errorMessage(_actionOutput !== "" ? _actionOutput : _actionError);
        const code = Model.errorCode(_actionOutput !== "" ? _actionOutput : _actionError);
        if (exitCode !== 0 || code !== "") {
            _desired = -1;
            lastError = message !== "" ? message : "warp-cli failed";
            flash(lastError);
        } else if (actionStatus !== "") {
            actionStatusTimer.restart();
        }
        delayedRefresh.restart();
    }

    // ------------------------------------------------------------- the clocks
    readonly property Timer refreshTimer: Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: root.pollingAllowed && root.probed && root.installed
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Right after login warp-svc is usually still starting, which leaves the
    // mark stale until the next slow poll. Ramp quickly, then give up.
    readonly property Timer startupRamp: Timer {
        property int ticks: 0
        interval: 2000
        repeat: true
        running: root.pollingAllowed && root.probed && root.installed && !root.available && ticks < 15
        onTriggered: {
            ticks += 1;
            if (!root.available)
                root.refresh();
        }
    }

    readonly property Timer delayedRefresh: Timer {
        interval: 700
        repeat: false
        onTriggered: root.refreshDetails()
    }

    // Every read is skipped while its own process is still running, so one that
    // never exits silently stops the panel refreshing at all — permanently.
    // Deadlines are per launch so a read started late in the window keeps its
    // remainder instead of being killed with the batch.
    property double _statusLaunchMs: 0
    property double _settingsLaunchMs: 0
    property double _registrationLaunchMs: 0
    property double _statsLaunchMs: 0

    readonly property Timer pollWatchdog: Timer {
        readonly property int windowMs: 15000
        interval: windowMs
        repeat: false
        onTriggered: {
            const now = Date.now();
            const reads = [[root.statusProcess, root._statusLaunchMs], [root.settingsProcess, root._settingsLaunchMs], [root.registrationProcess, root._registrationLaunchMs], [root.statsProcess, root._statsLaunchMs]];
            let nextMs = 0;
            for (let i = 0; i < reads.length; i++) {
                const proc = reads[i][0];
                if (!proc.running)
                    continue;
                const remaining = windowMs - (now - reads[i][1]);
                if (remaining <= 0)
                    proc.running = false;
                else if (nextMs === 0 || remaining < nextMs)
                    nextMs = remaining;
            }
            if (nextMs > 0) {
                interval = nextMs;
                restart();
            } else {
                interval = windowMs;
                root.refreshing = false;
            }
        }
    }

    readonly property Timer actionStatusTimer: Timer {
        interval: 2200
        repeat: false
        onTriggered: root.actionStatus = ""
    }

    // -------------------------------------------------------- the processes
    // The one question asked unconditionally: is warp-cli on this machine?
    readonly property Process presenceProcess: Process {
        running: false
        command: []
        onExited: exitCode => {
            root.probed = true;
            root.installed = exitCode === 0;
            if (root.installed) {
                root.refreshStatus();
            } else {
                root.refreshing = false;
                root._pendingDetails = false;
                root.resetUnavailable("Not installed");
            }
        }
    }

    readonly property Process statusProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._statusOutput = text
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._statusError = text
        }
        onExited: exitCode => {
            root.refreshing = false;
            root._pendingDetails = false;
            root.applyStatus(root._statusOutput, exitCode, root._statusError);
        }
    }

    readonly property Process settingsProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._settingsOutput = text
        }
        onExited: exitCode => root.applySettings(root._settingsOutput)
    }

    readonly property Process registrationProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._registrationOutput = text
        }
        onExited: exitCode => root.applyRegistration(root._registrationOutput)
    }

    readonly property Process statsProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._statsOutput = text
        }
        onExited: exitCode => root.tunnelStats = Model.parseTunnelStats(root._statsOutput)
    }

    readonly property Process actionProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._actionOutput = text
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._actionError = text
        }
        onExited: exitCode => root.finishAction(exitCode)
    }

    readonly property Process daemonProcess: Process {
        running: false
        command: []
        onExited: exitCode => {
            if (exitCode !== 0)
                root.flash("Could not start the WARP daemon");
            root.delayedRefresh.restart();
        }
    }

    Component.onCompleted: refresh()
}

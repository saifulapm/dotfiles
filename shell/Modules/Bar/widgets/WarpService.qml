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
//   * The chaining is actually honoured. Theirs re-reads settings, registration
//     and stats on every tick; here only the panel shows those, so with no
//     panel open the poll is one `status` and nothing else (`viewers`). Their
//     equivalent flag exists but is never read, so their "cheap" poll spawns
//     three processes it has no reader for.
//   * An action gets a watchdog of its own, and a connect/disconnect gets a
//     settle poll. Without the first, one `warp-cli connect` that never exits
//     leaves `busy` true and the switch dead for the life of the shell; without
//     the second, an optimistic `_desired` that reality never matches leaves the
//     bar claiming a tunnel that is not there. Both are live in all three
//     plugins; rpots/omarchy-cloudflare-warp is where the settle poll comes from.
//   * `switch_locked` blocks disconnecting, not switching mode. It is
//     Cloudflare's "Lock WARP switch" policy — the org pinning the client on —
//     and theirs spends it on the mode list instead, which dims seven rows over
//     a flag that has nothing to say about them.
//   * The egress trace, from ussego/owarp: what the daemon believes is not what
//     Cloudflare received, and only the second one can tell you the tunnel is up
//     but idle. Fetched while connected and only with the panel open.
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

    // How many panels are on screen. Everything past `status` — the settings
    // block, the registration record, the tunnel stats, the egress trace — is
    // only ever drawn in a panel, so it follows this rather than the poll: with
    // every panel closed a tick is one process, not four. The panels hold it
    // themselves (a bar per screen can carry one each).
    property int viewers: 0
    readonly property bool detailsVisible: viewers > 0

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
    // Cloudflare's "Lock WARP switch" policy: the org can pin the client on.
    // It is about the switch, not the mode list — see disconnect().
    property bool switchLocked: false
    property string splitTunnelText: ""
    property var splitTunnel: ({})
    property bool disableForWifi: false
    property bool disableForEthernet: false

    property bool registered: false
    property string accountLabel: ""
    property string accountType: ""
    property string organization: ""
    property string deviceId: ""
    property string deviceName: ""

    property var tunnelStats: ({})
    // Cloudflare's own answer about the connection our request arrived over.
    property var trace: ({})
    property string settingMode: ""
    property string actionStatus: ""
    property string lastError: ""
    // A details pass has landed, so an empty split-tunnel list means "none" and
    // not "not looked yet".
    property bool detailsLoaded: false

    readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 20, 5, 3600)
    // The one request this widget makes to the network, and shell.json can
    // switch it off. It only ever goes out while the tunnel is up and a panel
    // is open — never on a machine that is not using WARP, and never at idle.
    readonly property bool egressCheckEnabled: setting("egressCheck", true) === true

    readonly property bool busy: presenceProcess.running || statusProcess.running || settingsProcess.running || registrationProcess.running || statsProcess.running || actionProcess.running || daemonProcess.running

    readonly property var modeRows: Model.modeRows(mode)
    readonly property bool tunnelMode: Model.isTunnelMode(mode)
    readonly property bool canToggle: installed && !daemonDown && !needsTos && !busy && !settling
    // Locked on by policy: the switch stays live so the click can say why.
    readonly property bool lockedOn: switchLocked && connected
    // A connect or disconnect that has gone out and is not yet reflected.
    readonly property bool settling: settleTimer.running

    // The trace, read out. `traceLeaking` is the one that matters: the daemon
    // says connected and Cloudflare says the request came in outside the
    // tunnel. Only ever said about the real `connected`, never the optimistic
    // `active`, so a click cannot make the bar cry leak.
    readonly property bool traceOk: trace && trace.ok === true
    readonly property string traceIp: traceOk ? trace.ip : ""
    readonly property string traceLocation: traceOk ? trace.location : ""
    readonly property string traceWarpLabel: traceOk ? trace.warpLabel : ""
    readonly property bool traceGateway: traceOk && trace.gateway === "on"
    readonly property bool traceLeaking: Model.traceLeaking(connected, trace)

    readonly property var splitTunnelEntries: splitTunnel && splitTunnel.entries ? splitTunnel.entries : []
    readonly property string splitTunnelSummary: splitTunnel && splitTunnel.summary ? splitTunnel.summary : ""
    // The same fact as the summary, in the two halves the panel's disclosure
    // row wants: the mode to set in the reading weight, and what it means to
    // mute beside it.
    readonly property string splitTunnelModeLabel: Model.splitTunnelModeLabel(splitTunnel && splitTunnel.mode ? splitTunnel.mode : "")
    readonly property string splitTunnelMeaning: Model.splitTunnelMeaning(splitTunnel && splitTunnel.mode ? splitTunnel.mode : "", splitTunnelEntries.length)

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
    property string _traceOutput: ""
    property string _actionOutput: ""
    property string _actionError: ""
    property double _lastRegistrationMs: 0
    property double _lastTraceMs: 0
    // When the tunnel last came up, so the egress check can let the routing
    // settle before it is allowed to call anything a leak. 0 while it is down.
    property double _connectedSinceMs: 0
    property bool _pendingDetails: false
    // Which command actionProcess is running, so its watchdog can give a
    // network round trip more room than a local toggle.
    property string _actionKind: ""

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
    // the follow-ups are chained off a status read that came back healthy — and
    // only a panel reads any of them, so with none open this does nothing at
    // all. The exceptions are the two the bar mark itself needs: the mode, for
    // the tooltip, and a registration we have never successfully read.
    function launchDetailReads(wantDetails) {
        const full = wantDetails === true || detailsVisible;
        if (!settingsProcess.running && (full || !detailsLoaded)) {
            _settingsOutput = "";
            _settingsLaunchMs = Date.now();
            settingsProcess.command = warpCommand(["settings"]);
            settingsProcess.running = true;
        }
        const now = Date.now();
        // It changes when you register, and that path clears the throttle.
        if (!registrationProcess.running && (!registered || (full && now - _lastRegistrationMs > 300000))) {
            _lastRegistrationMs = now;
            _registrationOutput = "";
            _registrationLaunchMs = now;
            registrationProcess.command = warpCommand(["registration", "show"]);
            registrationProcess.running = true;
        }
        if (connected && full && !statsProcess.running) {
            _statsOutput = "";
            _statsLaunchMs = Date.now();
            statsProcess.command = warpCommand(["tunnel", "stats"]);
            statsProcess.running = true;
        } else if (!connected) {
            tunnelStats = ({});
        }
        // The trace crosses the network, so it is throttled harder than the
        // local reads and is dropped entirely the moment the tunnel goes down —
        // a stale "through WARP" outliving the connection would be a lie.
        //
        // The five seconds are the important part: warp-svc reports Connected
        // before the routes are necessarily carrying anything, and a trace sent
        // into that gap comes back warp=off. That is not a leak, it is a race,
        // and calling it a leak on the bar would be worse than saying nothing.
        if (!connected) {
            trace = ({});
            _lastTraceMs = 0;
        } else if (full && egressCheckEnabled && !traceProcess.running && _connectedSinceMs !== 0 && now - _connectedSinceMs > 5000 && now - _lastTraceMs > 30000) {
            _lastTraceMs = now;
            _traceLaunchMs = now;
            _traceOutput = "";
            traceProcess.command = cmd(["curl", "-fsS", "--max-time", "5", "https://www.cloudflare.com/cdn-cgi/trace"]);
            traceProcess.running = true;
        }
        pollWatchdog.restart();
    }

    function resetUnavailable(message) {
        available = false;
        connected = false;
        connecting = false;
        _desired = -1;
        settleTimer.stop();
        status = "Unavailable";
        statusText = message;
        reasonText = "";
        tunnelStats = ({});
        trace = ({});
        _connectedSinceMs = 0;
    }

    // ------------------------------------------------------------- applying it
    function applyStatus(raw, exitCode, stderr, wantDetails) {
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
            settleTimer.stop();
            return;
        }

        connected = parsed.connected === true;
        connecting = parsed.connecting === true;
        // Stamped on the edge, not on every read: this is the age of the
        // connection, and the egress check waits on it.
        if (connected && _connectedSinceMs === 0)
            _connectedSinceMs = Date.now();
        else if (!connected)
            _connectedSinceMs = 0;
        // Reality caught up with the pending toggle — stop overriding it, and
        // let the settle poll go home.
        if (_desired !== -1 && connected === (_desired === 1)) {
            _desired = -1;
            settleTimer.stop();
        }
        if (parsed.available)
            lastError = "";

        if (daemonDown || needsTos) {
            registered = false;
            mode = "";
            accountLabel = "";
            tunnelStats = ({});
            trace = ({});
            splitTunnel = ({});
            detailsLoaded = false;
            return;
        }
        launchDetailReads(wantDetails);
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
        detailsLoaded = true;
    }

    // A read that came back with nothing says nothing: the watchdog killing
    // this one used to read as "not registered" and badge the bar. Only a
    // parsed answer is allowed to move any of it.
    function applyRegistration(raw) {
        const parsed = Model.parseRegistration(raw);
        if (parsed.known !== true)
            return;
        registered = parsed.registered === true;
        accountType = parsed.accountType;
        accountLabel = parsed.accountLabel;
        organization = parsed.organization;
        deviceId = parsed.deviceId;
        deviceName = parsed.deviceName;
        // And only the client's own "there is no registration" sets the badge —
        // not, say, a daemon that dropped the socket mid-answer.
        if (parsed.missing === true)
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
        runAction(["connect"], "Connecting…", "connect");
        beginSettle();
    }

    function disconnect() {
        if (!canToggle)
            return;
        // "Lock WARP switch": the org has pinned the client on. The switch
        // stays live rather than going dead, so the click can say so.
        if (switchLocked) {
            lastError = "WARP is locked on by your organization";
            flash(lastError);
            return;
        }
        _desired = 0;
        runAction(["disconnect"], "Disconnecting…", "disconnect");
        beginSettle();
    }

    function register() {
        if (!installed || daemonDown || actionProcess.running)
            return;
        _desired = -1;
        settleTimer.stop();
        // The next details pass has to re-read the registration rather than sit
        // on the 5-minute throttle.
        _lastRegistrationMs = 0;
        runAction(["registration", "new"], "Registering this device…", "register");
    }

    // Not gated on switch_locked: that policy is about the switch. A managed
    // client that also forbids the mode answers with its own error, which is a
    // truthful "no" instead of a guessed one.
    function setMode(value) {
        const next = String(value || "");
        if (!installed || daemonDown || next === "" || actionProcess.running)
            return;
        if (next === mode)
            return;
        settingMode = next;
        runAction(["mode", next], "Switching to " + Model.modeLabel(next) + "…", "mode");
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

    function runAction(args, label, kind) {
        if (actionProcess.running)
            return;
        actionStatus = label || "";
        _actionOutput = "";
        _actionError = "";
        _actionKind = String(kind || "");
        actionProcess.command = warpCommand(args);
        actionProcess.running = true;
        actionWatchdog.restart();
    }

    // A connect or disconnect is a request, not a result: warp-cli returns as
    // soon as the daemon has taken it. Poll from the click until the status
    // agrees, so the panel fills in seconds rather than at the next tick.
    function beginSettle() {
        settleTimer.ticks = 0;
        settleTimer.restart();
    }

    function finishAction(exitCode) {
        actionWatchdog.stop();
        settingMode = "";
        // warp-cli reports failure in the payload at exit 0 as readily as by
        // status, so both have to be checked (see WarpModel.js).
        const message = Model.errorMessage(_actionOutput !== "" ? _actionOutput : _actionError);
        const code = Model.errorCode(_actionOutput !== "" ? _actionOutput : _actionError);
        _actionKind = "";
        if (exitCode !== 0 || code !== "") {
            // The request never landed, so there is nothing to settle and
            // nothing to keep claiming.
            _desired = -1;
            settleTimer.stop();
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
        // Full while a panel is open — its stats and its egress line are the
        // only things that go stale on a tick — and one `status` otherwise.
        onTriggered: root.run(root.detailsVisible)
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
    property double _traceLaunchMs: 0

    readonly property Timer pollWatchdog: Timer {
        readonly property int windowMs: 15000
        interval: windowMs
        repeat: false
        onTriggered: {
            const now = Date.now();
            const reads = [[root.statusProcess, root._statusLaunchMs], [root.settingsProcess, root._settingsLaunchMs], [root.registrationProcess, root._registrationLaunchMs], [root.statsProcess, root._statsLaunchMs], [root.traceProcess, root._traceLaunchMs]];
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

    // The reads have a watchdog; without one here, a `warp-cli connect` that
    // never exits leaves `busy` true and every control in the panel dead for
    // the life of the shell. `registration new` crosses the network and
    // deserves the longer window; the rest are local socket calls.
    readonly property Timer actionWatchdog: Timer {
        interval: root._actionKind === "register" ? 90000 : 30000
        repeat: false
        onTriggered: {
            if (!root.actionProcess.running)
                return;
            root.actionProcess.running = false;
            root._desired = -1;
            root.settleTimer.stop();
            root._actionKind = "";
            root.lastError = "warp-cli did not answer";
            root.flash(root.lastError);
            root.delayedRefresh.restart();
        }
    }

    // warp-cli returns when the daemon accepts a connect, not when the tunnel
    // is up. Poll from there until the status agrees — and give up rather than
    // leave the optimistic mark standing over a connection that never came.
    readonly property Timer settleTimer: Timer {
        property int ticks: 0
        readonly property int limit: 15
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            ticks += 1;
            if (root._desired === -1) {
                stop();
                // It landed: pick up the stats and the egress line for it.
                root.refreshDetails();
                return;
            }
            if (ticks >= limit) {
                const wanted = root._desired === 1;
                root._desired = -1;
                stop();
                root.lastError = wanted ? "WARP did not connect" : "WARP did not disconnect";
                root.flash(root.lastError);
                root.refreshDetails();
                return;
            }
            root.refresh();
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
            // Consumed here rather than cleared: it is what tells the chained
            // reads that this pass was asked for by a panel.
            const wantDetails = root._pendingDetails;
            root._pendingDetails = false;
            root.applyStatus(root._statusOutput, exitCode, root._statusError, wantDetails);
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

    // The only thing here that leaves the machine. `-f` so an error page is an
    // exit code rather than a body we would have to reject by shape, and a hard
    // 5 s cap so a captive portal cannot hold the panel.
    readonly property Process traceProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._traceOutput = text
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                // No answer is not an answer: leave the last one alone rather
                // than turning a flaky network into a leak warning.
                root._lastTraceMs = 0;
                return;
            }
            root.trace = Model.parseTrace(root._traceOutput);
        }
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

import QtQuick
import Quickshell
import Quickshell.Io
import "TailscaleModel.js" as Model

// Tailscale service — port of omarchy's tailscale plugin Service.qml
// (CREDITS.md). It owns everything the widget and the panel read: whether the
// CLI exists at all, what `tailscale status --json` says about this device and
// its tailnet, the Mullvad exit-node table, the list of login profiles, and the
// up/down/switch/exit-node/authorize commands.
//
// What is kept from theirs
//   * the optimistic `_desired` / `active` pair, so the bar mark and the hero
//     line flip the instant you click instead of waiting for tailscaled;
//   * their login dance: `tailscale up` streamed line by line, the first
//     https:// URL to appear on either stream handed to the browser, a 10 s
//     fallback that re-reads the URL out of the status, and the status parse
//     itself opening one it sees while a login is in flight;
//   * the startup ramp (a 2 s retry for ~30 s) that covers tailscaled still
//     connecting when the shell comes up after a fresh boot;
//   * the poll watchdog, armed once per launch rather than restarted every
//     refresh, that reaps a `tailscale` hung on a network coming and going —
//     without it one stuck process stops every later refresh, permanently;
//   * the delayed refresh after every command, the 2.2 s action-status expiry,
//     and the 60 s account-list throttle;
//   * their operator escape hatch: a profile read refused with "profiles
//     access denied" raises a row that runs
//     `pkexec tailscale set --operator=$USER`.
//
// What differs
//   * Nothing runs until one presence probe (`command -v tailscale`) answers,
//     and nothing ever runs again once it answers no. That probe is the whole
//     widget's gate, where theirs re-runs `which` on every refresh forever.
//   * The periodic refresh asks only for the status — the one thing the bar
//     mark is drawn from. The Mullvad exit-node table and the profile list are
//     read when the panel opens or is refreshed by hand. Upstream runs all
//     three on every tick, whether or not anyone is looking, down to a
//     five-second interval.
//   * The timer runs only while the widget is on a visible bar. This shell
//     does not poll at idle; tailscaled offers no event source we can watch
//     without holding its socket open, so their cadence is kept and scoped to
//     when it can be seen.
//   * Every privileged refusal raises the authorize row, not just the one
//     wording their profile list produces (see Model.isAccessDenied).
//   * The browser is reached with Qt.openUrlExternally rather than
//     `omarchy-launch-browser`, and Taildrop sends go to our own
//     bin/tailscale-send.
//   * Every child process is wrapped in `setpriv --pdeathsig TERM`: quickshell
//     does not signal a Process child when the shell exits, and `tailscale up`
//     can sit waiting on a browser login for as long as it takes.
QtObject {
    id: root

    property var settings: ({})
    // False while the widget is off-screen; the periodic refresh follows it.
    property bool pollingAllowed: false

    readonly property string sendHelperPath: Quickshell.env("HOME") + "/.dotfiles/bin/tailscale-send"

    // The presence probe has answered at least once. Until then the widget
    // shows nothing at all, rather than flashing a mark it will take back.
    property bool probed: false
    property bool installed: false
    property bool running: false
    property bool needsLogin: false

    // Optimistic off state so the UI reacts the instant you click, rather than
    // waiting for the next status refresh. _desired is -1 while we just follow
    // the real state, or 0/1 while a toggle is still catching up.
    property int _desired: -1
    readonly property bool active: _desired === -1 ? running : (_desired === 1)
    property bool refreshing: false
    property string backendState: "Unknown"
    property string statusText: "Checking…"
    property string selfName: ""
    property string selfDnsName: ""
    property string selfIp: ""
    property string selfUserId: ""
    property bool fileSharing: false
    property string authUrl: ""
    property var peers: []
    property var exitNodes: []
    property var tailnetExitNodes: []
    property var mullvadExitNodes: []
    property var mullvadRegions: []
    property var accounts: []
    property string selectedAccountId: ""
    property string selectedAccountLabel: ""
    property string switchingAccountId: ""
    property string settingExitNodeId: ""
    property bool accountsAccessDenied: false
    property string actionStatus: ""
    property string lastError: ""
    // A details pass has landed, so an empty exit-node list means "none" and
    // not "not looked yet".
    property bool detailsLoaded: false

    readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
    readonly property bool busy: presenceProcess.running || statusProcess.running || exitNodeListProcess.running || accountsProcess.running || actionProcess.running || loginProcess.running || switchProcess.running || operatorProcess.running || exitNodeProcess.running
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

    property string _statusOutput: ""
    property string _statusError: ""
    property string _accountsOutput: ""
    property string _accountsError: ""
    property string _exitNodeListOutput: ""
    property string _exitNodeListError: ""
    property string _actionOutput: ""
    property string _actionError: ""
    property string _loginOutput: ""
    property string _loginError: ""
    property bool _loginInProgress: false
    property bool _loginUrlOpened: false
    property string _preLoginAuthUrl: ""
    property double _lastAccountsRefreshMs: 0
    property string _switchOutput: ""
    property string _switchError: ""
    property string _exitNodeOutput: ""
    property string _exitNodeError: ""
    property string _operatorOutput: ""
    property string _operatorError: ""
    // A details pass asked for while the presence probe is still in flight —
    // the panel opens on top of the startup probe often enough.
    property bool _pendingDetails: false

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

    // quickshell does not signal a Process child when the shell exits, and
    // `tailscale up` can wait on a browser login indefinitely.
    function cmd(args) {
        return ["setpriv", "--pdeathsig", "TERM", "--"].concat(args);
    }

    function filterIPv4(ips) {
        return Model.filterIPv4(ips);
    }

    function cleanDnsName(name) {
        return Model.cleanDnsName(name);
    }

    function shortDnsName(name) {
        return Model.shortDnsName(name);
    }

    function displayHostName(hostName, dnsName) {
        return Model.displayHostName(hostName, dnsName);
    }

    function osIcon(os) {
        return Model.osIcon(os);
    }

    function accountLabel(account) {
        return Model.accountLabel(account);
    }

    function copyToClipboard(value) {
        const text = String(value || "");
        if (text === "")
            return;
        Quickshell.execDetached(["wl-copy", "--type", "text/plain", text]);
    }

    function copyPeerIp(peer) {
        if (!peer)
            return;
        const ips = filterIPv4(peer.TailscaleIPs || []);
        copyToClipboard(ips.length > 0 ? ips[0] : "");
    }

    function copyPeerName(peer) {
        if (!peer)
            return;
        copyToClipboard(displayHostName(peer.HostName, peer.DNSName));
    }

    function copyPeerDnsName(peer) {
        if (!peer)
            return;
        copyToClipboard(cleanDnsName(peer.DNSName));
    }

    function peerAddress(peer) {
        if (!peer)
            return "";
        if (peer.DNSName)
            return cleanDnsName(peer.DNSName);
        if (peer.HostName)
            return String(peer.HostName);
        const ips = filterIPv4(peer.TailscaleIPs || []);
        return ips.length > 0 ? ips[0] : "";
    }

    function canSendFiles(peer) {
        if (!fileSharing || !running || !peer)
            return false;
        return Model.isTaildropTarget(peer, selfUserId);
    }

    function sendFile(peer) {
        if (!canSendFiles(peer))
            return;
        const target = peerAddress(peer);
        if (target === "")
            return;
        Quickshell.execDetached([sendHelperPath, target]);
    }

    // ------------------------------------------------------------ refreshing
    // The cheap question the bar mark is drawn from.
    function refresh() {
        run(false, false);
    }

    // Adds the Mullvad exit-node table and the profile list, which only the
    // panel ever shows.
    function refreshDetails(forceAccounts) {
        run(true, forceAccounts === true);
    }

    function run(full, forceAccounts) {
        if (!probed) {
            if (full)
                _pendingDetails = true;
            if (!presenceProcess.running) {
                refreshing = true;
                presenceProcess.command = cmd(["bash", "-c", "command -v tailscale >/dev/null 2>&1"]);
                presenceProcess.running = true;
            }
            return;
        }
        // Once the probe has said "no CLI here", nothing ever runs again.
        if (!installed)
            return;
        launchReads(full, forceAccounts);
    }

    function launchReads(full, forceAccounts) {
        let launched = false;
        if (!statusProcess.running) {
            _statusOutput = "";
            _statusError = "";
            refreshing = true;
            statusProcess.command = cmd(["tailscale", "status", "--json"]);
            statusProcess.running = true;
            launched = true;
        }
        if (full) {
            if (!exitNodeListProcess.running) {
                _exitNodeListOutput = "";
                _exitNodeListError = "";
                exitNodeListProcess.command = cmd(["tailscale", "exit-node", "list"]);
                exitNodeListProcess.running = true;
                launched = true;
            }
            const now = Date.now();
            const shouldRefreshAccounts = forceAccounts === true || accounts.length === 0 || now - _lastAccountsRefreshMs > 60000;
            if (shouldRefreshAccounts && !accountsProcess.running) {
                _accountsOutput = "";
                _accountsError = "";
                _lastAccountsRefreshMs = now;
                accountsProcess.command = cmd(["tailscale", "switch", "--list", "--json"]);
                accountsProcess.running = true;
                launched = true;
            }
        }
        // Arm on the launch that needs watching and leave it alone after that.
        // Restarting it every refresh pushes the deadline out ahead of a hung
        // process forever once the refresh interval is shorter than the
        // timeout, and refreshIntervalSec goes down to five seconds.
        if (launched && !pollWatchdog.running)
            pollWatchdog.start();
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // Ours: tailscale refuses privileged verbs in prose on stderr, so the
    // authorize row is raised from whatever prose we got rather than only from
    // the profile list's own wording.
    function noteAccessDenied(text) {
        if (!Model.isAccessDenied(text))
            return false;
        accountsAccessDenied = true;
        return true;
    }

    function resetUnavailable(message) {
        running = false;
        needsLogin = false;
        _desired = -1;
        backendState = "Unavailable";
        statusText = message;
        selfName = "";
        selfDnsName = "";
        selfIp = "";
        selfUserId = "";
        fileSharing = false;
        authUrl = "";
        peers = [];
        exitNodes = [];
        tailnetExitNodes = [];
        mullvadExitNodes = [];
        mullvadRegions = [];
        accounts = [];
        selectedAccountId = "";
        selectedAccountLabel = "";
        switchingAccountId = "";
        settingExitNodeId = "";
        accountsAccessDenied = false;
    }

    function parseStatus(raw) {
        const parsed = Model.parseStatus(raw);
        if (!parsed.ok) {
            resetUnavailable(parsed.message || "Status error");
            lastError = parsed.error || "Failed to parse tailscale status";
            console.warn("tailscale:", lastError);
            return;
        }
        if (parsed.unavailable) {
            resetUnavailable(parsed.message || "Disconnected");
            return;
        }

        backendState = parsed.backendState;
        running = parsed.running;
        // Reality caught up to the pending toggle — stop overriding.
        if (_desired !== -1 && running === (_desired === 1))
            _desired = -1;
        needsLogin = parsed.needsLogin;
        authUrl = parsed.authUrl;
        if (needsLogin && _loginInProgress && !_loginUrlOpened && authUrl !== "" && authUrl !== _preLoginAuthUrl)
            openAuthUrlFrom(authUrl, false);
        selfName = parsed.selfName;
        selfDnsName = parsed.selfDnsName;
        selfIp = parsed.selfIp;
        selfUserId = parsed.selfUserId;
        fileSharing = parsed.fileSharing;
        peers = parsed.running ? parsed.peers : [];
        tailnetExitNodes = parsed.running ? parsed.exitNodes : [];
        exitNodes = parsed.running ? tailnetExitNodes.concat(mullvadRegions) : [];

        if (needsLogin)
            statusText = "Needs login";
        else if (running) {
            statusText = "Connected";
            _loginInProgress = false;
            _loginUrlOpened = false;
            _preLoginAuthUrl = "";
            loginTimeoutTimer.stop();
        } else if (backendState === "Stopped")
            statusText = "Disconnected";
        else
            statusText = backendState;
        lastError = "";
    }

    function parseAccounts(raw) {
        const parsed = Model.parseAccounts(raw);
        accounts = parsed.accounts;
        selectedAccountId = parsed.selectedAccountId;
        selectedAccountLabel = parsed.selectedAccountLabel;
        accountsAccessDenied = false;
    }

    function parseExitNodeList(raw) {
        mullvadExitNodes = Model.parseExitNodeList(raw);
        mullvadRegions = Model.mullvadRegionOptions(mullvadExitNodes);
        exitNodes = running ? tailnetExitNodes.concat(mullvadRegions) : [];
    }

    // -------------------------------------------------------------- commands
    function toggleTailscale() {
        if (!installed)
            return;
        if (active)
            down();
        else
            loginOrUp();
    }

    function down() {
        // No progress status here — the greyed mark and the hero line already
        // convey the optimistic off; only surface a message if it fails.
        _desired = 0;
        runAction(cmd(["tailscale", "down"]));
    }

    function loginOrUp() {
        if (!installed || loginProcess.running)
            return;
        _desired = -1;
        const plan = Model.loginPlan(needsLogin, authUrl);
        if (plan.authUrl !== "") {
            _loginUrlOpened = false;
            openAuthUrlFrom(plan.authUrl, true);
            return;
        }
        _loginOutput = "";
        _loginError = "";
        if (needsLogin)
            actionStatus = "Starting Tailscale login…";
        else
            _desired = 1;
        _loginInProgress = needsLogin;
        _loginUrlOpened = false;
        _preLoginAuthUrl = authUrl;
        loginProcess.command = cmd(plan.command);
        loginProcess.running = true;
        if (needsLogin)
            loginTimeoutTimer.restart();
    }

    function switchAccount(id) {
        const accountId = String(id || "");
        if (!installed || accountId === "" || accountId === selectedAccountId || switchProcess.running)
            return;
        _switchOutput = "";
        _switchError = "";
        switchingAccountId = accountId;
        switchProcess.command = cmd(["tailscale", "switch", accountId]);
        switchProcess.running = true;
    }

    function exitNodeTarget(peer) {
        if (!peer)
            return "";
        if (peer.Mullvad === true) {
            const mullvadIps = filterIPv4(peer.TailscaleIPs || []);
            if (mullvadIps.length > 0)
                return mullvadIps[0];
        }
        return peerAddress(peer);
    }

    function setExitNode(peer) {
        if (!installed || !running || !peer || exitNodeProcess.running)
            return;
        const isActive = peer.ExitNode === true;
        const target = isActive ? "" : exitNodeTarget(peer);
        if (!isActive && target === "")
            return;
        _exitNodeOutput = "";
        _exitNodeError = "";
        settingExitNodeId = String(peer.id || "");
        exitNodeProcess.command = cmd(["tailscale", "set", "--exit-node=" + target]);
        exitNodeProcess.running = true;
    }

    function authorizeTailscaleOperator() {
        if (!installed || operatorProcess.running || userName === "")
            return;
        _operatorOutput = "";
        _operatorError = "";
        actionStatus = "Authorizing Tailscale operator…";
        // Deliberately not wrapped in setpriv: the kernel clears a pending
        // parent-death signal across pkexec's credential change anyway.
        operatorProcess.command = ["pkexec", "tailscale", "set", "--operator=" + userName];
        operatorProcess.running = true;
    }

    function runAction(command, label) {
        if (actionProcess.running)
            return;
        _actionOutput = "";
        _actionError = "";
        actionStatus = label || "";
        actionProcess.command = command;
        actionProcess.running = true;
    }

    function openAuthUrlFrom(text, allowFallback) {
        if (_loginUrlOpened)
            return true;
        const match = String(text || "").match(/https?:\/\/\S+/);
        const url = match && match[0] ? match[0] : (allowFallback === true ? authUrl : "");
        if (url !== "") {
            // Turning on ended up needing browser auth — stop pretending we
            // are up.
            _desired = -1;
            _loginUrlOpened = true;
            _loginInProgress = false;
            loginTimeoutTimer.stop();
            Qt.openUrlExternally(url);
            actionStatus = "Opened the Tailscale login page";
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
        if (_loginInProgress && !_loginUrlOpened)
            openAuthUrlFrom(text, false);
    }

    // ------------------------------------------------------------ the clocks
    // Their periodic refresh, scoped to a visible widget with a CLI behind it.
    readonly property Timer refreshTimer: Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: root.pollingAllowed && root.probed && root.installed
        onTriggered: root.refresh()
    }

    // After a fresh boot the startup poll usually lands before tailscaled has
    // connected, which left the mark stale until the next periodic refresh.
    // Poll quickly until the service shows up, or give up after ~30 seconds.
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
        interval: 600
        repeat: false
        onTriggered: root.refresh()
    }

    // Every poll is skipped while its own process is still running, so one that
    // never exits — tailscale can hang on a network that is coming and going —
    // silently stops the panel refreshing at all, and it stays stopped. Reap
    // anything still running well inside the refresh interval so the next tick
    // starts clean.
    readonly property Timer pollWatchdog: Timer {
        interval: 15000
        repeat: false
        onTriggered: {
            if (root.statusProcess.running)
                root.statusProcess.running = false;
            if (root.exitNodeListProcess.running)
                root.exitNodeListProcess.running = false;
            if (root.accountsProcess.running)
                root.accountsProcess.running = false;
        }
    }

    readonly property Timer actionStatusTimer: Timer {
        interval: 2200
        repeat: false
        onTriggered: root.actionStatus = ""
    }

    readonly property Timer loginTimeoutTimer: Timer {
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root._loginInProgress || root._loginUrlOpened)
                return;
            if (!root.openAuthUrlFrom(root.authUrl, true)) {
                root._loginInProgress = false;
                root.actionStatus = "Tailscale login link not available yet";
                root.actionStatusTimer.restart();
            }
        }
    }

    // --------------------------------------------------------- the processes
    // The one question asked unconditionally: is Tailscale on this machine?
    readonly property Process presenceProcess: Process {
        running: false
        command: []
        onExited: exitCode => {
            root.probed = true;
            root.installed = exitCode === 0;
            if (root.installed) {
                const full = root._pendingDetails;
                root._pendingDetails = false;
                root.launchReads(full, full);
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
                root.parseStatus(out);
            else {
                root.resetUnavailable("Disconnected");
                root.lastError = root.elideStatus(err);
                root.noteAccessDenied(err);
            }
        }
    }

    readonly property Process accountsProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: accountsStdout
            waitForEnd: true
            onStreamFinished: root._accountsOutput = text
        }
        stderr: StdioCollector {
            id: accountsStderr
            waitForEnd: true
            onStreamFinished: root._accountsError = text
        }
        onExited: exitCode => {
            const out = String(accountsStdout.text || root._accountsOutput || "");
            const err = String(accountsStderr.text || root._accountsError || "");
            if (exitCode === 0)
                root.parseAccounts(out);
            else {
                root.parseAccounts("");
                if (root.noteAccessDenied(err) || root.noteAccessDenied(out))
                    root.lastError = "Authorize the Tailscale operator to show connections";
                else
                    root.lastError = root.elideStatus(err || out || "Could not list Tailscale connections");
            }
        }
    }

    readonly property Process exitNodeListProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: exitNodeListStdout
            waitForEnd: true
            onStreamFinished: root._exitNodeListOutput = text
        }
        stderr: StdioCollector {
            id: exitNodeListStderr
            waitForEnd: true
            onStreamFinished: root._exitNodeListError = text
        }
        onExited: exitCode => {
            const out = String(exitNodeListStdout.text || root._exitNodeListOutput || "");
            // A tailnet with no Mullvad add-on answers non-zero; that is a
            // "none", not a failure worth putting on screen.
            root.parseExitNodeList(exitCode === 0 ? out : "");
            root.detailsLoaded = true;
        }
    }

    readonly property Process actionProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: actionStdout
            waitForEnd: true
            onStreamFinished: root._actionOutput = text
        }
        stderr: StdioCollector {
            id: actionStderr
            waitForEnd: true
            onStreamFinished: root._actionError = text
        }
        onExited: exitCode => {
            const out = String(actionStdout.text || root._actionOutput || "");
            const err = String(actionStderr.text || root._actionError || "");
            if (exitCode !== 0) {
                root._desired = -1;
                root.noteAccessDenied(err || out);
                root.lastError = root.elideStatus(err || out || "Tailscale command failed");
                root.actionStatus = root.lastError;
                root.actionStatusTimer.restart();
            } else {
                root.lastError = "";
                root.actionStatus = "";
            }
            root.delayedRefresh.restart();
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
            const opened = root.openAuthUrlFrom(combined, true);
            if (exitCode !== 0 && !opened) {
                root._desired = -1;
                root._loginInProgress = false;
                root.noteAccessDenied(combined);
                root.lastError = root.elideStatus(combined || "tailscale up failed");
                root.actionStatus = root.lastError;
                root.actionStatusTimer.restart();
            } else if (!opened) {
                root.lastError = "";
                root.actionStatus = "";
            }
            root.delayedRefresh.restart();
        }
    }

    readonly property Process switchProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: switchStdout
            waitForEnd: true
            onStreamFinished: root._switchOutput = text
        }
        stderr: StdioCollector {
            id: switchStderr
            waitForEnd: true
            onStreamFinished: root._switchError = text
        }
        onExited: exitCode => {
            const out = String(switchStdout.text || root._switchOutput || "");
            const err = String(switchStderr.text || root._switchError || "");
            if (exitCode !== 0) {
                root.noteAccessDenied(err || out);
                root.lastError = root.elideStatus(err || out || "Account switch failed");
                root.actionStatus = root.lastError;
                root.actionStatusTimer.restart();
            } else {
                root.lastError = "";
                root.actionStatus = "";
                root._lastAccountsRefreshMs = 0;
            }
            root.switchingAccountId = "";
            root.delayedRefresh.restart();
        }
    }

    readonly property Process exitNodeProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: exitNodeStdout
            waitForEnd: true
            onStreamFinished: root._exitNodeOutput = text
        }
        stderr: StdioCollector {
            id: exitNodeStderr
            waitForEnd: true
            onStreamFinished: root._exitNodeError = text
        }
        onExited: exitCode => {
            const out = String(exitNodeStdout.text || root._exitNodeOutput || "");
            const err = String(exitNodeStderr.text || root._exitNodeError || "");
            if (exitCode !== 0) {
                root.noteAccessDenied(err || out);
                root.lastError = root.elideStatus(err || out || "Exit node selection failed");
                root.actionStatus = root.lastError;
                root.actionStatusTimer.restart();
            } else {
                root.lastError = "";
                root.actionStatus = "";
            }
            root.settingExitNodeId = "";
            root.delayedRefresh.restart();
        }
    }

    readonly property Process operatorProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: operatorStdout
            waitForEnd: true
            onStreamFinished: root._operatorOutput = text
        }
        stderr: StdioCollector {
            id: operatorStderr
            waitForEnd: true
            onStreamFinished: root._operatorError = text
        }
        onExited: exitCode => {
            const out = String(operatorStdout.text || root._operatorOutput || "");
            const err = String(operatorStderr.text || root._operatorError || "");
            if (exitCode !== 0) {
                root.lastError = root.elideStatus(err || out || "Tailscale authorization failed");
                root.actionStatus = root.lastError;
                root.actionStatusTimer.restart();
            } else {
                root.accountsAccessDenied = false;
                root.lastError = "";
                root.actionStatus = "Tailscale operator authorized";
                root.actionStatusTimer.restart();
                root._lastAccountsRefreshMs = 0;
            }
            root.delayedRefresh.restart();
        }
    }

    Component.onCompleted: refresh()
}

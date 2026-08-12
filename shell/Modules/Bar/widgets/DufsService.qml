import QtQuick
import Quickshell
import Quickshell.Io

// Dufs service — ours, in the shape of DevServicesService: it owns everything
// the widget and the panel read about the on-demand dufs file server
// (bin/dufs-serve behind the dufs.service user unit — $HOME over HTTP on
// port 5000, basic auth with the fixed password `developer`). ONE instance
// however many screens carry the widget (S2).
//
// State observation is event-driven, never polled: the unit's
// ExecStartPost/ExecStopPost write "on"/"off" into
// ~/.local/state/qshell/dufs-on and the FileView watcher follows the content.
// One-shot probes cover what the flag cannot say: presence at startup
// plus one stale-flag reconcile, and — on panel open only — the unit's own
// word and the addresses the URLs are built from.
QtObject {
    id: root

    // The presence probe has answered at least once. Until then the widget
    // shows nothing at all, rather than flashing a mark it will take back.
    property bool probed: false
    property bool installed: false

    // The flag file's word, patched by is-active probes. A power loss can
    // strand the flag on; the reconcile at startup and panel open corrects.
    property bool running: false
    // "" | "starting" | "stopping" while a toggle settles — cleared by the
    // matching flag transition, a failed systemctl, or the expiry sweep.
    property string pending: ""
    // Optimistic state for the mark and the switch: the click shows before
    // systemd answers.
    readonly property bool active: pending === "starting" ? true : (pending === "stopping" ? false : running)

    readonly property int port: 5000
    // Fixed sign-in (user decision 2026-08-07): whatever bin/dufs-serve
    // bakes — $USER and `developer123!` — so there is nothing to probe.
    readonly property string authUser: Quickshell.env("USER") || ""
    readonly property string authPassword: "developer123!"
    property string lanIp: ""
    property string tailscaleIp: ""
    readonly property string localUrl: "http://127.0.0.1:" + port
    readonly property string lanUrl: lanIp === "" ? "" : "http://" + lanIp + ":" + port
    readonly property string tailscaleUrl: tailscaleIp === "" ? "" : "http://" + tailscaleIp + ":" + port

    property bool refreshing: false
    property string actionStatus: ""
    property string lastError: ""

    readonly property string flagPath: Quickshell.env("HOME") + "/.local/state/qshell/dufs-on"

    property string _unitOutput: ""
    property string _addrOutput: ""
    property string _controlError: ""

    // quickshell does not signal a Process child when the shell exits.
    function cmd(args) {
        return ["setpriv", "--pdeathsig", "TERM", "--"].concat(args);
    }

    // ------------------------------------------------------------ refreshing
    // The cheap question: presence once, then the unit's word. Startup, panel
    // open, and explicit refresh only — there is no timer in this file.
    function refresh() {
        if (!probed) {
            if (!presenceProcess.running) {
                refreshing = true;
                presenceProcess.command = cmd(["bash", "-c", "command -v dufs >/dev/null 2>&1 || test -x \"$HOME/.cargo/bin/dufs\""]);
                presenceProcess.running = true;
            }
            return;
        }
        if (!installed)
            return;
        if (!unitProcess.running) {
            _unitOutput = "";
            refreshing = true;
            unitProcess.command = cmd(["systemctl", "--user", "is-active", "dufs.service"]);
            unitProcess.running = true;
        }
    }

    // Adds what only the panel shows: the LAN/tailscale addresses.
    function refreshDetails() {
        refresh();
        if (!probed || !installed)
            return;
        if (!addrProcess.running) {
            _addrOutput = "";
            addrProcess.command = cmd(["bash", "-c", "lan=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \\([0-9.]*\\).*/\\1/p' | sed -n 1p); ts=$(tailscale ip -4 2>/dev/null | sed -n 1p); printf '%s\\n%s\\n' \"$lan\" \"$ts\""]);
            addrProcess.running = true;
        }
    }

    function applyFlag(on) {
        running = on;
        if ((pending === "starting" && on) || (pending === "stopping" && !on))
            pending = "";
    }

    function parseAddresses(raw) {
        const lines = String(raw || "").split("\n");
        lanIp = (lines[0] || "").trim();
        tailscaleIp = (lines[1] || "").trim();
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // -------------------------------------------------------------- commands
    function toggle() {
        if (!installed || pending !== "" || controlProcess.running)
            return;
        const starting = !active;
        pending = starting ? "starting" : "stopping";
        pendingExpiry.restart();
        _controlError = "";
        controlProcess.command = cmd(["systemctl", "--user", starting ? "start" : "stop", "dufs.service"]);
        controlProcess.running = true;
    }

    function openBrowser() {
        if (!active)
            return;
        Qt.openUrlExternally(lanUrl !== "" ? lanUrl : localUrl);
    }

    function copyToClipboard(value, label) {
        const text = String(value || "");
        if (text === "")
            return;
        Quickshell.execDetached(["wl-copy", "--type", "text/plain", text]);
        actionStatus = "Copied " + (label || "to the clipboard");
        actionStatusTimer.restart();
    }

    // ------------------------------------------------------------ the clocks
    // Only the failsafes — a pending is normally cleared by its flag
    // transition within a second, and the rows must not read "Starting…"
    // forever if systemd never answers.
    readonly property Timer pendingExpiry: Timer {
        interval: 15000
        repeat: false
        onTriggered: {
            root.pending = "";
            root.refresh();
        }
    }

    readonly property Timer actionStatusTimer: Timer {
        interval: 2200
        repeat: false
        onTriggered: root.actionStatus = ""
    }

    // --------------------------------------------------------- the processes
    readonly property Process presenceProcess: Process {
        running: false
        command: []
        onExited: exitCode => {
            root.probed = true;
            root.installed = exitCode === 0;
            root.refreshing = false;
            // One reconcile so a flag stranded by a power loss cannot leave
            // the mark lit until someone opens the panel.
            if (root.installed)
                root.refresh();
        }
    }

    readonly property Process unitProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: unitStdout
            waitForEnd: true
            onStreamFinished: root._unitOutput = text
        }
        // `is-active` exits non-zero for everything but "active"; the word on
        // stdout is the answer in either case.
        onExited: {
            root.refreshing = false;
            const out = String(unitStdout.text || root._unitOutput || "").trim().split("\n")[0];
            root.applyFlag(out === "active" || out === "activating");
        }
    }

    readonly property Process addrProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: addrStdout
            waitForEnd: true
            onStreamFinished: root._addrOutput = text
        }
        onExited: root.parseAddresses(String(addrStdout.text || root._addrOutput || ""))
    }

    readonly property Process controlProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: controlStderr
            waitForEnd: true
            onStreamFinished: root._controlError = text
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.pending = "";
                root.lastError = root.elideStatus(root._controlError || "systemctl command failed");
                root.refresh();
            } else {
                root.lastError = "";
            }
        }
    }

    // The unit's own report — "on"/"off" content, written and never removed,
    // so the read only fails (one log WARN) on a machine that has never run
    // dufs. `reload()` at startup matters: the view stays unloaded until
    // something reads it, and neither loaded nor loadFailed ever fires until
    // then.
    readonly property FileView flagFile: FileView {
        path: root.flagPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyFlag(text().trim() === "on")
        onLoadFailed: root.applyFlag(false)
        Component.onCompleted: reload()
    }

    Component.onCompleted: refresh()
}

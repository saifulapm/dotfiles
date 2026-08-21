import QtQuick
import Quickshell
import Quickshell.Io
import "PortsModel.js" as Model

// Ports service — what is listening, for the ports widget and panel. ONE
// instance however many screens carry the widget (S2); created at the bar
// root.
//
// NO FOLLOWER, and that is a deliberate admission rather than an oversight.
// The other event-driven services here each have a real event source —
// systemd's JobRemoved, udev, sunsetr's own stream. A socket entering LISTEN
// has no such thing short of a netlink sock_diag subscription, which would
// mean a privileged helper for a panel that answers a question nobody asks
// while it is shut.
//
// So the cadence is: once at startup, on every panel open, and 2 s while the
// panel is on screen — the shell's approved "panels refreshing while open"
// exception, and nothing at all the rest of the time. The tooltip can
// therefore be a few minutes stale on a bar nobody has clicked, which is the
// right trade for a list whose whole audience is someone about to look at it.
QtObject {
    id: root

    property bool probed: false

    property var rows: []

    // Set by the panel while it is on screen; the refresher gates on it.
    property bool panelOpen: false

    // Counted over PORTS, not raw sockets: a service on both v4 and v6 is one
    // listener to a person, and the bar tooltip is written for a person.
    readonly property var ports: Model.groupByPort(rows)
    readonly property int listenerCount: ports.length
    readonly property int mineCount: ports.filter(row => !Model.isDeclared(row)).length
    readonly property int exposedCount: ports.filter(row => Model.isExposed(row)).length
    readonly property string tooltip: Model.tooltipText(rows)

    readonly property string home: Quickshell.env("HOME") || ""

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
    }

    function applyList(raw) {
        probed = true;
        rows = Model.parseRows(raw);
        lastError = "";
    }

    function ranked(query) {
        return Model.rank(rows, query);
    }

    // ------------------------------------------------------------- actions
    function openUrl(row) {
        const url = Model.urlFor(row);
        if (url === "")
            return;
        Quickshell.execDetached(["xdg-open", url]);
    }

    function copyUrl(row) {
        const url = Model.urlFor(row);
        if (url === "")
            return;
        Quickshell.execDetached(["bash", "-c", "printf '%s' \"$1\" | wl-copy", "--", url]);
    }

    // A QR of the URL, so a phone on the same network can open the dev
    // server without anyone typing an IP address off a screen.
    //
    // The matrix comes from bin/network-qr --text, which is the Wi-Fi share
    // helper's renderer with the payload made arbitrary — one qrencode
    // wrapper for the shell rather than two. It arrives as rows of 0/1 and
    // the panel paints it with native rectangles, so nothing is written to
    // disk and there is no image to cache.
    //
    // The Wi-Fi overlay (NetworkQrPanel) is deliberately NOT reused: it is
    // built around an SSID and a passphrase, and generalizing a working
    // surface to carry a URL is a bigger change than painting sixty
    // rectangles here.
    property var qrRows: []
    property int qrPort: 0
    property string qrUrl: ""

    function requestQr(row) {
        const url = Model.urlFor(row);
        if (url === "" || qrProcess.running)
            return;
        // Clicking the same row again puts it away.
        if (qrPort === row.port) {
            clearQr();
            return;
        }
        qrRows = [];
        qrPort = row.port;
        qrUrl = url;
        qrProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "network-qr", "--text", url];
        qrProcess.running = true;
    }

    function clearQr() {
        qrRows = [];
        qrPort = 0;
        qrUrl = "";
    }

    function openDirectory(row) {
        if (!row || !row.cwd)
            return;
        Quickshell.execDetached(["xdg-open", String(row.cwd)]);
    }

    // Stop a listener. BOTH the pid and the start time go to bin/ports,
    // which refuses the pair if they no longer describe the same process —
    // the PID-reuse guard. Nothing here decides that it is safe; the script
    // re-checks against /proc at the moment of the signal.
    function stop(row) {
        if (!Model.isKillable(row))
            return;
        stopProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "ports", "kill", String(row.pid), String(row.start)];
        stopProcess.running = true;
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // ----------------------------------------------------------- the clocks
    // The whole cadence, and its `running` condition is the compliance: the
    // panel is on screen. Two seconds is slow enough to cost nothing and
    // fast enough that a `pnpm dev` started in another window shows up while
    // the panel is still open.
    readonly property Timer refreshTimer: Timer {
        interval: 2000
        repeat: true
        running: root.panelOpen
        onTriggered: root.refresh()
    }

    // --------------------------------------------------------- the processes
    readonly property Process listProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "ports"]
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
                root.lastError = root.elideStatus(err || "Could not list listening ports");
            }
        }
    }

    readonly property Process qrProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: qrStdout
            waitForEnd: true
            onStreamFinished: {
                const lines = String(qrStdout.text || "").split("\n").filter(line => line.length > 0);
                // A matrix is square; anything else means qrencode failed or
                // printed a message, and painting it would be nonsense.
                if (lines.length === 0 || lines.some(line => line.length !== lines.length)) {
                    root.clearQr();
                    root.lastError = "Could not build a QR code for that URL";
                    return;
                }
                root.qrRows = lines;
            }
        }
        stderr: StdioCollector {
            id: qrStderr
            waitForEnd: true
            onStreamFinished: if (String(qrStderr.text || "").trim() !== "") {
                root.clearQr();
                root.lastError = root.elideStatus(qrStderr.text);
            }
        }
    }

    readonly property Process stopProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: stopStderr
            waitForEnd: true
            onStreamFinished: root._error = text
        }
        onExited: exitCode => {
            // bin/ports' refusals are the interesting output here — "that is
            // not the process that was listed", "belongs to uid 0" — so they
            // are surfaced verbatim rather than replaced with a generic
            // failure.
            if (exitCode !== 0)
                root.lastError = root.elideStatus(root._error || "Could not stop that process");
            else
                root.lastError = "";
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
}

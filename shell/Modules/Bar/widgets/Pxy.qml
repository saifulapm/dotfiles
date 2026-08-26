import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "PxyModel.js" as Model

// pxy — the local LLM proxy's control surface. The panel pins the auto route
// to one model (chain stays as fallback), shows the live walk order with
// per-candidate verdicts, active cooldowns, and every provider's limits.
//
// All data comes from one bin/pxy-panel-scan run (which shells out to the
// pxy CLI); pinning runs `pxy route`, so the CLI and this panel can never
// disagree about what the route is. This shell does not poll: a quick scan at
// startup decides bar visibility, a full one (remote balances included) runs
// when the panel opens or refresh is pressed.
BarIcon {
    id: rootItem

    glyph: "󰓡" // md-swap_horizontal — the route switcher

    // ---------------------------------------------------------------- state
    property bool scanned: false
    property bool refreshing: false
    property bool daemonActive: false
    property int modelCount: 0
    property string routePin: ""
    property bool routePinActive: false
    property var chain: []
    property var cooldowns: []
    property var limits: []
    property var models: []
    property string statusText: ""

    // A route/restart action in flight; rows stay clickable but the panel
    // shows the spinner through `refreshing`.
    property bool acting: false

    readonly property bool alarming: scanned && !daemonActive

    visible: scanned
    active: alarming
    tooltipText: {
        if (!daemonActive)
            return "pxy · daemon down";
        if (routePin !== "" && routePinActive)
            return "pxy · pinned " + Model.modelName(routePin);
        return "pxy · auto (chain priority)";
    }

    // -------------------------------------------------------------- actions
    function refresh(full) {
        if (scanProc.running)
            return;
        refreshing = true;
        scanProc.command = [Quickshell.env("HOME") + "/.dotfiles/bin/pxy-panel-scan"].concat(full ? [] : ["--no-remote"]);
        scanProc.running = true;
    }

    // `pxy route <id>` / `pxy route --clear`, then a quick re-scan: only the
    // route and the walk order changed, the balances didn't.
    function pin(modelId) {
        runAction(["route", modelId]);
    }

    function clearPin() {
        runAction(["route", "--clear"]);
    }

    function restartDaemon() {
        runAction(["__restart"]);
    }

    function runAction(args) {
        if (actionProc.running)
            return;
        acting = true;
        refreshing = true;
        if (args[0] === "__restart")
            actionProc.command = ["systemctl", "--user", "restart", "pxy"];
        else
            actionProc.command = [Quickshell.env("HOME") + "/.local/bin/pxy"].concat(args);
        actionProc.running = true;
    }

    function parseScan(output) {
        refreshing = scanProc.running;
        const raw = String(output || "").trim();
        if (raw === "")
            return;
        try {
            const data = JSON.parse(raw.split("\n").pop());
            // ready === false means no pxy binary on this machine — leave
            // `scanned` false so the widget never appears here at all.
            if (data.ready === false)
                return;
            daemonActive = !!(data.daemon && data.daemon.active);
            modelCount = data.daemon ? Number(data.daemon.modelCount || 0) : 0;
            routePin = String(data.routePin || "");
            routePinActive = data.routePinActive === true;
            chain = data.chain || [];
            cooldowns = data.cooldowns || [];
            // A quick scan (--no-remote) carries local caps only; keep the
            // remote-balance rows the last full scan brought rather than
            // silently replacing them with the poorer list.
            if (data.remoteIncluded === true || limits.length === 0)
                limits = data.limits || [];
            models = data.models || [];
            statusText = String(data.statusText || "");
            scanned = true;
        } catch (e) {
            console.warn("pxy-panel", "Failed to parse scan output:", e);
        }
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: rootItem.parseScan(text)
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text || "").trim() !== "")
                console.warn("pxy-panel", String(text).trim())
        }
        onExited: rootItem.refreshing = rootItem.refreshing && running
    }

    Process {
        id: actionProc
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text || "").trim() !== "")
                console.warn("pxy-panel", String(text).trim())
        }
        onExited: {
            rootItem.acting = false;
            // A daemon restart needs a beat before healthz answers.
            actionSettle.restart();
        }
    }

    Timer {
        id: actionSettle
        interval: 800
        onTriggered: rootItem.refresh(false)
    }

    // Quick scan at startup so the bar knows whether pxy exists here at all;
    // remote balances wait for the panel to be opened.
    Component.onCompleted: refresh(false)

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("PxyPanel.qml", {
                theme: rootItem.theme,
                pxy: rootItem
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
        if (panelLoader.item.opened)
            refresh(true);
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            refresh(true);
        else
            openPanel();
    }

    PanelLoader {
        id: panelLoader
    }
}

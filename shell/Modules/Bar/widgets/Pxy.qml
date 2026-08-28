import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "PxyModel.js" as Model

// pxy — the local LLM proxy's control surface. Routing is by GROUP: config.toml
// declares named failover chains (free, subscription, payperuse…), an agent is
// launched with a group name as its model, and the group walks its list until
// one candidate serves. The panel shows any group's live walk order with
// per-candidate verdicts, active cooldowns, and every provider's limits, and
// pins one model ahead of whichever chain a request asks for.
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
    // [{name, size}] and name -> walk order; every group is scanned at once, so
    // switching chips is instant and can't show a stale chain.
    property var groups: []
    property var chains: ({})
    property var cooldowns: []
    property var limits: []
    property var models: []
    property string statusText: ""

    readonly property string firstGroup: groups.length > 0 ? String(groups[0].name) : ""

    function chainOf(group) {
        return (chains && chains[group]) || [];
    }

    // A route/restart action in flight; rows stay clickable but the panel
    // shows the spinner through `refreshing`.
    property bool acting: false
    // Specifically the daemon restart, so its button spins on its own rather
    // than every action lighting up every button.
    property bool restarting: false

    readonly property bool alarming: scanned && !daemonActive

    visible: scanned
    active: alarming
    tooltipText: {
        if (!daemonActive)
            return "pxy · daemon down";
        if (routePin !== "" && routePinActive)
            return "pxy · pinned " + Model.modelName(routePin);
        return "pxy · " + groups.length + " group(s), chain priority";
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
        restarting = args[0] === "__restart";
        if (restarting)
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
            groups = data.groups || [];
            chains = data.chains || {};
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
        // Cleared here rather than in parseScan: this fires even when the scan
        // produced nothing parseable, and a spinner that outlives its work is
        // worse than no spinner at all.
        onExited: {
            rootItem.refreshing = rootItem.refreshing && running;
            rootItem.restarting = false;
        }
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
            // `restarting` stays true through the settle timer and the rescan
            // it triggers: systemctl returns before the daemon answers healthz,
            // and a button that stopped spinning there would say "done" while
            // the panel still reads DAEMON DOWN.
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

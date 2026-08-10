import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "BluetoothModel.js" as Model

// AirPods — only exists while the pods are connected. Left click opens the
// panel (battery, ear state, noise picker), right click flips ANC and
// Transparency without opening anything, the tooltip carries the per-pod
// battery the way the bluetooth widget's does.
//
// All state and control ride the librepods daemon's stream via
// LibrePodsService; this widget never touches AAP or BlueZ itself.
BarIcon {
    id: rootItem

    required property var service

    // The hold rides out a librepods restart (its stream drops and the
    // service reports disconnected for the seconds the daemon takes to come
    // back) — same shape as the bluetooth widget's adapter hold. A genuine
    // disconnect outlives it and the widget leaves.
    visible: service.connected || connectedHold.running
    onVisibleChanged: if (!visible && panelLoader.item)
        panelLoader.item.close()

    property bool wasConnected: false
    readonly property bool nowConnected: service.connected
    onNowConnectedChanged: {
        if (!nowConnected && wasConnected)
            connectedHold.restart();
        else if (nowConnected)
            connectedHold.stop();
        wasConnected = nowConnected;
    }

    Timer {
        id: connectedHold
        interval: 4000
    }

    glyph: "󱡏" // md-earbuds
    dimmed: !service.connected
    tooltipText: {
        const battery = Model.batteryText(rootItem.service.battery);
        const mode = rootItem.service.noiseName;
        return battery === "" ? mode : battery + "\n" + mode;
    }

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("AirPodsPanel.qml", {
                theme: rootItem.theme,
                service: rootItem.service
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.LeftButton) {
            openPanel();
        } else {
            // ANC <-> Transparency, the pair the stems' press-and-hold walks.
            rootItem.service.setNoise(rootItem.service.noise === 1 ? 2 : 1);
        }
    }

    function summonPanel(mode) {
        if (mode === "close") {
            if (panelLoader.item)
                panelLoader.item.close();
            return;
        }
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("AirPodsPanel.qml", {
                theme: rootItem.theme,
                service: rootItem.service
            });
        panelLoader.item.anchorItem = rootItem;
        if (mode === "open")
            panelLoader.item.open();
        else
            panelLoader.item.toggle();
    }

    // Read by the bar to rank surfaces for the IPC verbs, as bluetooth's is.
    readonly property bool panelOpen: panelLoader.item ? panelLoader.item.opened === true : false

    function summonRouted(mode) {
        if (!rootItem.bar || !rootItem.bar.summonWidgetMode("airpods", mode))
            rootItem.summonPanel(mode);
        return "ok";
    }

    // `qs ipc call airpods -- toggle` for a keybind; noise verbs so a bind
    // can switch modes without opening anything (anc|transparency|adaptive|
    // off). Pinned to the first screen the way bluetooth's target is.
    IpcHandler {
        target: "airpods"
        enabled: rootItem.bar !== null && Quickshell.screens.length > 0 && rootItem.bar.screen === Quickshell.screens[0]

        function open(): string {
            return rootItem.summonRouted("open");
        }

        function close(): string {
            return rootItem.summonRouted("close");
        }

        function toggle(): string {
            return rootItem.summonRouted("toggle");
        }

        function noise(mode: string): string {
            const index = ["off", "anc", "transparency", "adaptive"].indexOf(mode);
            if (index < 0)
                return "unknown mode: " + mode;
            rootItem.service.setNoise(index);
            return rootItem.service.noiseNames[index];
        }
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../components"

// Bluetooth, omarchy glyphs. Left click opens the panel, right click toggles
// the adapter, middle click opens bluetoothctl in a float.
BarIcon {
    id: rootItem

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connectedDevices: Bluetooth.devices.values.filter(d => d.connected)

    glyph: {
        if (!rootItem.adapter || !rootItem.adapter.enabled)
            return "󰂲"; // bluetooth-off
        if (rootItem.connectedDevices.length > 0)
            return "󰂱"; // bluetooth-connect
        return "󰂯";     // bluetooth
    }

    visible: adapter !== null
    dimmed: !adapter || !adapter.enabled
    tooltipText: {
        if (!adapter || !adapter.enabled)
            return "Bluetooth off";
        if (connectedDevices.length === 0)
            return "No devices connected";
        return connectedDevices.map(d => d.name + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "")).join("\n");
    }

    function toggleBluetooth() {
        if (rootItem.adapter)
            rootItem.adapter.enabled = !rootItem.adapter.enabled;
    }

    function summonPanel(mode) {
        if (mode === "close") {
            if (panelLoader.active && panelLoader.item)
                panelLoader.item.close();
            return;
        }
        panelLoader.active = true;
        panelLoader.item.anchorItem = rootItem;
        if (mode === "open")
            panelLoader.item.open();
        else
            panelLoader.item.toggle();
    }

    function openPanel() {
        summonPanel("toggle");
    }

    onTapped: button => {
        if (button === Qt.RightButton) {
            rootItem.toggleBluetooth();
        } else if (button === Qt.MiddleButton) {
            Quickshell.execDetached(["foot", "--app-id=qshell-float", "-e", "bluetoothctl"]);
        } else {
            openPanel();
        }
    }

    // omarchy's IPC surface (their omarchy.bluetooth target): summon verbs
    // plus toggleBluetooth so a keybind can flip the adapter without opening
    // anything. `bar open bluetooth` remains the layout-aware summon path;
    // this target is the direct one. The bar mounts one widget per screen and
    // quickshell permits one handler per target, so only the first screen's
    // copy registers it. NOTE: `qs ipc call bluetooth show` needs `--` before
    // the verb — the CLI parses a bare `show` as its own subcommand.
    IpcHandler {
        target: "bluetooth"
        enabled: rootItem.bar !== null && Quickshell.screens.length > 0 && rootItem.bar.screen === Quickshell.screens[0]

        function open(): string {
            rootItem.summonPanel("open");
            return "ok";
        }

        function close(): string {
            rootItem.summonPanel("close");
            return "ok";
        }

        function show(): string {
            rootItem.summonPanel("open");
            return "ok";
        }

        function hide(): string {
            rootItem.summonPanel("close");
            return "ok";
        }

        function toggle(): string {
            rootItem.summonPanel("toggle");
            return "ok";
        }

        function toggleBluetooth(): string {
            rootItem.toggleBluetooth();
            return rootItem.adapter ? (rootItem.adapter.enabled ? "on" : "off") : "no adapter";
        }
    }

    LazyLoader {
        id: panelLoader
        active: false
        component: BluetoothPanel {
            theme: rootItem.theme
        }
    }
}

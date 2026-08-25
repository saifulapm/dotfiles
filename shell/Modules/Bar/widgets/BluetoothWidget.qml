import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../components"
import "BluetoothModel.js" as Model

// Bluetooth, omarchy glyphs. Left click opens the panel, right click toggles
// the adapter, middle click opens bluetoothctl in a float.
BarIcon {
    id: rootItem

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connectedDevices: Bluetooth.devices ? Bluetooth.devices.values.filter(d => d.connected) : []

    // The shared Apple-accessory battery reader, injected by the bar's registry
    // — one instance however many screens carry this widget (S2). Nullable
    // rather than required: the widget must still render on a machine where the
    // service was never created.
    property BtBatteryService btbattery: null

    // BlueZ's own figure where a device publishes one, AAP where it does not
    // (AirPods only ever appear in the second half — see BtBatteryService).
    function batteryTextFor(device) {
        if (!device)
            return "";
        const readings = rootItem.btbattery ? rootItem.btbattery.batteryFor(device.address) : null;
        const aapText = Model.batteryText(readings);
        if (aapText !== "")
            return aapText;
        return device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "";
    }

    glyph: {
        if (!rootItem.adapter || !rootItem.adapter.enabled)
            return "󰂲"; // bluetooth-off
        if (rootItem.connectedDevices.length > 0)
            return "󰂱"; // bluetooth-connect
        return "󰂯";     // bluetooth
    }

    // The hold keeps the widget mounted across a bluetoothd restart
    // (Restart=on-failure brings it back inside a second); only an adapter
    // that stays gone past the grace actually hides it.
    visible: adapter !== null || adapterHold.running
    dimmed: !adapter || !adapter.enabled
    onAdapterChanged: adapter === null ? adapterHold.restart() : adapterHold.stop()

    Timer {
        id: adapterHold
        interval: 4000
    }
    tooltipText: {
        if (!adapter || !adapter.enabled)
            return "Bluetooth off";
        if (connectedDevices.length === 0)
            return "No devices connected";
        return connectedDevices.map(d => {
            const battery = rootItem.batteryTextFor(d);
            return d.name + (battery === "" ? "" : " · " + battery);
        }).join("\n");
    }

    function toggleBluetooth() {
        if (rootItem.adapter)
            rootItem.adapter.enabled = !rootItem.adapter.enabled;
    }

    function summonPanel(mode) {
        if (mode === "close") {
            if (panelLoader.item)
                panelLoader.item.close();
            return;
        }
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("BluetoothPanel.qml", {
                theme: rootItem.theme,
                btbattery: rootItem.btbattery
            });
        panelLoader.item.anchorItem = rootItem;
        if (mode === "open")
            panelLoader.item.open();
        else
            panelLoader.item.toggle();
    }

    function openPanel() {
        summonPanel("toggle");
    }

    // Read by the bar to rank surfaces for the IPC verbs below: the copy with
    // the panel already open answers before the focused output's copy.
    readonly property bool panelOpen: panelLoader.item ? panelLoader.item.opened === true : false

    // The IPC verbs' shared body — kept on the widget, not inside IpcHandler,
    // where every declared function becomes a callable verb. Falls back to
    // this copy when no surface answers (widget hidden on every bar, so no
    // slot passes summonWidgetModeHere's visibility rule).
    function summonRouted(mode) {
        if (!rootItem.bar || !rootItem.bar.summonWidgetMode("bluetooth", mode))
            rootItem.summonPanel(mode);
        return "ok";
    }

    onTapped: button => {
        if (button === Qt.RightButton) {
            rootItem.toggleBluetooth();
        } else if (button === Qt.MiddleButton) {
            Quickshell.execDetached(["foot-run", "--app-id=qshell-float", "-e", "bluetoothctl"]);
        } else {
            openPanel();
        }
    }

    // omarchy's IPC surface (their omarchy.bluetooth target): summon verbs
    // plus toggleBluetooth so a keybind can flip the adapter without opening
    // anything. `bar open bluetooth` remains the layout-aware summon path;
    // this target is the direct one. The bar mounts one widget per screen and
    // quickshell permits one handler per target, so registration is pinned to
    // the first screen — but the verbs must NOT act on that copy, or a summon
    // opens on screens[0] while the user is on another monitor (omarchy
    // 667d2d2). They route through the bar, which ranks surfaces by open
    // panel then niri focus. NOTE: `qs ipc call bluetooth show` needs `--`
    // before the verb — the CLI parses a bare `show` as its own subcommand.
    IpcHandler {
        target: "bluetooth"
        enabled: rootItem.bar !== null && Quickshell.screens.length > 0 && rootItem.bar.screen === Quickshell.screens[0]

        function open(): string {
            return rootItem.summonRouted("open");
        }

        function close(): string {
            return rootItem.summonRouted("close");
        }

        function show(): string {
            return rootItem.summonRouted("open");
        }

        function hide(): string {
            return rootItem.summonRouted("close");
        }

        function toggle(): string {
            return rootItem.summonRouted("toggle");
        }

        function toggleBluetooth(): string {
            rootItem.toggleBluetooth();
            return rootItem.adapter ? (rootItem.adapter.enabled ? "on" : "off") : "no adapter";
        }
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    PanelLoader {
        id: panelLoader
    }
}

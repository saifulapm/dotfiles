import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../components"

// Bluetooth, omarchy glyphs. Left click opens bluetoothctl, right click
// toggles the adapter.
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

    onTapped: button => {
        if (button === Qt.RightButton && rootItem.adapter)
            rootItem.adapter.enabled = !rootItem.adapter.enabled;
        else
            Quickshell.execDetached(["foot", "--app-id=qshell-float", "-e", "bluetoothctl"]);
    }
}

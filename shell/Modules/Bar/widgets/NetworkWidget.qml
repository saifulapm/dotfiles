import QtQuick
import Quickshell
import Quickshell.Networking
import "../components"

// Wifi/wired status with omarchy's wifi-strength ladder. Left click opens
// nmtui in a floating terminal, right click toggles wifi.
BarIcon {
    id: rootItem

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired) || null
    readonly property var wifiNetwork: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) || null) : null
    readonly property bool wiredUp: wiredDevice !== null && wiredDevice.connected
    readonly property bool online: wiredUp || wifiNetwork !== null

    glyph: {
        if (wiredUp)
            return "󰈀"; // ethernet
        if (!wifiDevice || !Networking.wifiEnabled || !wifiNetwork)
            return "󰤮"; // wifi-off
        const s = wifiNetwork.signalStrength;
        if (s >= 80)
            return "󰤨"; // wifi-strength-4
        if (s >= 60)
            return "󰤥";
        if (s >= 40)
            return "󰤢";
        return "󰤟";     // wifi-strength-1
    }

    visible: wifiDevice !== null || wiredDevice !== null
    dimmed: !online
    tooltipText: {
        if (wiredUp)
            return "Wired · " + wiredDevice.name;
        if (!Networking.wifiEnabled)
            return "Wifi off";
        if (wifiNetwork)
            return wifiNetwork.name + " · " + Math.round(wifiNetwork.signalStrength) + "%";
        return "Not connected";
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            Networking.wifiEnabled = !Networking.wifiEnabled;
        else
            Quickshell.execDetached(["foot", "--app-id=qshell-float", "-e", "nmtui"]);
    }
}

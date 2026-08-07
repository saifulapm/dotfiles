import QtQuick
import Quickshell
import Quickshell.Networking
import "../components"
import "NetworkModel.js" as Model

// Wifi/wired status with omarchy's wifi-strength ladder. Left click opens the
// network panel, right click toggles the radio, middle click drops into nmtui.
BarIcon {
    id: rootItem

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired) || null
    readonly property var wifiNetwork: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) || null) : null
    readonly property bool wiredUp: wiredDevice !== null && wiredDevice.connected
    readonly property bool online: wiredUp || wifiNetwork !== null
    // quickshell reports signalStrength as 0..1; everything here is percent.
    readonly property int signalPercent: Model.signalPercent(wifiNetwork)

    glyph: {
        if (wiredUp)
            return "󰈀"; // ethernet
        if (!wifiDevice || !Networking.wifiEnabled || !wifiNetwork)
            return "󰤮"; // wifi-off
        return Model.wifiIconFor(rootItem.signalPercent);
    }

    visible: wifiDevice !== null || wiredDevice !== null
    dimmed: !online
    tooltipText: {
        if (wiredUp)
            return "Wired · " + wiredDevice.name;
        if (!Networking.wifiEnabled)
            return "Wifi off";
        if (wifiNetwork)
            return wifiNetwork.name + " · " + rootItem.signalPercent + "%";
        return "Not connected";
    }

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("NetworkPanel.qml", {
                theme: rootItem.theme
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton) {
            Networking.wifiEnabled = !Networking.wifiEnabled;
        } else if (button === Qt.MiddleButton) {
            Quickshell.execDetached(["foot-run", "--app-id=qshell-float", "-e", "nmtui"]);
        } else {
            openPanel();
        }
    }

    // Source-based so the panel's tree compiles on first open, not with the
    // bar (S1). Invisible: BarButton's default property is a Row, and a Row
    // skips invisible items — the loaded BarPanel is its own window anyway.
    Loader {
        id: panelLoader
        visible: false
    }
}

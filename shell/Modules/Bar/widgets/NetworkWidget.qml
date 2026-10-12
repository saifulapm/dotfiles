import QtQuick
import Quickshell
import Quickshell.Io
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
    // NetworkManager can leave the active profile out of the device's
    // AvailableConnections, and Quickshell only builds known networks from
    // that list. An OWE transition-mode network does this between scans: the
    // in-use access point carries the hidden "_owetm_" SSID, so the profile
    // for the open SSID looks out of range even while it is connected. Trust
    // the device's own state then instead of flickering to disconnected
    // (omarchy 18328559).
    readonly property bool wifiUp: wifiNetwork !== null || (wifiDevice !== null && wifiDevice.connected)
    readonly property bool online: wiredUp || wifiUp
    // quickshell reports signalStrength as 0..1; everything here is percent.
    // The panel reads this too (through anchorItem), so the nmcli fallback
    // below lives once, here, where it runs whether or not the panel is open.
    readonly property int signalPercent: Model.connectedSignalStrength(wifiNetwork ? wifiNetwork.signalStrength : 0, activeApSignal)
    // Filled by activeApSignalPoll from nmcli while the connected network has
    // no strength of its own to report.
    property int activeApSignal: -1
    readonly property bool onWifi: !wiredUp && wifiUp
    readonly property bool needsActiveApSignal: onWifi && !(wifiNetwork && wifiNetwork.signalStrength > 0)
    // Bumped whenever the cached reading stops describing the current link, so
    // an nmcli read still in flight from before cannot write a stale strength.
    property int activeApSignalGeneration: 0
    property int activeApSignalRequest: -1
    onOnWifiChanged: if (!onWifi)
        resetActiveApSignal()
    onWifiDeviceChanged: resetActiveApSignal()

    // Switching Wi-Fi networks always passes through a non-Wi-Fi state (both
    // the device and the old network drop out of the connected state while the
    // new profile activates), so this also covers a change of network.
    function resetActiveApSignal() {
        activeApSignal = -1;
        activeApSignalGeneration++;
    }

    function pollActiveApSignal() {
        if (activeApSignalProc.running)
            return;
        activeApSignalRequest = activeApSignalGeneration;
        activeApSignalProc.running = true;
    }

    function finishActiveApSignal(raw) {
        if (activeApSignalRequest !== activeApSignalGeneration) {
            // The link changed mid-read and the restarted poll skipped while
            // this one was running; read again now instead of a full interval
            // later.
            if (needsActiveApSignal)
                activeApSignalPoll.restart();
            return;
        }
        activeApSignal = Model.parseActiveApSignal(raw);
    }

    glyph: {
        if (wiredUp)
            return "󰈀"; // ethernet
        if (!wifiDevice || !Networking.wifiEnabled || !wifiUp)
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
        if (wifiUp)
            return (wifiNetwork ? wifiNetwork.name : "Wi-Fi") + " · " + rootItem.signalPercent + "%";
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

    // Reads the in-use access point's strength without triggering a scan, for
    // the connected network that has none of its own (see signalPercent).
    Process {
        id: activeApSignalProc
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list", "ifname", rootItem.wifiDevice ? rootItem.wifiDevice.name : "", "--rescan", "no"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: rootItem.finishActiveApSignal(text)
        }
    }

    Timer {
        id: activeApSignalPoll
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: rootItem.needsActiveApSignal
        onTriggered: rootItem.pollActiveApSignal()
    }

    // Source-based so the panel's tree compiles on first open, not with the
    // bar (S1). Invisible: BarButton's default property is a Row, and a Row
    // skips invisible items — the loaded BarPanel is its own window anyway.
    PanelLoader {
        id: panelLoader
    }
}

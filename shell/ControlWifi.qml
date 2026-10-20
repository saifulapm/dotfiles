import Quickshell.Networking
import QtQuick
import "lib/control-net.mjs" as Lib
import "lib/voice.mjs" as V

// Control's Wi-Fi section: every Wi-Fi device's networks, from NetworkManager's own change events.
Item {
    id: section

    required property var theme
    property int selected: 0
    readonly property var look: V.listLook(theme.tokens)

    readonly property var wifi: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    readonly property var all: wifi.reduce((nets, d) => nets.concat(d.networks.values), [])
    readonly property var networks: Lib.wifiOrder(all.map(n => ({
                    name: n.name,
                    connected: n.connected,
                    known: n.known,
                    signalStrength: n.signalStrength
                }))).map(i => all[i])
    readonly property var rows: networks.map(n => Lib.wifiRow(n))

    // Quickshell lists a network that is not saved only while its device scans, so the section scans while it is drawn and never while idle.
    function scan() {
        wifi.forEach(d => d.scannerEnabled = visible);
    }
    onVisibleChanged: scan()
    onWifiChanged: scan()

    // The item a key last acted on: the reorder its connect causes keeps the selection on it, and moving away lets it go.
    property var picked: null
    onSelectedChanged: {
        if (networks.indexOf(picked) !== selected)
            picked = null;
    }
    onRowsChanged: {
        const i = networks.indexOf(picked);
        selected = i >= 0 ? i : Math.max(0, Math.min(selected, rows.length - 1));
    }

    function key(event) {
        const network = networks[selected];
        if (!network)
            return false;
        picked = network;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (network.connected)
                network.disconnect();
            else
                network.connect();
        } else if (event.key === Qt.Key_D)
            network.forget();
        else
            return false;
        return true;
    }

    function state() {
        return {
            details: rows.map(r => r.detail)
        };
    }

    implicitHeight: line.implicitHeight

    Text {
        id: line
        textFormat: Text.PlainText
        leftPadding: 20
        text: section.look.tabText(section.wifi.length ? "↵ connect · d forget" : "No Wi-Fi")
        color: section.look.small.color
        font.family: section.look.small.font
        font.pixelSize: section.look.small.size
        font.letterSpacing: section.look.small.spacing
    }
}

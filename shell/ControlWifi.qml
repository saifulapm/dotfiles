import Quickshell.Networking
import QtQuick
import "lib/control-net.mjs" as Lib

// Control's Wi-Fi section: every Wi-Fi device's networks, from NetworkManager's own change events.
Item {
    id: section

    required property var theme
    property int selected: 0

    readonly property var wifi: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    readonly property var all: wifi.reduce((nets, d) => nets.concat(d.networks.values), [])
    readonly property var networks: Lib.wifiOrder(all.map(n => ({
                    name: n.name,
                    connected: n.connected,
                    known: n.known,
                    signalStrength: n.signalStrength
                }))).map(i => all[i])
    readonly property var rows: networks.map(n => Lib.wifiRow(n))

    // The item under the selection: a reorder (a connect moves it to the top) keeps the selection on it, and a forget leaves it on a row that exists.
    property var picked: null
    onSelectedChanged: picked = networks[selected] ?? null
    onRowsChanged: {
        const i = networks.indexOf(picked);
        selected = i >= 0 ? i : Math.max(0, Math.min(selected, rows.length - 1));
        picked = networks[selected] ?? null;
    }

    function key(event) {
        const network = networks[selected];
        if (!network)
            return false;
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
        text: section.wifi.length ? "↵ CONNECT · D FORGET" : "NO WI-FI"
        color: section.theme.color.muted
        font.family: section.theme.tokens ? section.theme.tokens.type.ui : ""
        font.pixelSize: 10
        font.letterSpacing: 1.2
    }
}

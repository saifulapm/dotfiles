import Quickshell.Bluetooth
import QtQuick
import "lib/control-net.mjs" as Lib

// Control's Bluetooth section: the default adapter's devices, from BlueZ's own change events.
Item {
    id: section

    required property var theme
    property int selected: 0

    readonly property var all: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices.values : []
    readonly property var devices: Lib.btOrder(all.map(d => ({
                    name: d.name,
                    connected: d.connected,
                    paired: d.paired
                }))).map(i => all[i])
    readonly property var rows: devices.map(d => Lib.btRow(d))

    // The item under the selection: a reorder (a connect moves it to the top) keeps the selection on it, and a forget leaves it on a row that exists.
    property var picked: null
    onSelectedChanged: picked = devices[selected] ?? null
    onRowsChanged: {
        const i = devices.indexOf(picked);
        selected = i >= 0 ? i : Math.max(0, Math.min(selected, rows.length - 1));
        picked = devices[selected] ?? null;
    }

    function key(event) {
        const device = devices[selected];
        if (!device)
            return false;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (device.connected)
                device.disconnect();
            else
                device.connect();
        } else if (event.key === Qt.Key_P)
            device.pair();
        else if (event.key === Qt.Key_D)
            device.forget();
        else
            return false;
        return true;
    }

    function state() {
        return {
            details: rows.map(r => r.detail)
        };
    }

    implicitHeight: hint.implicitHeight

    Text {
        id: hint
        textFormat: Text.PlainText
        leftPadding: 20
        text: Bluetooth.defaultAdapter ? "↵ CONNECT · P PAIR · D FORGET" : "NO BLUETOOTH"
        color: section.theme.color.muted
        font.family: section.theme.tokens ? section.theme.tokens.type.ui : ""
        font.pixelSize: 10
        font.letterSpacing: 1.2
    }
}

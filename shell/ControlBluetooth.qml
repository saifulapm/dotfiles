import Quickshell.Bluetooth
import QtQuick
import "lib/control-net.mjs" as Lib
import "lib/voice.mjs" as V

// Control's Bluetooth section: the default adapter's devices, from BlueZ's own change events.
Item {
    id: section

    required property var theme
    property int selected: 0
    readonly property var look: V.listLook(theme.tokens)

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    // An adapter that is off lists nothing, though BlueZ still holds its devices.
    readonly property var all: on ? adapter.devices.values : []
    readonly property var devices: Lib.btOrder(all.map(d => ({
                    name: d.name,
                    connected: d.connected,
                    paired: d.paired
                }))).map(i => all[i])
    readonly property var rows: devices.map(d => Lib.btRow(d))

    // The item a key last acted on: the reorder its connect causes keeps the selection on it, and moving away lets it go.
    property var picked: null
    onSelectedChanged: {
        if (devices.indexOf(picked) !== selected)
            picked = null;
    }
    onRowsChanged: {
        const i = devices.indexOf(picked);
        selected = i >= 0 ? i : Math.max(0, Math.min(selected, rows.length - 1));
    }

    function key(event) {
        if (event.key === Qt.Key_O && adapter) {
            adapter.enabled = !adapter.enabled;
            return true;
        }
        // Off, s, t and Enter do nothing, and are still taken so they act on nothing else.
        if (!on)
            return [Qt.Key_Return, Qt.Key_Enter, Qt.Key_S, Qt.Key_T].indexOf(event.key) >= 0;
        const device = devices[selected];
        if (!device)
            return false;
        picked = device;
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
            details: rows.map(r => r.detail),
            hint: hint.text,
            powered: on
        };
    }

    implicitHeight: hint.implicitHeight

    Text {
        id: hint
        textFormat: Text.PlainText
        leftPadding: 20
        text: section.look.tabText(Lib.btHint({
            adapter: !!section.adapter,
            enabled: section.on
        }))
        color: section.look.small.color
        font.family: section.look.small.font
        font.pixelSize: section.look.small.size
        font.letterSpacing: section.look.small.spacing
    }
}

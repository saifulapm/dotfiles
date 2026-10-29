import Quickshell.Bluetooth
import QtQuick
import "." as Root
import "lib/control-net.mjs" as Lib
import "lib/voice.mjs" as V

// Control's Bluetooth section: the default adapter's devices, from BlueZ's own change events.
Item {
    id: section

    required property var theme
    property int selected: 0
    readonly property var look: V.listLook(theme.tokens)
    // A pairing request in the island takes every key while this tab shows, since Control holds the keyboard.
    readonly property bool typing: Root.Pairing.question !== null
    readonly property var typingKeys: Root.Pairing.question?.keys ?? []

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    // An adapter that is off lists nothing, though BlueZ still holds its devices.
    readonly property var all: on ? adapter.devices.values : []
    readonly property bool discovering: on && adapter.discovering
    // A device that sent no name has only BlueZ's alias of its address, so it reads as nameless.
    readonly property var plain: all.map(d => ({
                name: d.deviceName ? d.name : "",
                address: d.address,
                connected: d.connected,
                paired: d.paired,
                trusted: d.trusted,
                battery: d.battery,
                batteryAvailable: d.batteryAvailable
            }))
    readonly property var order: Lib.btOrder(plain, discovering)
    readonly property var devices: order.map(i => all[i])
    readonly property var rows: order.map(i => Lib.btRow(plain[i]))

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
        if (typing)
            return Root.Pairing.key(event);
        if (event.key === Qt.Key_O && adapter) {
            adapter.enabled = !adapter.enabled;
            return true;
        }
        // Off, s, t and Enter do nothing, and are still taken so they act on nothing else.
        if (!on)
            return [Qt.Key_Return, Qt.Key_Enter, Qt.Key_S, Qt.Key_T].indexOf(event.key) >= 0;
        if (event.key === Qt.Key_S) {
            adapter.discovering = !adapter.discovering;
            return true;
        }
        const device = devices[selected];
        if (!device)
            return false;
        picked = device;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (device.connected)
                device.disconnect();
            else if (!device.paired)
                Root.Pairing.pairTrustConnect(device);
            else
                device.connect();
        } else if (event.key === Qt.Key_T)
            device.trusted = !device.trusted;
        else if (event.key === Qt.Key_P)
            device.pair();
        else if (event.key === Qt.Key_D)
            device.forget();
        else
            return false;
        return true;
    }

    // Control closing ends a scan it may have started.
    function stopScan() {
        if (discovering)
            adapter.discovering = false;
    }

    function state() {
        return {
            details: rows.map(r => r.detail),
            hint: hint.text,
            powered: on,
            discovering: discovering
        };
    }

    implicitHeight: hint.implicitHeight

    Text {
        id: hint
        textFormat: Text.PlainText
        leftPadding: 20
        text: section.look.tabText(Lib.btHint({
            adapter: !!section.adapter,
            enabled: section.on,
            discovering: section.discovering
        }))
        color: section.look.small.color
        font.family: section.look.small.font
        font.pixelSize: section.look.small.size
        font.letterSpacing: section.look.small.spacing
    }
}

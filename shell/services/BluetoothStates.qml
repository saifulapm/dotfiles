import Quickshell
import Quickshell.Bluetooth
import QtQuick
import ".." as Root
import "../lib/bluetooth.mjs" as B

// The island's Bluetooth states, from BlueZ's own change events: a paired device connecting shows its name and battery for 2 s.
Scope {
    id: bt

    // While on, the connect state never shows (FP8P8H89).
    property bool dnd: false
    readonly property var all: Bluetooth.defaultAdapter?.devices.values ?? []
    // Each device's address, connected and paired, so a change to any of them runs check().
    readonly property string states: all.map(d => d.address + (d.connected ? " on" : " off") + (d.paired ? " paired" : "")).join(",")
    // Each device's connected as last seen, by address.
    property var seen: ({})
    // The device whose connect state shows, null while none does.
    property var device: null
    readonly property var current: device ? {
        name: device.deviceName ? device.name : "",
        address: device.address,
        battery: device.batteryAvailable ? device.battery : null
    } : null

    function check() {
        const r = B.newlyConnected(seen, all.map(d => ({
                        address: d.address,
                        connected: d.connected,
                        paired: d.paired
                    })));
        seen = r.seen;
        const d = all.find(x => r.connected.includes(x.address));
        if (d && !dnd) {
            device = d;
            hold.restart();
        }
    }

    onStatesChanged: check()

    // BlueZ reports a battery once the device's HFP link is up, a moment after the connect, so its arrival starts the 2 s again.
    Connections {
        target: bt.device
        function onBatteryAvailableChanged() {
            if (bt.device.batteryAvailable)
                hold.restart();
        }
    }

    Root.Tick {
        id: hold
        interval: 2000
        onTriggered: bt.device = null
    }
}

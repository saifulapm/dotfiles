import Quickshell
import Quickshell.Networking
import QtQuick
import "../lib/margins.mjs" as M

// With no NetworkManager the device list stays empty, so the wifi word is absent.
Scope {
    readonly property string wifi: M.wifiText(Networking.devices.values.map(d => ({ wifi: d.type === DeviceType.Wifi, connected: d.connected })))
}

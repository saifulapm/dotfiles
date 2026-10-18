import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "../lib/margins.mjs" as M

// UPower's display device sends PropertiesChanged, so the battery word follows it without polling.
Scope {
    readonly property var device: UPower.displayDevice
    readonly property string battery: device.ready && device.isLaptopBattery && device.isPresent ? M.batteryText(device.percentage, device.state === UPowerDeviceState.Charging) : ""
}

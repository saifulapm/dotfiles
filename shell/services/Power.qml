import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "../lib/margins.mjs" as M
import "../lib/battery.mjs" as B

// UPower's display device sends PropertiesChanged, so the battery word follows it without polling.
Scope {
    id: power

    readonly property var device: UPower.displayDevice
    readonly property bool laptop: device.ready && device.isLaptopBattery && device.isPresent
    readonly property string battery: laptop ? M.batteryText(device.percentage, device.state === UPowerDeviceState.Charging) : ""
    // Asahi does not suspend, so this notice is all that stands between a low battery and a dead machine.
    property bool armed: true

    function check() {
        if (!laptop)
            return;
        const r = B.lowBattery(armed, device.percentage, device.state === UPowerDeviceState.Discharging);
        armed = r.armed;
        if (r.warn)
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Battery", "Battery low", Math.round(device.percentage * 100) + "% left"]);
    }

    Connections {
        target: power.device
        function onPercentageChanged() {
            power.check();
        }
        function onStateChanged() {
            power.check();
        }
    }
    onLaptopChanged: check()
}

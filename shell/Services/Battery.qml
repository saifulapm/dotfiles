import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Low-battery warning + AC/battery power-profile switching — port of
// omarchy's services/battery plugin (Service.qml + BatteryModel.js, MIT, see
// CREDITS.md). Their 30-second check timer is not ported: the UPower display
// device pushes percentage/state changes on its own, so the warning logic
// re-evaluates from property bindings instead — the event-driven shape the
// no-polling rule asks for, with identical observable behaviour.
//
// Their per-source saved-profile files are not ported either: upstream only
// writes them from an omarchy CLI we do not ship, so this is their behaviour
// on a machine where nothing was ever saved — AC gets performance when the
// daemon offers it (balanced otherwise), battery gets balanced.
QtObject {
    id: root

    readonly property int batteryThreshold: 10
    readonly property var device: UPower.displayDevice

    readonly property int level: device && device.isPresent ? Math.round((device.percentage || 0) * 100) : -1
    readonly property bool discharging: !!(device && device.isPresent && UPower.onBattery && device.state === UPowerDeviceState.Discharging)
    readonly property bool low: discharging && level >= 0 && level <= batteryThreshold

    // Survives a hot reload, so an edit to the shell cannot re-fire the
    // warning while the battery sits below the threshold (their reloadableId
    // trick).
    property PersistentProperties persisted: PersistentProperties {
        reloadableId: "qshell-battery"
        property bool notifiedLowBattery: false
    }

    onLowChanged: evaluateWarning()
    Component.onCompleted: evaluateWarning()

    // Their shouldWarnLowBattery: warn once on the way down, re-arm the
    // moment the state stops qualifying (charger plugged, or climbed back).
    function evaluateWarning() {
        if (low && !persisted.notifiedLowBattery)
            warnProc.running = true;
        persisted.notifiedLowBattery = low;
    }

    readonly property Process warnProc: Process {
        command: ["notify-send", "-a", "qshell", "-u", "critical", "-t", "30000", "-h", "string:qshell-glyph:󱐋", "Time to recharge!", "Battery is down to " + root.level + "%"]
    }

    readonly property Connections powerSourceWatch: Connections {
        target: UPower
        function onOnBatteryChanged() {
            // In-process equivalent of their omarchy-powerprofiles-set
            // autodetect path; PowerProfiles is quickshell's D-Bus client for
            // the same daemon powerprofilesctl drives.
            if (UPower.onBattery)
                PowerProfiles.profile = PowerProfile.Balanced;
            else
                PowerProfiles.profile = PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance : PowerProfile.Balanced;
        }
    }
}

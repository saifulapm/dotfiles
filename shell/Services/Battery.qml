import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Low-battery warnings + AC/battery power-profile switching — port of
// omarchy's services/battery plugin (Service.qml + BatteryModel.js, MIT, see
// CREDITS.md). Their 30-second check timer is not ported: the UPower display
// device pushes percentage/state changes on its own, so the warning logic
// re-evaluates from property bindings instead — the event-driven shape the
// no-polling rule asks for.
//
// The warning ladder goes past upstream's single 10 % check: 20 % gets a
// normal heads-up, 10 % and 5 % go critical. Each rung fires once per
// discharge — a level change fires only the deepest rung crossed and the
// latch remembers it, so draining 20 → 10 → 5 warns three times, a jump
// from 25 straight to 8 warns once (critically), and nothing repeats until
// the charger re-arms the ladder. Desktops skip the whole thing: their
// UPower display device is not a laptop battery.
//
// Their per-source saved-profile files are not ported either: upstream only
// writes them from an omarchy CLI we do not ship, so this is their behaviour
// on a machine where nothing was ever saved — AC gets performance when the
// daemon offers it (balanced otherwise), battery gets balanced.
QtObject {
    id: root

    // Descending; deepest crossed rung wins. Levels are percent.
    readonly property var warnLevels: [20, 10, 5]
    readonly property var device: UPower.displayDevice

    readonly property bool isLaptopBattery: !!(device && device.isPresent && device.isLaptopBattery)
    readonly property int level: device && device.isPresent ? Math.round((device.percentage || 0) * 100) : -1
    readonly property bool discharging: !!(isLaptopBattery && UPower.onBattery && device.state === UPowerDeviceState.Discharging)

    // Survives a hot reload, so an edit to the shell cannot re-fire a
    // warning while the battery sits below a threshold (their reloadableId
    // trick). warnedFloor is the lowest rung already fired this discharge;
    // 101 means the ladder is fully armed.
    property PersistentProperties persisted: PersistentProperties {
        reloadableId: "qshell-battery"
        property int warnedFloor: 101
    }

    onLevelChanged: evaluateWarning()
    onDischargingChanged: evaluateWarning()
    Component.onCompleted: evaluateWarning()

    function evaluateWarning() {
        // Plugging in (or the state otherwise leaving discharge) re-arms
        // every rung; the discharge latch never re-fires on its own. Written
        // only when it really changes — this handler also fires while the
        // UPower device tears down at shutdown, and an idempotent no-op is
        // the safest thing to do from a dying object graph.
        if (!discharging) {
            if (persisted.warnedFloor !== 101)
                persisted.warnedFloor = 101;
            return;
        }
        if (level < 0)
            return;
        // The deepest rung at or above the current level, skipped if a
        // previous change already fired it (or one below it).
        let rung = -1;
        for (let i = 0; i < warnLevels.length; i++) {
            if (level <= warnLevels[i])
                rung = warnLevels[i];
        }
        if (rung < 0 || persisted.warnedFloor <= rung)
            return;
        persisted.warnedFloor = rung;
        warnProc.command = rung <= 10 ? ["notify-send", "-a", "qshell", "-u", "critical", "-t", "30000", "-h", "string:qshell-glyph:󱐋", "Battery critically low", "Down to " + level + "% — plug in now"] : ["notify-send", "-a", "qshell", "-u", "normal", "-t", "15000", "-h", "string:qshell-glyph:󱐋", "Time to recharge!", "Battery is down to " + level + "%"];
        warnProc.running = true;
    }

    readonly property Process warnProc: Process {}

    readonly property Connections powerSourceWatch: Connections {
        target: UPower
        function onOnBatteryChanged() {
            // bin/power-profile owns the per-source MEMORY (omarchy's
            // powerprofiles-set port): it restores whatever the user last
            // chose for this source — the old in-process branch hardcoded
            // balanced/performance and forgot every choice.
            Quickshell.execDetached(["power-profile", "autodetect"]);
        }
    }

    // Boot restore, their powerprofiles-init: apply the saved profile for the
    // current source once per shell start. Also heals raw powerprofilesctl
    // drift — every OWN entry point saves through the same script.
    readonly property Timer profileInit: Timer {
        running: true
        interval: 1500
        onTriggered: Quickshell.execDetached(["power-profile", "autodetect"])
    }
}

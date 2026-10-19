import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "lib/control-system.mjs" as Lib
import "lib/voice.mjs" as V

// Control's Power section: battery, profile, charge limit where the hardware has one, then the session actions, each but Lock waiting for y.
Item {
    id: power

    required property var theme
    property int selected: 0
    readonly property var look: V.listLook(theme.tokens)
    // The action waiting for its y, or "".
    property string confirming: ""
    // The battery's end-of-charge threshold, or -1 where the hardware has none.
    property int chargeLimit: -1

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery.ready && battery.isLaptopBattery && battery.isPresent
    readonly property var profiles: PowerProfiles.hasPerformanceProfile ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance] : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    readonly property var items: (hasBattery ? [{
                    id: "battery",
                    title: "Battery",
                    detail: Math.round(battery.percentage * 100) + "% · " + UPowerDeviceState.toString(battery.state).toLowerCase()
                }] : []).concat([{
                id: "profile",
                title: "Profile",
                detail: PowerProfile.toString(PowerProfiles.profile).toLowerCase()
            }]).concat(chargeLimit >= 0 ? [{
                    id: "limit",
                    title: "Charge limit",
                    detail: chargeLimit + "%"
                }] : []).concat(Lib.ACTIONS.map(a => ({
                id: a.id,
                title: a.title,
                detail: a.id === confirming ? "y to confirm" : ""
            })))
    readonly property var rows: items

    function run(id) {
        confirming = "";
        Quickshell.execDetached(Lib.actionCommand(id));
    }

    function key(event) {
        const item = items[selected];
        if (confirming !== "") {
            if (event.key === Qt.Key_Y)
                run(confirming);
            else
                confirming = "";
            return true;
        }
        if (!item)
            return false;
        if (item.id === "profile" && (event.key === Qt.Key_H || event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            const i = profiles.indexOf(PowerProfiles.profile);
            PowerProfiles.profile = profiles[(i + (event.key === Qt.Key_H ? profiles.length - 1 : 1)) % profiles.length];
            return true;
        }
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
            return false;
        const action = Lib.ACTIONS.find(a => a.id === item.id);
        if (!action)
            return false;
        if (action.confirm)
            confirming = action.id;
        else
            run(action.id);
        return true;
    }

    function state() {
        return {
            confirming: confirming,
            profile: PowerProfile.toString(PowerProfiles.profile).toLowerCase(),
            chargeLimit: chargeLimit
        };
    }

    onSelectedChanged: confirming = ""
    onVisibleChanged: confirming = ""
    implicitHeight: hint.implicitHeight

    // The threshold changes only by root's hand, so it is read once.
    Process {
        running: true
        command: ["sh", "-c", "cat /sys/class/power_supply/*/charge_control_end_threshold 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text);
                power.chargeLimit = isNaN(v) ? -1 : v;
            }
        }
    }

    Text {
        id: hint
        textFormat: Text.PlainText
        leftPadding: 20
        text: power.look.tabText(power.confirming !== "" ? (Lib.ACTIONS.find(a => a.id === power.confirming).title + "? y confirms · any other key cancels") : "↵ act · h/l profile")
        color: power.confirming !== "" ? power.theme.color.danger : power.look.small.color
        font.family: power.look.small.font
        font.pixelSize: power.look.small.size
        font.letterSpacing: power.look.small.spacing
    }
}

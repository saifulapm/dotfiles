import Quickshell
import Quickshell.Io
import QtQuick
import "lib/control-system.mjs" as Lib
import "lib/voice.mjs" as V

// Control's Route section: where agent questions ring, Do Not Disturb, and the sync details.
Item {
    id: route

    required property var theme
    required property var notifs
    // Read once, when Control first opens, not when the warm-up makes it.
    property bool probe: true
    // The Desk's sync service, null until the Desk loads.
    required property var sync
    readonly property var units: sync ? sync.units : ({})
    property int selected: 0
    readonly property var look: V.listLook(theme.tokens)
    // phone or device, as workflow route last printed it; "" until it answers.
    property string to: ""
    // just dev points this at a fake, since workflow route tells every hub.
    readonly property string workflow: Quickshell.env("DOTS_WORKFLOW") || "workflow"
    readonly property var rows: [{
            title: "Questions ring on",
            detail: to || "unknown"
        }, {
            title: "Do Not Disturb",
            detail: notifs.dnd ? "on" : "off"
        }].concat(Lib.syncRows(units))

    function key(event) {
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
            return false;
        if (selected === 0 && !asker.running) {
            asker.command = [workflow, "route", to === "phone" ? "device" : "phone"];
            asker.running = true;
        } else if (selected === 1) {
            notifs.setDnd(!notifs.dnd);
        }
        return true;
    }

    function state() {
        // details are the rows' text as drawn, errors cut short; sync holds them whole.
        return { route: to, dnd: notifs.dnd, sync: units, details: rows.map(r => r.detail) };
    }

    implicitHeight: hint.implicitHeight

    // Each form of workflow route prints the route it leaves, so one call both sets and reads it.
    Process {
        id: asker
        running: route.probe
        command: [route.workflow, "route"]
        stdout: StdioCollector {
            onStreamFinished: {
                const to = Lib.routeOf(text);
                if (to)
                    route.to = to;
            }
        }
    }

    Text {
        id: hint
        textFormat: Text.PlainText
        leftPadding: 20
        text: route.look.tabText("↵ toggle")
        color: route.look.small.color
        font.family: route.look.small.font
        font.pixelSize: route.look.small.size
        font.letterSpacing: route.look.small.spacing
    }
}

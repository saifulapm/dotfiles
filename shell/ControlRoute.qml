import Quickshell
import Quickshell.Io
import QtQuick
import "lib/control-system.mjs" as Lib

// Control's Route section: where agent questions ring, Do Not Disturb, and the sync details.
Item {
    id: route

    required property var theme
    required property var notifs
    property int selected: 0
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
        }, {
            title: "Sync",
            detail: "no rounds yet"
        }]

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
        return { route: to, dnd: notifs.dnd };
    }

    implicitHeight: hint.implicitHeight

    // Each form of workflow route prints the route it leaves, so one call both sets and reads it.
    Process {
        id: asker
        running: true
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
        text: "↵ TOGGLE"
        color: route.theme.color.muted
        font.family: route.theme.tokens ? route.theme.tokens.type.ui : ""
        font.pixelSize: 10
        font.letterSpacing: 1.2
    }
}

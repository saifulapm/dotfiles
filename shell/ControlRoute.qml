import Quickshell
import Quickshell.Io
import QtQuick
import "lib/control-system.mjs" as Lib

// Control's Route section: where agent questions ring, then every sync unit; Control draws its page.
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
    // phone or device, as workflow route last printed it; "" until it answers.
    property string to: ""
    // just dev points this at a fake, since workflow route tells every hub.
    readonly property string workflow: Quickshell.env("DOTS_WORKFLOW") || "workflow"
    readonly property var rows: [{
            title: "Questions ring on",
            detail: to || "unknown",
            glyph: String.fromCodePoint(0xF009A),
            sub: to === "phone" ? "Phone" : to === "device" ? "This device" : "Unknown"
        }].concat(Lib.syncRows(units).map(r => Object.assign({
                glyph: String.fromCodePoint(0xF04E6)
            }, r)))

    function key(event) {
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
            return false;
        if (selected === 0 && !asker.running) {
            asker.command = [workflow, "route", to === "phone" ? "device" : "phone"];
            asker.running = true;
        }
        return true;
    }

    function state() {
        // details are the rows' text as drawn, errors cut short; sync holds them whole.
        return { route: to, dnd: notifs.dnd, sync: units, details: rows.map(r => r.detail) };
    }


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
}

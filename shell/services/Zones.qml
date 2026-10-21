import Quickshell
import Quickshell.Io
import QtQuick

// What bin/dots-zones prints, {home, zones, next}: run when the calendar first asks, and again once the clock passes the next offset change.
Scope {
    id: service

    required property var clock
    // null until the first answer; a run that fails keeps the last one.
    property var answer: null
    readonly property bool due: answer !== null && answer.next !== null && clock.now.getTime() >= answer.next * 1000
    onDueChanged: if (due)
        run()

    function need() {
        if (answer === null)
            run();
    }

    function run() {
        if (!zonesRun.running)
            zonesRun.running = true;
    }

    Process {
        id: zonesRun
        // The user manager's PATH need not have bin/, so this runs the one beside the shell.
        command: [Quickshell.shellDir + "/../bin/dots-zones"]
        stdout: StdioCollector {
            id: zonesOut
        }
        onExited: code => {
            if (code !== 0)
                return;
            try {
                service.answer = JSON.parse(zonesOut.text);
            } catch (e) {}
        }
    }
}

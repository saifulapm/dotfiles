pragma Singleton
import Quickshell
import QtQuick

// Shell-wide state that `qs ipc call shell status` reports.
Singleton {
    // Names of the surfaces that have loaded; each surface appends itself on first open.
    property list<string> loaded: []
    property list<QtObject> ticks: []
    // When the running recording started, in ms since the epoch; 0 while nothing records.
    property real recordingSince: 0

    // A function, not a binding: a binding over ticks would miss a Tick starting or stopping.
    function timers(): int {
        return ticks.filter(t => t.running).length;
    }

    function addTick(tick) {
        ticks.push(tick);
    }

    function removeTick(tick) {
        ticks = ticks.filter(t => t !== tick);
    }
}

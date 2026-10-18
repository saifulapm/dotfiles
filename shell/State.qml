pragma Singleton
import Quickshell
import QtQuick

// Shell-wide state that `qs ipc call shell status` reports.
Singleton {
    // Names of the surfaces that have loaded; each surface appends itself on first open.
    property list<string> loaded: []
    property list<QtObject> ticks: []
    readonly property int timers: ticks.filter(t => t.running).length

    function addTick(tick) {
        ticks.push(tick);
    }

    function removeTick(tick) {
        ticks = ticks.filter(t => t !== tick);
    }
}

pragma Singleton
import Quickshell
import QtQuick
import "lib/motion.mjs" as M

// Shell-wide state that `qs ipc call shell status` reports.
Singleton {
    // Names of the surfaces that have loaded; each appends itself when made, in the warm-up after the first frame or on an earlier open.
    property list<string> loaded: []
    property list<QtObject> ticks: []
    // When the running recording started, in ms since the epoch; 0 while nothing records.
    property real recordingSince: 0
    // How many times slower surfaces move, read once at start; only bin/dots-dev sets it.
    readonly property real slowdown: M.slowdownOf(Quickshell.env("DOTS_MOTION_SLOWDOWN"))

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

import Quickshell
import QtQuick
import ".." as Root
import "../lib/margins.mjs" as M

// The wait to the next minute is worked out on every tick, so a late tick never drifts the clock.
Scope {
    id: clock

    property var now: new Date()

    Root.Tick {
        interval: M.msToNextMinute(new Date())
        running: true
        repeat: true
        onTriggered: {
            const t = new Date();
            clock.now = t;
            interval = M.msToNextMinute(t);
        }
    }
}

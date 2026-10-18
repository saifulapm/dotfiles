import Quickshell
import QtQuick
import ".." as Root
import "../lib/margins.mjs" as M

// The shell's one timer. It fires on each minute boundary and works the wait out again
// every time, so it stays aligned however late a tick lands.
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

import Quickshell
import Quickshell.Wayland
import QtQuick

// The idle check's other client: a small window that holds a Wayland idle inhibitor while it shows.
ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 200
        implicitHeight: 120
        color: "black"
        title: "idle-inhibitor"

        IdleInhibitor {
            window: win
            enabled: true
        }
    }
}

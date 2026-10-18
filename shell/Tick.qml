import QtQuick
import "." as Root

// The one Timer the shell may use. It registers in State so status counts the running ones.
Timer {
    id: tick

    Component.onCompleted: Root.State.addTick(tick)
    Component.onDestruction: Root.State.removeTick(tick)
}

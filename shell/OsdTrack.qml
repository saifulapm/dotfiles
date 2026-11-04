import QtQuick
import "." as Root

// Frost's volume bar for a value from 0 to 100: a thin track with the accent fill growing to the value.
Item {
    id: bar

    required property var look
    property real value: 0
    readonly property alias fillItem: fill
    // The fill's animation as `island state` reports it: what the animation runs with, and the share of the track it grows to.
    readonly property var fillAnimation: ({ ms: grow.duration, curve: "ease-out", to: Math.max(0, Math.min(100, value)) / 100 })
    implicitHeight: look.thickness

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: bar.look.color
    }

    Rectangle {
        id: fill
        height: parent.height
        width: parent.width * Math.max(0, Math.min(100, bar.value)) / 100
        radius: height / 2
        color: bar.look.fill

        Behavior on width {
            NumberAnimation {
                id: grow
                // Slowed like every other motion.
                duration: bar.look.duration * Root.State.slowdown
                easing.type: Easing.OutCubic
            }
        }
    }
}

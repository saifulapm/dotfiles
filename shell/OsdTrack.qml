import QtQuick

// Frost's volume bar for a value from 0 to 100: a thin track with the accent fill growing to the value.
Item {
    id: bar

    required property var look
    property real value: 0
    readonly property alias fillItem: fill
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
                duration: bar.look.duration
                easing.type: Easing.OutCubic
            }
        }
    }
}

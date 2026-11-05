import QtQuick

// The OSD's bar for a value from 0 to 100: one rounded bar.
Item {
    id: bars

    required property var look
    property real value: 0
    implicitHeight: 14

    // How many of 20 read as lit, from what is drawn.
    function drawn() {
        return Math.round(roundFill.width / roundTrack.width * 20);
    }

    Rectangle {
        id: roundTrack
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: bars.look.unlit.color

        Rectangle {
            id: roundFill
            width: parent.width * Math.min(Math.max(bars.value, 0), 100) / 100
            height: parent.height
            radius: parent.radius
            color: bars.look.lit.color
        }
    }
}

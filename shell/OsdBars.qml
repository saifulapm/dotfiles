import QtQuick

// The OSD's bar for a value from 0 to 100 in a theme's style: Paper's 20 bars, Blueprint's ▮ blocks or Artboard's one rounded bar.
Item {
    id: bars

    required property var look
    property real value: 0
    readonly property int lit: look.litCount(value)
    implicitHeight: 14

    // How many of 20 read as lit, from what is drawn; a function, since a binding would not see the Repeater make its bars.
    function drawn() {
        return look.bars === "blocks" ? litBlocks.text.length : look.bars === "bars" ? Array.from({ length: 20 }, (_, i) => barRepeater.itemAt(i)).filter(b => b && b.on).length : Math.round(roundFill.width / roundTrack.width * 20);
    }

    // Paper: 20 bars, the lit ones tall in the accent.
    Row {
        visible: bars.look.bars === "bars"
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Repeater {
            id: barRepeater
            model: 20

            Rectangle {
                required property int index
                readonly property bool on: index < bars.lit
                anchors.verticalCenter: parent.verticalCenter
                width: 4
                height: on ? 14 : 8
                color: on ? bars.look.lit.color : bars.look.unlit.color
            }
        }
    }

    // Blueprint: a run of ▮ blocks, the unlit ones in the line colour.
    Row {
        visible: bars.look.bars === "blocks"
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: litBlocks
            textFormat: Text.PlainText
            text: "▮".repeat(bars.lit)
            color: bars.look.lit.color
            font.family: bars.look.value.font
            font.pixelSize: 12
            font.letterSpacing: 0.6
        }
        Text {
            textFormat: Text.PlainText
            text: "▮".repeat(20 - bars.lit)
            color: bars.look.unlit.color
            font.family: bars.look.value.font
            font.pixelSize: 12
            font.letterSpacing: 0.6
        }
    }

    // Artboard: one rounded bar.
    Rectangle {
        id: roundTrack
        visible: bars.look.bars === "round"
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

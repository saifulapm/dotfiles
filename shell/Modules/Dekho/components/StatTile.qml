import QtQuick

// omakade's fact tile out of GameDetails: a quiet label over a loud value, in a
// card that is barely a card. Three of them across is how that page states the
// numbers nobody reads in a sentence — playtime, achievements, completion for a
// game; runtime, rating, status, seasons, studio, country for a title.
Rectangle {
    id: tile

    required property var style
    required property string label
    required property string value

    implicitHeight: style.ui(88)
    radius: style.radiusSm
    color: style.alpha(style.fg, 0.045)
    border.color: style.alpha(style.fg, 0.13)

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: tile.style.ui(16)
        anchors.rightMargin: tile.style.ui(12)
        spacing: tile.style.ui(7)

        Text {
            text: tile.label
            color: tile.style.muted
            font.family: tile.style.fontFamily
            font.pixelSize: tile.style.type(9)
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: tile.value
            color: tile.style.brightFg
            font.family: tile.style.fontFamily
            font.pixelSize: tile.style.type(16)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }
}

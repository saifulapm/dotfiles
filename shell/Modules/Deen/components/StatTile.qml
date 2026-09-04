import QtQuick

// Dekho's fact tile, itself omakade's out of GameDetails: a quiet label over a
// loud value, in a card that is barely a card.
//
// Here it states the two numbers the memorisation screen used to bury in a
// sentence — how much is due and how much is enrolled — which are the numbers
// you open that screen to find out.
Rectangle {
    id: tile

    required property var style
    required property string label
    required property string value
    // Lets a tile that means "you are done" say so in the theme's ok colour
    // rather than in the same white as "eleven still to go".
    property color valueColor: style.brightFg

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
            textFormat: Text.PlainText
            text: tile.label
            color: tile.style.muted
            font.family: tile.style.fontFamily
            font.pixelSize: tile.style.type(9)
            font.weight: Font.DemiBold
        }
        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: tile.value
            color: tile.valueColor
            font.family: tile.style.fontFamily
            font.pixelSize: tile.style.type(16)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }
}

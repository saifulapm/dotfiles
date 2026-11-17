import QtQuick

// A card's action on board 2: the first is inverted, the on colour filled with the fill's text; the rest are quiet tiles. No key is drawn.
Rectangle {
    id: button

    property string text: ""
    property bool primary: false
    property color ink: "white"
    property color fill: "black"
    property string font: ""
    readonly property alias label: word
    // Its fill and its text as drawn, for `island state`.
    readonly property var drawn: ({ text: word.text, primary, fill: String(color), ink: String(word.color) })
    height: 32
    radius: 10
    color: primary ? ink : Qt.alpha(ink, 0.07)

    Text {
        id: word
        anchors.centerIn: parent
        width: Math.min(implicitWidth, button.width - 20)
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        text: button.text
        color: button.primary ? button.fill : button.ink
        font.family: button.font
        font.pixelSize: 13
        font.weight: button.primary ? Font.Bold : Font.Medium
    }
}

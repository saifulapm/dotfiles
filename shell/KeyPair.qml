import QtQuick

// A key and its word as every surface's legend draws them: the key in mono, the word in the small dim text; a pair with no word draws its key alone.
Rectangle {
    id: keyPair

    required property var modelData
    required property var theme
    required property var look
    property color keyColor: look.chip.key
    property color wordColor: theme.color.muted
    property int keyWeight: Font.Medium
    // What the checks read: the key and word as drawn, the two as one line, the word's spacing and the key's own Text.
    readonly property string keyLabel: keyText.text
    readonly property string wordLabel: wordText.text
    readonly property string drawn: keyLabel + " " + wordLabel
    readonly property real wordSpacing: wordText.font.letterSpacing
    property alias keyGlyph: keyText

    width: pair.implicitWidth + 14
    height: pair.implicitHeight + 6
    radius: 6
    color: look.chip.fill

    Row {
        id: pair
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: keyText
            textFormat: Text.PlainText
            text: keyPair.modelData.key
            color: keyPair.keyColor
            font.family: keyPair.theme.tokens ? keyPair.theme.tokens.type.mono : ""
            font.pixelSize: keyPair.look.small.size
            font.letterSpacing: keyPair.look.small.spacing
            font.weight: keyPair.keyWeight
        }
        Text {
            id: wordText
            visible: text !== ""
            textFormat: Text.PlainText
            text: keyPair.modelData.word
            color: keyPair.wordColor
            font.family: keyPair.look.small.font
            font.pixelSize: keyPair.look.small.size
            font.letterSpacing: keyPair.look.small.spacing
        }
    }
}

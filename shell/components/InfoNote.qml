import QtQuick

// Warn-glyph plus a wrapped explanatory sentence — why a control is inert
// ("power-profiles-daemon is not installed…"), not a hover tooltip.
Row {
    id: note

    required property var theme
    property string text: ""

    width: parent ? parent.width : 0
    spacing: theme.space(1.5)

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰋽"
        color: note.theme.warn
        pixelSize: note.theme.fontPx(0.917)
    }

    Text {
        width: note.width - note.theme.space(4)
        text: note.text
        color: note.theme.textMuted
        font.family: note.theme.fontUi
        font.pixelSize: note.theme.fontPx(0.833)
        wrapMode: Text.WordWrap
    }
}

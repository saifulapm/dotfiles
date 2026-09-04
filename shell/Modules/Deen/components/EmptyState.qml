import QtQuick

// Dekho's empty column, itself omakade's out of LibraryView: a glyph, a title,
// a message and one thing to do about it.
//
// This module has three states that are empty for reasons worth naming and a
// bare blank page says none of them — nothing enrolled yet, nothing due until
// later, and a `deen` binary that is not installed. The last of those is the
// one that matters most: it is what every machine but this one shows today.
Column {
    id: empty

    required property var style
    property string glyph: "◇"
    property string title: ""
    property string message: ""
    // "" hides the button entirely, which is right for the states with nothing
    // to retry.
    property string action: ""

    signal actionRequested

    spacing: style.ui(12)

    Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: empty.glyph
        color: empty.style.accent
        font.family: empty.style.fontFamily
        font.pixelSize: empty.style.type(42)
    }

    Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: empty.title
        color: empty.style.fg
        font.family: empty.style.fontFamily
        font.pixelSize: empty.style.type(16)
        font.weight: Font.DemiBold
    }

    Text {
        textFormat: Text.PlainText
        width: Math.min(implicitWidth, empty.parent ? empty.parent.width * 0.6 : implicitWidth)
        anchors.horizontalCenter: parent.horizontalCenter
        visible: empty.message !== ""
        text: empty.message
        color: empty.style.muted
        font.family: empty.style.fontFamily
        font.pixelSize: empty.style.type(11)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    GlassButton {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: empty.action !== ""
        style: empty.style
        text: empty.action
        compact: true
        onClicked: empty.actionRequested()
    }
}

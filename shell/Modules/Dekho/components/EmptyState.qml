import QtQuick

// omakade's empty column out of LibraryView: a glyph, a title, a message and
// one thing to do about it. Every list in this module can be empty for a reason
// worth naming — no TMDB key, a query that matched nothing, a filter
// combination with no results, a machine that has never played anything — and
// a bare blank page says none of them.
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
        anchors.horizontalCenter: parent.horizontalCenter
        text: empty.glyph
        color: empty.style.accent
        font.family: empty.style.fontFamily
        font.pixelSize: empty.style.type(42)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: empty.title
        color: empty.style.fg
        font.family: empty.style.fontFamily
        font.pixelSize: empty.style.type(16)
        font.weight: Font.DemiBold
    }

    Text {
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

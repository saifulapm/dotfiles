import QtQuick

// Omarchy's BarIconButton geometry: a fixed 27 px click slot with a 13 px
// glyph optically centered on a 16 px canvas. `status` variant narrows to
// the 21 px slot with a 10 px glyph (their BarIndicator).
BarButton {
    id: icon

    property string glyph: ""
    property bool status: false
    // Override for glyph color; empty tracks contentColor (active/normal).
    property var glyphColor: undefined

    fixedWidth: status ? 21 : 27

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: icon.glyph
        color: icon.glyphColor !== undefined ? icon.glyphColor : icon.contentColor
        pixelSize: icon.status ? icon.theme.fontPx(0.833) : 13
    }
}

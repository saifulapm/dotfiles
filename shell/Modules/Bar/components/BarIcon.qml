import QtQuick

// Omarchy's BarIconButton geometry: a fixed 27 px click slot with a 13 px
// glyph optically centered on a 16 px canvas. `status` variant narrows to
// the 21 px slot with a 10 px glyph (their BarIndicator).
//
// On a vertical bar the slot swaps axes exactly as theirs does — the fixed
// size becomes the button's HEIGHT and the width falls back to the bar's
// thickness.
BarButton {
    id: icon

    property string glyph: ""
    property bool status: false
    // Override for glyph color; empty tracks contentColor (active/normal).
    property var glyphColor: undefined
    // Rotates the glyph in place (the vertical tray's chevron rides this).
    property real glyphRotation: 0

    readonly property int slotSize: status ? 21 : 27

    fixedWidth: vertical ? -1 : slotSize
    fixedHeight: vertical ? slotSize : -1

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        rotation: icon.glyphRotation
        text: icon.glyph
        color: icon.glyphColor !== undefined ? icon.glyphColor : icon.contentColor
        pixelSize: icon.status ? icon.theme.fontPx(0.833) : 13
        // Upstream's `!root.bar || root.bar.foregroundAnimationEnabled`.
        colorAnimationEnabled: !icon.bar || icon.bar.foregroundAnimationEnabled === true
    }
}

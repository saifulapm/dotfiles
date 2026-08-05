import QtQuick

// Nerd Font glyphs carry wildly inconsistent side bearings, so centering the
// Text's layout box leaves the visible ink off-center. Measure the painted
// ink (tightBoundingRect) and correct horizontally only — the baseline stays
// shared so mixed-height icons don't drift vertically. Concept from omarchy's
// Ui/OpticalGlyph.qml (CREDITS.md).
Item {
    id: root

    property string text: ""
    property color color: "white"
    property string fontFamily: "Symbols Nerd Font"
    property int pixelSize: 14

    implicitWidth: glyph.implicitWidth
    implicitHeight: glyph.implicitHeight

    TextMetrics {
        id: metrics
        text: root.text
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
    }

    Text {
        id: glyph
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: {
            const tight = metrics.tightBoundingRect;
            if (tight.width <= 0)
                return 0;
            return Math.round(glyph.implicitWidth / 2 - (tight.x + tight.width / 2));
        }
        text: root.text
        color: root.color
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        renderType: Text.NativeRendering

        // Omarchy's 160 ms state-color transition.
        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }
    }
}

import QtQuick

// Nerd Font glyphs carry wildly inconsistent side bearings, so centering the
// Text's layout box leaves the visible ink off-center. Measure the painted
// ink (tightBoundingRect) and correct horizontally only — the baseline stays
// shared so mixed-height icons don't drift vertically. Concept from omarchy's
// Ui/OpticalGlyph.qml.
Item {
    id: root

    property string text: ""
    property color color: "white"
    property string fontFamily: "Symbols Nerd Font"
    property int pixelSize: 13
    // Omarchy gates their bar glyphs' color transition on the bar's
    // foregroundAnimationEnabled (their WidgetButton Behavior) so the
    // transparency auto-contrast flip lands in ONE frame instead of
    // crossfading through unreadable in-betweens. Bar consumers wire this
    // to that flag; everything else keeps the animated default.
    property bool colorAnimationEnabled: true

    // Slots holding a lone glyph can center the ink vertically too — the
    // shared-baseline default only matters when a glyph sits beside text,
    // and a short-ink glyph (the iCloud cloud is 0.56em against the 0.83em
    // Material Design standard) otherwise sits visibly low in its slot.
    property bool verticalInkCenter: false

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
        anchors.verticalCenterOffset: {
            if (!root.verticalInkCenter)
                return 0;
            const tight = metrics.tightBoundingRect;
            if (tight.height <= 0)
                return 0;
            // tightBoundingRect is baseline-relative (y is negative above
            // the baseline), so the ink's position inside the item runs
            // through baselineOffset.
            const inkCenter = glyph.baselineOffset + tight.y + tight.height / 2;
            return Math.round(glyph.implicitHeight / 2 - inkCenter);
        }
        text: root.text
        color: root.color
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        renderType: Text.NativeRendering

        // Omarchy's 160 ms state-color transition.
        Behavior on color {
            enabled: root.colorAnimationEnabled
            ColorAnimation {
                duration: 160
            }
        }
    }
}

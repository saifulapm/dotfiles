import Quickshell
import QtQuick
import "." as Root
import "lib/surface.mjs" as S
import "lib/switch.mjs" as W

// The one frame every shell surface draws: its fill and a 1 px frame, square, with no shadow; a colorscheme switch crossfades both.
Item {
    id: surface

    property var tokens: null
    // island, card or chip; an island and its specimen chip are a slab, a card is framed.
    property string role: "card"
    // Parts of the look swapped for a moment, as the island's lease draws its last minute; null keeps the scheme's.
    property var restyle: null
    readonly property var style: S.restyled(S.surfaceStyle(tokens, role), restyle)
    readonly property color accent: tokens ? tokens.color.accent : "transparent"
    // A bare surface draws no fill or frame of its own, as the island, whose shape draws its fill beside it.
    property bool bare: false
    default property alias content: inner.data
    // The name the surfaces host knows a card by, so a press on it never counts as a click outside.
    objectName: "card"
    // The fill as the body draws it, so a state function can report the colour on screen.
    readonly property alias drawnFill: fillRect.color

    // The surface as drawn, in the window's pixels.
    function drawnBox() {
        const a = mapToItem(null, 0, 0);
        const b = mapToItem(null, width, height);
        return { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y };
    }

    Rectangle {
        id: fillRect
        anchors.fill: parent
        visible: !surface.bare
        color: surface.style.fill
        border.width: surface.style.frame.width
        border.color: surface.style.frame.color

        // A colorscheme switch crossfades the fill and frame with the paper, on Qt's nearest curve to the paper's.
        Behavior on color {
            ColorAnimation {
                duration: W.SWITCH.ms * Root.State.slowdown
                easing.type: Easing.InOutSine
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: W.SWITCH.ms * Root.State.slowdown
                easing.type: Easing.InOutSine
            }
        }
    }

    Item {
        id: inner
        anchors.fill: parent
    }
}

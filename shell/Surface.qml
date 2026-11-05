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
    // The paper at the style's wash, as a panel lays it over the desktop; it crossfades on a colorscheme switch like the fill.
    property color wash: tokens ? Qt.alpha(tokens.color.paper, style.wash) : "transparent"
    Behavior on wash {
        ColorAnimation {
            duration: W.SWITCH.ms * Root.State.slowdown
            easing.type: Easing.InOutSine
        }
    }
    // The Motion that plays this card's open and close; the island and the previews have none.
    property var motion: null
    readonly property var pose: motion ? motion.pose : ({ lift: 0, scale: 1 })
    default property alias content: inner.data
    // The name the surfaces host knows a card by, so a press on it never counts as a click outside.
    objectName: "card"
    // The fill as the body draws it, so a state function can report the colour on screen.
    readonly property alias drawnFill: fillRect.color

    scale: pose.scale

    // The card as drawn this frame, moved and scaled by its motion, in the window's pixels.
    function drawnBox() {
        const a = mapToItem(null, 0, 0);
        const b = mapToItem(null, width, height);
        return { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y };
    }
    transform: Translate {
        y: surface.pose.lift
    }

    Rectangle {
        id: fillRect
        anchors.fill: parent
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

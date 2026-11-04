import Quickshell
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "lib/surface.mjs" as S

// The one frame every shell surface draws: fill, frame, shadow, corner and the theme's signature parts.
Item {
    id: surface

    property var tokens: null
    // island, card or chip; each has its own shadow and corner numbers in surface.mjs.
    property string role: "card"
    // Shown above the top-left corner when the theme draws frame labels.
    property string label: ""
    // Parts of the look swapped for a moment, as the island's lease draws its last minute; null keeps the theme's.
    property var restyle: null
    readonly property var style: S.restyled(S.surfaceStyle(tokens, role), restyle)
    readonly property real chamfer: style.corner.chamfer
    readonly property var shadow: style.shadow
    readonly property color accent: tokens ? tokens.color.accent : "transparent"
    // The Motion that plays this card's open and close; the island and the previews have none.
    property var motion: null
    readonly property var pose: motion ? motion.pose : ({ lift: 0, scale: 1, outline: 1, fill: 1, text: 1 })
    // What a surface puts in its card fades in with pose.text: with the fill after a plot's outline, after the glass in Hi-Fi.
    default property alias content: inner.data
    // The glass highlight line, so a state function can report where it is drawn.
    readonly property alias highlight: highlightLine
    // The fill as the body draws it, so a state function can report the colour on screen.
    readonly property alias drawnFill: fillRect.color
    // A theme that blurs draws this box as glass; the panel hands `region` to its window, which asks niri to blur behind it.
    readonly property bool glass: tokens ? tokens.niri.blur === true : false
    // The box at rest, mapped from the parent: Region follows an item's geometry, not the open's lift and scale, so a region on the surface itself stays where the open began.
    readonly property Region region: Region {
        readonly property point at: surface.parent ? surface.parent.mapToItem(null, surface.x, surface.y) : Qt.point(surface.x, surface.y)
        x: Math.round(at.x)
        y: Math.round(at.y)
        width: Math.round(surface.width)
        height: Math.round(surface.height)
        radius: surface.style.corner.radius
    }

    scale: pose.scale

    // A colour as the fill fades in; at rest it is left alone, since Qt.alpha would make transparent opaque black.
    function faded(c) {
        return pose.fill < 1 ? Qt.alpha(c, pose.fill) : c;
    }

    // The card as drawn this frame, moved and scaled by its motion, in the window's pixels.
    function drawnBox() {
        const a = mapToItem(null, 0, 0);
        const b = mapToItem(null, width, height);
        return { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y };
    }
    // The blur region as niri gets it, in the window's pixels, read from the Region itself so a state function reports what is asked for.
    function regionBox() {
        return { x: region.x, y: region.y, w: region.width, h: region.height, radius: region.radius };
    }
    transform: Translate {
        y: surface.pose.lift
    }

    Rectangle {
        visible: surface.shadow.kind === "hard" && !surface.chamfer
        opacity: surface.pose.fill
        x: surface.shadow.x
        y: surface.shadow.y
        width: surface.width
        height: surface.height
        radius: surface.style.corner.radius
        color: surface.shadow.color
    }

    // Loaded only for themes that blur, so a hard-shadow theme pays for no shader.
    Loader {
        active: surface.shadow.kind === "soft" || surface.shadow.kind === "glow"
        opacity: surface.pose.fill
        anchors.fill: parent
        sourceComponent: RectangularShadow {
            offset.x: surface.shadow.x
            offset.y: surface.shadow.y
            // Qt's docs give 1.2 times the CSS blur for the same falloff.
            blur: surface.shadow.blur * 1.2
            spread: surface.shadow.spread
            radius: surface.style.corner.radius || surface.chamfer / 2
            color: Qt.alpha(surface.shadow.color, surface.shadow.alpha)
        }
    }

    Rectangle {
        id: fillRect
        visible: !surface.chamfer && surface.pose.outline >= 1
        anchors.fill: parent
        radius: surface.style.corner.radius
        color: surface.faded(surface.style.fill)
        border.width: surface.style.frame.width
        // A warm open lights the frame with its glass, so the hairline never shows before it.
        border.color: surface.motion?.curves?.kind === "warm" ? surface.faded(surface.style.frame.color) : surface.style.frame.color
    }

    // Hi-Fi's glass catches light in a 1 px line of ink under the top border, whatever the island shows.
    Rectangle {
        id: highlightLine
        visible: !!surface.style.highlight
        opacity: surface.pose.fill
        x: surface.style.frame.width
        y: surface.style.frame.width
        width: surface.width - 2 * surface.style.frame.width
        height: 1
        color: surface.style.highlight || "transparent"
    }

    // A cut corner bevels the top-left and bottom-right, like the designs' clip-path polygons.
    Loader {
        active: surface.chamfer > 0
        visible: surface.pose.outline >= 1
        anchors.fill: parent
        sourceComponent: Shape {
            // CurveRenderer's smoother diagonals cost a warm open 5 to 10 ms more on its first frame.
            preferredRendererType: Shape.GeometryRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: surface.shadow.kind === "hard" ? surface.faded(surface.shadow.color) : "transparent"
                PathRectangle {
                    x: surface.shadow.x
                    y: surface.shadow.y
                    width: surface.width
                    height: surface.height
                    topLeftRadius: surface.chamfer
                    bottomRightRadius: surface.chamfer
                    bevel: true
                }
            }

            ShapePath {
                id: body
                strokeWidth: surface.style.frame.width
                strokeColor: surface.style.frame.width ? surface.style.frame.color : "transparent"
                fillColor: surface.faded(surface.style.fill)
                joinStyle: ShapePath.MiterJoin
                PathRectangle {
                    width: surface.width
                    height: surface.height
                    topLeftRadius: surface.chamfer
                    bottomRightRadius: surface.chamfer
                    bevel: true
                    strokeAdjustment: body.strokeWidth
                }
            }
        }
    }

    // A plot draws the frame's own path, chamfers and all, from the top edge round, before any fill.
    Loader {
        // Only while the card shows, so a closed Blueprint surface keeps no pen.
        active: surface.pose.outline < 1 && surface.visible
        anchors.fill: parent
        sourceComponent: Shape {
            preferredRendererType: Shape.GeometryRenderer

            ShapePath {
                id: pen
                strokeWidth: surface.style.frame.width
                strokeColor: surface.style.frame.width ? surface.style.frame.color : "transparent"
                fillColor: "transparent"
                joinStyle: ShapePath.MiterJoin
                trim.end: surface.pose.outline
                PathRectangle {
                    width: surface.width
                    height: surface.height
                    radius: surface.style.corner.radius
                    topLeftRadius: surface.chamfer || surface.style.corner.radius
                    bottomRightRadius: surface.chamfer || surface.style.corner.radius
                    bevel: surface.chamfer > 0
                    strokeAdjustment: pen.strokeWidth
                }
            }
        }
    }

    // Registration ticks just outside the edges, where each chamfer meets them.
    Repeater {
        model: surface.style.ticks ? [[surface.chamfer, -6, 1, 4], [-6, surface.chamfer, 4, 1], [surface.width - surface.chamfer - 1, surface.height + 2, 1, 4], [surface.width + 2, surface.height - surface.chamfer - 1, 4, 1]] : []

        Rectangle {
            required property var modelData
            x: modelData[0]
            y: modelData[1]
            width: modelData[2]
            height: modelData[3]
            color: surface.accent
            opacity: 0.6 * surface.pose.fill
        }
    }

    // A design tool's selection: four handles centred on the corners and the frame's name above it.
    Repeater {
        model: surface.style.handles ? [[0, 0], [1, 0], [0, 1], [1, 1]] : []

        Rectangle {
            required property var modelData
            x: modelData[0] * surface.width - 4
            y: modelData[1] * surface.height - 4
            z: 1
            opacity: surface.pose.fill
            width: 8
            height: 8
            color: surface.style.handleFill || surface.style.fill
            border.width: 1.5
            border.color: surface.accent
        }
    }

    // The label as drawn: the Text item's own text and visibility, for the state functions.
    function frameLabel() {
        const a = frameText.mapToItem(null, 0, 0);
        const b = frameText.mapToItem(null, frameText.width, frameText.height);
        return { text: frameText.text, visible: frameText.visible, truncated: frameText.truncated, box: { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y } };
    }

    Text {
        id: frameText
        textFormat: Text.PlainText
        visible: surface.style.handles && surface.label !== ""
        opacity: surface.pose.fill
        y: -20
        // One line no wider than the card, so a long label, such as a 200-character app id, elides at the card's right edge.
        width: surface.width
        maximumLineCount: 1
        elide: Text.ElideRight
        text: surface.label
        color: surface.accent
        font.family: surface.tokens ? surface.tokens.type.ui : ""
        font.pixelSize: 11
        font.weight: Font.Medium
    }

    Item {
        id: inner
        anchors.fill: parent
        opacity: surface.pose.text
    }
}

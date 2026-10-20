import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "lib/surface.mjs" as S

// The one frame every shell surface draws: fill, frame, shadow, corner and the theme's signature parts.
Item {
    id: surface

    property var tokens: null
    // island, card or window; each has its own shadow and corner numbers in surface.mjs.
    property string role: "card"
    // Shown above the top-left corner when the theme draws frame labels.
    property string label: ""
    readonly property var style: S.surfaceStyle(tokens, role)
    readonly property real chamfer: style.corner.chamfer
    readonly property var shadow: style.shadow
    readonly property color accent: tokens ? tokens.color.accent : "transparent"
    // The Motion that plays this card's open and close; the island and the previews have none.
    property var motion: null
    readonly property var pose: motion ? motion.pose : ({ lift: 0, scale: 1, outline: 1, fill: 1 })
    // What a surface puts in its card fades in with the fill, after a plot's outline.
    default property alias content: inner.data

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
        visible: !surface.chamfer && surface.pose.outline >= 1
        anchors.fill: parent
        radius: surface.style.corner.radius
        color: surface.faded(surface.style.fill)
        border.width: surface.style.frame.width
        border.color: surface.style.frame.color
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
            color: surface.style.fill
            border.width: 1.5
            border.color: surface.accent
        }
    }

    Text {
        textFormat: Text.PlainText
        visible: surface.style.handles && surface.label !== ""
        opacity: surface.pose.fill
        y: -20
        text: surface.label
        color: surface.accent
        font.family: surface.tokens ? surface.tokens.type.ui : ""
        font.pixelSize: 11
        font.weight: Font.Medium
    }

    Item {
        id: inner
        anchors.fill: parent
        opacity: surface.pose.fill
    }
}

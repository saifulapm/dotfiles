import QtQuick
import QtQuick.Shapes
import "../Commons/gradient.js" as Gradient

// A rounded-rect border painted with a gradient, for the surfaces whose
// `border` token carries one ("#26a269ee #2ec27eee 45deg"). QtQuick's
// Rectangle border takes a single color and ShapePath strokes take one too,
// so the ring is drawn as a FILLED path instead: the outer rounded rect and
// the inner one in a single path with OddEvenFill, which makes the middle a
// hole. Whatever the ring surrounds shows through unpainted — the lock field
// is translucent, and covering it would be visible.
//
// This is omarchy's Border.qml/BorderGeometry.js idea reduced to the one case
// we need: a uniform width on all four sides. Their per-side widths and the
// hand-rolled arc path builder that goes with them are not ported — nothing
// in our schema asks for an uneven border.
//
// Anchor it over the Rectangle it belongs to and give it the same radius; set
// that Rectangle's own border.width to 0 while `active` is true.
Item {
    id: root

    // Gradient-or-solid token. A solid one leaves `active` false and draws
    // nothing, so the plain Rectangle border stays in charge.
    property string spec: ""
    property real borderWidth: 1
    property real cornerRadius: 0

    readonly property var parsed: Gradient.parseSpec(spec)
    readonly property bool active: parsed.enabled && borderWidth > 0

    visible: active
    // A hidden Shape still costs a scene-graph node and a render pass, so
    // keep it out of the tree entirely until a gradient theme is loaded.
    Loader {
        anchors.fill: parent
        active: root.active
        sourceComponent: Shape {
            id: ring
            preferredRendererType: Shape.CurveRenderer

            readonly property var line: Gradient.endpoints(root.width, root.height, root.parsed.angle)

            ShapePath {
                fillRule: ShapePath.OddEvenFill
                strokeWidth: 0
                strokeColor: "transparent"

                fillGradient: LinearGradient {
                    x1: ring.line.x1
                    y1: ring.line.y1
                    x2: ring.line.x2
                    y2: ring.line.y2

                    // One stop per color in the token, evenly spaced (theirs).
                    // Two is all any ported theme carries, but the grammar
                    // does not cap it.
                    GradientStop {
                        position: 0
                        color: Gradient.qmlColor(root.parsed.colors[0])
                    }
                    GradientStop {
                        position: 1
                        color: Gradient.qmlColor(root.parsed.colors[root.parsed.colors.length - 1])
                    }
                }

                PathRectangle {
                    width: root.width
                    height: root.height
                    radius: root.cornerRadius
                }

                // The hole. Its radius shrinks with the inset so the inner
                // corner stays concentric with the outer one.
                PathRectangle {
                    x: root.borderWidth
                    y: root.borderWidth
                    width: Math.max(0, root.width - root.borderWidth * 2)
                    height: Math.max(0, root.height - root.borderWidth * 2)
                    radius: Math.max(0, root.cornerRadius - root.borderWidth)
                }
            }
        }
    }
}

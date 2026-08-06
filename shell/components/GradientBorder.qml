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
// we need: a uniform width on all four sides. Callers feed `borderWidth` from
// their surface's `border-width` key (Theme.sWidth — [panel], [lock],
// [polkit], …), which is also a single uniform number. Their per-side widths
// (CSS-style "T R B L" lists, border-width-top/right/bottom/left keys) and
// the hand-rolled arc path builder that goes with them are not ported —
// no consumer here draws an uneven border.
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

            // One stop per color in the token, evenly spaced (theirs). Built
            // imperatively: the stop count follows the parsed spec, and a
            // static GradientStop pair would silently drop the middle colors
            // of a 3+-color token.
            readonly property var stopColors: root.parsed.colors
            onStopColorsChanged: rebuildStops()
            Component.onCompleted: rebuildStops()

            function rebuildStops() {
                const colors = stopColors || [];
                // Snapshot into a JS array: the stops property is a live view
                // of the list, so held across the reassignment below it would
                // enumerate the NEW stops and the cleanup would destroy them.
                const old = [];
                for (let i = 0; i < ringGradient.stops.length; i++)
                    old.push(ringGradient.stops[i]);
                const next = [];
                for (let i = 0; i < colors.length; i++)
                    next.push(stopComponent.createObject(ringGradient));
                ringGradient.stops = next;
                // Positions/colors are set once the stops are in the list:
                // appending alone does not emit the gradient's update signal,
                // a stop property change on a listed stop does.
                for (let i = 0; i < colors.length; i++) {
                    next[i].position = Gradient.stopPosition(colors.length, i);
                    next[i].color = Gradient.qmlColor(colors[i]);
                }
                // Replaced stops stay parented to the gradient until told
                // otherwise.
                for (let i = 0; i < old.length; i++)
                    old[i].destroy();
            }

            Component {
                id: stopComponent
                GradientStop {}
            }

            ShapePath {
                fillRule: ShapePath.OddEvenFill
                strokeWidth: 0
                strokeColor: "transparent"

                fillGradient: LinearGradient {
                    id: ringGradient
                    x1: ring.line.x1
                    y1: ring.line.y1
                    x2: ring.line.x2
                    y2: ring.line.y2
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

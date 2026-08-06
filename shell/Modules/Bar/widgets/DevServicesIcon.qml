import QtQuick
import QtQuick.Shapes

// A small database-cylinder mark, drawn with QtQuick.Shapes like the Dropbox
// tiles and the iCloud cloud rather than typeset — there is no brand glyph to
// borrow and the bar's fonts carry no emoji. Stroke-only: a full elliptical
// lid, the two walls around the bottom bulge, and one separator band, which
// is as much ink as reads at 13 px.
Item {
    id: root

    property real iconSize: 13
    property color color: "white"

    readonly property real strokeW: Math.max(1, iconSize / 9)
    // Half-stroke inset keeps the outline inside the item's bounds.
    readonly property real inset: strokeW / 2
    readonly property real lidRy: iconSize * 0.17
    readonly property real rx: width / 2 - inset

    width: iconSize * 0.92
    height: iconSize
    implicitWidth: iconSize * 0.92
    implicitHeight: iconSize

    Shape {
        anchors.fill: parent
        antialiasing: true
        layer.enabled: true
        layer.samples: 4

        // The lid: a full ellipse, in two arcs.
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.strokeW
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: root.inset
            startY: root.lidRy + root.inset
            PathArc {
                x: root.width - root.inset
                y: root.lidRy + root.inset
                radiusX: root.rx
                radiusY: root.lidRy
            }
            PathArc {
                x: root.inset
                y: root.lidRy + root.inset
                radiusX: root.rx
                radiusY: root.lidRy
            }
        }

        // The body: down the left wall, around the bottom bulge, up the right.
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.strokeW
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: root.inset
            startY: root.lidRy + root.inset
            PathLine {
                x: root.inset
                y: root.height - root.lidRy - root.inset
            }
            PathArc {
                x: root.width - root.inset
                y: root.height - root.lidRy - root.inset
                radiusX: root.rx
                radiusY: root.lidRy
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.width - root.inset
                y: root.lidRy + root.inset
            }
        }

        // The separator band across the middle.
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.strokeW
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: root.inset
            startY: root.height * 0.55
            PathArc {
                x: root.width - root.inset
                y: root.height * 0.55
                radiusX: root.rx
                radiusY: root.lidRy
                direction: PathArc.Counterclockwise
            }
        }
    }
}

import QtQuick
import QtQuick.Shapes

// A dashed rule along the top, or a dashed frame, as Blueprint draws its rules and done cards.
Shape {
    id: dashed

    property color color: "black"
    property bool frame: false

    preferredRendererType: Shape.GeometryRenderer

    ShapePath {
        strokeColor: dashed.color
        strokeWidth: 1
        strokeStyle: ShapePath.DashLine
        dashPattern: [4, 3]
        fillColor: "transparent"

        PathPolyline {
            path: dashed.frame ? [Qt.point(0.5, 0.5), Qt.point(dashed.width - 0.5, 0.5), Qt.point(dashed.width - 0.5, dashed.height - 0.5), Qt.point(0.5, dashed.height - 0.5), Qt.point(0.5, 0.5)] : [Qt.point(0, 0.5), Qt.point(dashed.width, 0.5)]
        }
    }
}

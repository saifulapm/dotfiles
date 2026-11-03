import QtQuick
import QtQuick.Shapes

// One of the Files boards' line icons, a path drawn in a square box (16 units, or 9 for Artboard's tick) scaled to its size.
Shape {
    id: icon

    property string path: ""
    property color color: "black"
    property real stroke: 1.3
    property real box: 16
    property real size: 16

    implicitWidth: size
    implicitHeight: size
    // The geometry renderer kept a stroke colour from before the theme's tokens arrived (YouTube's magnifier stayed its fallback), so a new colour rebuilds the path.
    onColorChanged: {
        svg.path = "";
        svg.path = Qt.binding(() => icon.path);
    }
    // The curve renderer drew nothing for the trash path at Artboard's 1.5 stroke; the geometry renderer draws every path.
    preferredRendererType: Shape.GeometryRenderer

    ShapePath {
        strokeColor: icon.color
        strokeWidth: icon.stroke
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        scale: Qt.size(icon.size / icon.box, icon.size / icon.box)
        PathSvg {
            id: svg
            path: icon.path
        }
    }
}

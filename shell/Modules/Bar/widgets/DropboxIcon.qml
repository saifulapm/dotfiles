import QtQuick
import QtQuick.Shapes

// The Dropbox mark, ported from omarchy's DropboxIcon.qml: five
// diamond tiles drawn with QtQuick.Shapes — four across two rows and one
// centered below. Drawn rather than typeset, so it needs no brand glyph in the
// icon font (the FontAwesome and Devicons ranges the upstream login row used
// do not render under our Symbols Nerd Font fallback).
Item {
    id: root

    property real iconSize: 13
    property color color: "white"

    width: iconSize * 1.18
    height: iconSize
    implicitWidth: iconSize * 1.18
    implicitHeight: iconSize

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        scale: 0.95

        Tile {
            cx: root.width * 0.25
            cy: root.height * 0.188
        }
        Tile {
            cx: root.width * 0.75
            cy: root.height * 0.188
        }
        Tile {
            cx: root.width * 0.25
            cy: root.height * 0.564
        }
        Tile {
            cx: root.width * 0.75
            cy: root.height * 0.564
        }
        Tile {
            cx: root.width * 0.50
            cy: root.height * 0.812
        }
    }

    component Tile: ShapePath {
        property real cx: 0
        property real cy: 0
        readonly property real tileWidth: root.width * 0.50
        readonly property real tileHeight: root.height * 0.376

        fillColor: root.color
        strokeWidth: 0
        startX: cx
        startY: cy - tileHeight / 2
        PathLine {
            x: cx + tileWidth / 2
            y: cy
        }
        PathLine {
            x: cx
            y: cy + tileHeight / 2
        }
        PathLine {
            x: cx - tileWidth / 2
            y: cy
        }
        PathLine {
            x: cx
            y: cy - tileHeight / 2
        }
    }
}

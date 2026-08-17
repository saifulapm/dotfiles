import QtQuick
import QtQuick.Shapes

// The Cloudflare mark, ported from tobi/omarchy-warp's WarpIcon.qml:
// the cloud silhouette drawn from primitives on a viewBox
// normalized to 1×1, with two trailing speed lines so it reads as "cloud,
// moving" rather than as a weather glyph. Drawn rather than typeset or loaded
// from an SVG, for the reasons TailscaleIcon.qml gives — no brand glyph
// survives our Symbols Nerd Font fallback, and a tiny SVG rasterizes badly in a
// 13 px bar slot.
//
// Reshaped to this repo's icon contract, which is the same divergence
// TailscaleIcon carries: nothing here reaches for a theme. Every colour, the
// badge ring and the badge font arrive as properties, so one component serves
// the bar mark and the panel header without knowing which is asking. Their
// version reads Color.foreground, Color.urgent, Color.popups.background and
// Style.font.family straight out of the singletons, and their badge is a
// BorderSurface we do not have.
Item {
    id: root

    property real iconSize: 13
    property color color: "white"
    property color badgeColor: "red"
    // The badge punches a hole in the mark with a ring of the surface behind it
    // and prints its glyph in that same colour; both are the caller's to supply.
    property color badgeBorderColor: "black"
    property color badgeTextColor: "black"
    property string fontFamily: ""
    property bool crossed: false
    property bool warning: false

    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    Shape {
        anchors.fill: parent
        antialiasing: true
        layer.enabled: true
        layer.samples: 4
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeWidth: 0

            // Flat bottom, a tall lobe left and a small one right — Cloudflare's
            // cloud proportions.
            startX: root.width * 0.20
            startY: root.height * 0.72

            PathLine {
                x: root.width * 0.86
                y: root.height * 0.72
            }
            PathCubic {
                x: root.width * 0.86
                y: root.height * 0.44
                control1X: root.width * 1.00
                control1Y: root.height * 0.70
                control2X: root.width * 1.00
                control2Y: root.height * 0.46
            }
            PathCubic {
                x: root.width * 0.63
                y: root.height * 0.40
                control1X: root.width * 0.80
                control1Y: root.height * 0.40
                control2X: root.width * 0.72
                control2Y: root.height * 0.38
            }
            PathCubic {
                x: root.width * 0.24
                y: root.height * 0.50
                control1X: root.width * 0.52
                control1Y: root.height * 0.14
                control2X: root.width * 0.26
                control2Y: root.height * 0.20
            }
            PathCubic {
                x: root.width * 0.20
                y: root.height * 0.72
                control1X: root.width * 0.06
                control1Y: root.height * 0.54
                control2X: root.width * 0.04
                control2Y: root.height * 0.70
            }
        }
    }

    // The speed lines go with the tunnel: nothing is moving while it is off.
    Column {
        anchors.left: parent.left
        anchors.leftMargin: -root.iconSize * 0.06
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.iconSize * 0.06
        spacing: Math.max(1, root.iconSize * 0.11)
        opacity: root.crossed ? 0.0 : 0.55
        visible: opacity > 0

        Rectangle {
            width: root.iconSize * 0.20
            height: Math.max(1, root.iconSize * 0.08)
            radius: height / 2
            color: root.color
        }

        Rectangle {
            width: root.iconSize * 0.13
            height: Math.max(1, root.iconSize * 0.08)
            radius: height / 2
            color: root.color
        }
    }

    Rectangle {
        visible: root.crossed
        anchors.centerIn: parent
        width: parent.width * 1.22
        height: Math.max(2, parent.height * 0.14)
        radius: height / 2
        color: root.color
        rotation: -45
    }

    Rectangle {
        id: badge

        visible: root.warning
        width: height
        height: Math.max(7, parent.height * 0.42)
        radius: height / 2
        color: root.badgeColor
        border.width: 1
        border.color: root.badgeBorderColor
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Text {
            anchors.centerIn: parent
            text: "!"
            color: root.badgeTextColor
            font.family: root.fontFamily
            font.pixelSize: Math.max(6, badge.height * 0.72)
            font.bold: true
        }
    }
}

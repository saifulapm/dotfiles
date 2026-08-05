import QtQuick

// The Tailscale mark, ported from omarchy's TailscaleIcon.qml (CREDITS.md):
// the official silhouette drawn as a 3×3 grid of dots with the six inactive
// ones faded to 0.24, rather than typeset or loaded from an SVG. Drawn, so it
// needs no brand glyph in the icon font (the FontAwesome, Devicons and Codicon
// ranges do not render under our Symbols Nerd Font fallback) and no tiny-SVG
// rasterising in a 13 px bar slot.
//
// Two overlays carry the state, as theirs do: a slash across the mark while
// Tailscale is off, and a badge in the bottom-right corner while the device
// still has to be authorized.
Item {
    id: root

    property real iconSize: 13
    property color color: "white"
    property color badgeColor: "red"
    // Their badge punches a hole in the mark with a ring of the panel
    // background, and prints the "!" in the background color; both are the
    // caller's to supply here, since this component knows nothing of a theme.
    property color badgeBorderColor: "black"
    property color badgeTextColor: "black"
    property string fontFamily: ""
    property bool crossed: false
    property bool warning: false

    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    readonly property real dotSize: Math.max(2, root.iconSize * 0.24)
    readonly property real mid: (root.iconSize - dotSize) / 2
    readonly property real end: root.iconSize - dotSize

    Dot {
        x: 0
        y: 0
        opacity: 0.24
    }
    Dot {
        x: root.mid
        y: 0
        opacity: 0.24
    }
    Dot {
        x: root.end
        y: 0
        opacity: 0.24
    }
    Dot {
        x: 0
        y: root.mid
        opacity: 1.0
    }
    Dot {
        x: root.mid
        y: root.mid
        opacity: 1.0
    }
    Dot {
        x: root.end
        y: root.mid
        opacity: 1.0
    }
    Dot {
        x: 0
        y: root.end
        opacity: 0.24
    }
    Dot {
        x: root.mid
        y: root.end
        opacity: 1.0
    }
    Dot {
        x: root.end
        y: root.end
        opacity: 0.24
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
        visible: root.warning
        width: Math.max(7, parent.width * 0.42)
        height: width
        radius: width / 2
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
            font.pixelSize: Math.max(6, parent.height * 0.72)
            font.bold: true
        }
    }

    component Dot: Rectangle {
        width: root.dotSize
        height: root.dotSize
        radius: width / 2
        color: root.color
    }
}

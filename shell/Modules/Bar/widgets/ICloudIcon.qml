import QtQuick
import "../components"

// The iCloud mark. Typeset rather than drawn: md-apple_icloud (U+F0038) sits
// in the Material Design range, the one range that actually renders under our
// Symbols Nerd Font fallback — verified by ink, not by fc-list (an offscreen
// render of the glyph next to a FontAwesome control showed real coverage where
// the control drew nothing). So unlike the Dropbox and Tailscale marks there
// is nothing to draw with Shapes here.
//
// The "!" badge is TailscaleIcon's: a corner disc ringed with the bar's own
// background so it reads as a hole punched in the mark, raised while the last
// network probe failed — an expired Apple session is the usual reason, and
// the panel carries the command that fixes it.
Item {
    id: root

    property real iconSize: 13
    property color color: "white"
    property bool warning: false
    property color badgeColor: "red"
    property color badgeBorderColor: "black"
    property color badgeTextColor: "black"
    property string fontFamily: ""

    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    OpticalGlyph {
        anchors.centerIn: parent
        text: "󰀸" // md-apple_icloud
        color: root.color
        pixelSize: Math.round(root.iconSize)
    }

    Rectangle {
        id: badge

        visible: root.warning
        width: Math.max(height, badgeLabel.implicitWidth + 3)
        height: Math.max(7, parent.height * 0.42)
        radius: height / 2
        color: root.badgeColor
        border.width: 1
        border.color: root.badgeBorderColor
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: "!"
            color: root.badgeTextColor
            font.family: root.fontFamily
            font.pixelSize: Math.max(6, badge.height * 0.72)
            font.bold: true
        }
    }
}

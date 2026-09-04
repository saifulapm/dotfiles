import QtQuick
import "../../../components"

// The mark of an rclone-remote widget, chosen by the instance: typeset when
// the instance names a glyph (iCloud's md-apple_icloud U+F0038 — the Material
// Design range is the one that renders under our Symbols Nerd Font fallback,
// verified by ink), or drawn when it names `drawnMark: "dropbox"` — the
// five-tile Dropbox mark (DropboxIcon.qml, omarchy's QtQuick.Shapes drawing)
// shared with the daemon-backed dropbox widget rather than redrawn here. The
// drawn mark sits behind a Loader so an instance that typesets never pays for
// a Shape and its render layer.
//
// The "!" badge is TailscaleIcon's: a corner disc ringed with the bar's own
// background so it reads as a hole punched in the mark, raised while the last
// network probe failed — an expired session being the usual reason, and the
// panel carries the command that fixes it.
Item {
    id: root

    property real iconSize: 13
    // Optical compensation for short-ink glyphs (BarIcon.glyphScale's twin).
    property real glyphScale: 1
    property color color: "white"
    property string glyph: ""
    property string drawnMark: ""
    property bool warning: false
    property color badgeColor: "red"
    property color badgeBorderColor: "black"
    property color badgeTextColor: "black"
    property string fontFamily: ""

    readonly property bool drawn: glyph === "" && drawnMark === "dropbox"

    width: implicitWidth
    height: implicitHeight
    // The Dropbox tiles are wider than tall, as DropboxIcon sizes itself.
    implicitWidth: drawn ? iconSize * 1.18 : iconSize
    implicitHeight: iconSize

    // Passed through to the glyph so the bar widget can pin its mark to the
    // bar's foregroundAnimationEnabled; the panel's hero keeps the default.
    property bool colorAnimationEnabled: true

    OpticalGlyph {
        visible: !root.drawn
        anchors.centerIn: parent
        text: root.glyph
        color: root.color
        pixelSize: Math.round(root.iconSize * root.glyphScale)
        verticalInkCenter: true
        colorAnimationEnabled: root.colorAnimationEnabled
    }

    Loader {
        active: root.drawn
        anchors.fill: parent
        sourceComponent: DropboxIcon {
            iconSize: root.iconSize
            color: root.color
        }
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
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "!"
            color: root.badgeTextColor
            font.family: root.fontFamily
            font.pixelSize: Math.max(6, badge.height * 0.72)
            font.bold: true
        }
    }
}

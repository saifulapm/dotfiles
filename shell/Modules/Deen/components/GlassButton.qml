import QtQuick
import QtQuick.Controls

// Modules/Dekho/components/GlassButton.qml, which is itself omakade's
// (github.com/tsouth89/omakade, GPL-3.0) line for line.
//
// Every control in this module is one of these. Before it, every Button, chip
// and grade key here was a bare QtQuick.Controls default drawing itself in
// Fusion's palette — which is why the hub read as a settings form rather than
// as part of this desktop, and it is the same verdict Dekho's doc §10 records
// against its own first version.
//
// The alpha ladder is the whole visual identity and is copied rather than
// approximated: 0.045 at rest, 0.12 selected, 0.18 primary, 0.14 hovered-or-
// focused, 0.24 pressed, over a border that goes accent the moment the item
// has the keyboard.
//
// COPIED, NOT IMPORTED FROM DEKHO. The two hubs share a look and nothing else:
// a cross-module `import "../Dekho/components"` would make the Islamic hub
// break when the movie hub retunes a chip, and these will diverge (this one
// grows `tone` below, which films have no use for). Bar/components and
// shell/components already sit side by side in this tree for the same reason.
//
// The literals are omakade's, at omakade's 1380x880 window. See Style.qml for
// why they go through ui() and type() rather than being retuned.
Button {
    id: root

    required property var style
    property string iconText: ""
    property bool primary: false
    property bool selected: false
    property bool compact: false

    // Which colour the lit states use. omakade has only the accent; the grade
    // keys here mean four different things about the same recitation, and a row
    // of four identical chips is a row you have to read before you can press.
    property color tone: root.style.accent

    // A button with a glyph and no words is square. omakade has no such button
    // — every one of its controls is labelled — but this hub's steppers are ◀
    // and ▶, and 76 px of minimum width around a 12 px arrow reads as a button
    // that lost its text.
    readonly property bool iconOnly: root.text.length === 0 && root.iconText.length > 0

    implicitHeight: root.compact ? root.style.ui(34) : root.style.ui(42)
    implicitWidth: root.iconOnly ? root.implicitHeight : Math.max(root.compact ? root.style.ui(76) : root.style.ui(104), contentRow.implicitWidth + (root.compact ? root.style.ui(22) : root.style.ui(30)))
    leftPadding: root.compact ? root.style.ui(11) : root.style.ui(15)
    rightPadding: root.leftPadding
    spacing: root.style.ui(8)
    focusPolicy: Qt.StrongFocus

    background: Rectangle {
        radius: root.style.radiusSm
        color: root.down ? root.style.alpha(root.primary ? root.tone : root.style.fg, 0.24) : root.hovered || root.activeFocus ? root.style.alpha(root.primary ? root.tone : root.style.fg, 0.14) : root.primary ? root.style.alpha(root.tone, 0.18) : root.selected ? root.style.alpha(root.style.fg, 0.12) : root.style.alpha(root.style.fg, 0.045)
        // omakade's 2 and 1. Doubling the hairline rather than writing a bare
        // 2 keeps the ring visible on this window, where a control is 80 px
        // tall and a single physical pixel of accent is not a focus cue.
        border.width: root.activeFocus ? root.style.ui(2) : root.style.hairline
        border.color: root.activeFocus ? root.tone : root.primary ? root.style.alpha(root.tone, 0.58) : root.style.alpha(root.style.fg, root.hovered ? 0.32 : 0.16)

        // omakade gates these on Preferences.reducedMotion; here the theme's
        // own motion.duration does that job for the whole desktop at once —
        // see Style.qml's motion section.
        Behavior on color {
            ColorAnimation {
                duration: root.style.normal
                easing.type: root.style.easing
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: root.style.normal
                easing.type: root.style.easing
            }
        }
    }

    contentItem: Row {
        id: contentRow

        spacing: root.spacing
        anchors.centerIn: parent

        Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconText.length > 0
            text: root.iconText
            color: root.enabled ? (root.primary ? root.style.brightFg : root.style.fg) : root.style.alpha(root.style.fg, 0.35)
            font.family: root.style.fontFamily
            font.pixelSize: root.compact ? root.style.type(12) : root.style.type(14)
        }

        Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text.length > 0
            text: root.text
            color: root.enabled ? (root.primary ? root.style.brightFg : root.style.fg) : root.style.alpha(root.style.fg, 0.35)
            font.family: root.style.fontFamily
            font.pixelSize: root.compact ? root.style.type(11) : root.style.type(12)
            font.weight: root.primary || root.selected ? Font.DemiBold : Font.Medium
        }
    }
}

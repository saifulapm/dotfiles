import QtQuick
import QtQuick.Controls

// omakade's qml/components/GlassButton.qml, line for line.
//
// Every control on every screen of this module is one of these — the mode
// chips, the kind chips, the sort cycler, the filter cycler, PLAY, the season
// chips, the genre buttons. omakade's whole visual identity is in the alpha
// ladder below, so it is copied rather than approximated: 0.045 at rest, 0.12
// selected, 0.18 primary, 0.14 hovered-or-focused, 0.24 pressed, over a border
// that goes accent the moment the item has the keyboard.
//
// It is a real QtQuick.Controls Button, which is the point. The module used to
// hand-roll its chips because a focused TextInput ate Left and Right (doc §6's
// key catcher), and none of them could be tabbed to. This one carries
// focusPolicy, hovered, down, activeFocus and the Qt focus chain for free —
// which is what `nextItemInFocusChain` walks in Dekho.qml's focus helpers.
//
// The literals are omakade's, at omakade's 1380x880. See Style.qml for why they
// go through ui() and type() rather than being retuned.
Button {
    id: root

    required property var style
    property string iconText: ""
    property bool primary: false
    property bool selected: false
    property bool compact: false

    implicitHeight: root.compact ? root.style.ui(34) : root.style.ui(42)
    implicitWidth: Math.max(root.compact ? root.style.ui(76) : root.style.ui(104), contentRow.implicitWidth + (root.compact ? root.style.ui(22) : root.style.ui(30)))
    leftPadding: root.compact ? root.style.ui(11) : root.style.ui(15)
    rightPadding: root.leftPadding
    spacing: root.style.ui(8)
    focusPolicy: Qt.StrongFocus

    background: Rectangle {
        radius: root.style.radiusSm
        color: root.down ? root.style.alpha(root.primary ? root.style.accent : root.style.fg, 0.24) : root.hovered || root.activeFocus ? root.style.alpha(root.primary ? root.style.accent : root.style.fg, 0.14) : root.primary ? root.style.alpha(root.style.accent, 0.18) : root.selected ? root.style.alpha(root.style.fg, 0.12) : root.style.alpha(root.style.fg, 0.045)
        // omakade's 2 and 1. Doubling the hairline rather than writing a bare
        // 2 keeps the ring visible on this window, where a control is 80 px
        // tall and a single physical pixel of accent is not a focus cue.
        border.width: root.activeFocus ? root.style.ui(2) : root.style.hairline
        border.color: root.activeFocus ? root.style.accent : root.primary ? root.style.alpha(root.style.accent, 0.58) : root.style.alpha(root.style.fg, root.hovered ? 0.32 : 0.16)

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
            text: root.text
            color: root.enabled ? (root.primary ? root.style.brightFg : root.style.fg) : root.style.alpha(root.style.fg, 0.35)
            font.family: root.style.fontFamily
            font.pixelSize: root.compact ? root.style.type(11) : root.style.type(12)
            font.weight: root.primary || root.selected ? Font.DemiBold : Font.Medium
        }
    }
}

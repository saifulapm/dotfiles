import QtQuick

// Omarchy's ToggleSwitch: a track with a knob, cursor-aware, `busy` dimming
// it while a change is in flight, `compact` for rows where the full-size
// track would compete with the content.
Rectangle {
    id: toggle

    required property var theme
    property bool checked: false
    property bool hasCursor: false
    property bool busy: false
    property bool compact: false
    property string hint: ""

    signal hovered
    signal toggled

    implicitWidth: compact ? theme.space(7) : theme.space(10)
    implicitHeight: compact ? theme.space(4) : theme.space(5.5)
    radius: height / 2
    color: checked ? theme.accent : theme.surface3
    border.width: theme.borderWidth
    border.color: toggle.hasCursor ? theme.accent : "transparent"
    opacity: toggle.busy ? 0.6 : 1

    Behavior on color {
        ColorAnimation {
            duration: toggle.theme.time(0.5)
        }
    }

    Rectangle {
        y: (parent.height - height) / 2
        x: toggle.checked ? parent.width - width - (parent.height - height) / 2 : (parent.height - height) / 2
        width: parent.height - toggle.theme.space(1.5)
        height: width
        radius: width / 2
        color: toggle.checked ? toggle.theme.textOnAccent : toggle.theme.textMuted

        Behavior on x {
            NumberAnimation {
                duration: toggle.theme.time(0.5)
                easing.type: toggle.theme.easing
            }
        }
    }

    HoverHandler {
        id: toggleHover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered)
            toggle.hovered()
    }

    TapHandler {
        onTapped: toggle.toggled()
    }

    PanelHint {
        theme: toggle.theme
        visible: toggleHover.hovered && toggle.hint !== ""
        anchor: toggle
        text: toggle.hint
    }
}

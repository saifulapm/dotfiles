import QtQuick

// Small bordered action button for panel cards, house style.
Rectangle {
    id: button

    required property var theme
    property string label: ""
    property bool selected: false
    property bool enabled: true

    signal clicked

    implicitWidth: text.implicitWidth + theme.space(4)
    implicitHeight: theme.space(7)
    radius: theme.radius(0.75)
    color: selected ? theme.alpha(theme.accent, 0.25) : (hover.hovered && enabled ? theme.alpha(theme.textPrimary, 0.08) : theme.surface2)
    border.width: theme.borderWidth
    border.color: selected ? theme.accent : theme.surface3
    opacity: enabled ? 1 : 0.45

    StyledText {
        id: text
        theme: button.theme
        anchors.centerIn: parent
        text: button.label
        role: StyledText.Body
        color: button.selected ? button.theme.accent : button.theme.textPrimary
    }

    HoverHandler {
        id: hover
        cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: button.enabled
        onTapped: button.clicked()
    }
}

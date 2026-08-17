import QtQuick

// Small bordered action button for panel cards, house style — the labelled
// member of the ChipSurface family. The surface (the accent wash when
// selected, the hover lift, the dim when disabled, and now the transitions
// between them) is ChipSurface's; this adds a centered label and a tap.
ChipSurface {
    id: button

    property string label: ""
    property bool selected: false
    property bool enabled: true

    signal clicked

    implicitWidth: text.implicitWidth + theme.space(4)
    implicitHeight: theme.space(7)

    chosen: button.selected
    // A button has no keyboard cursor of its own, so the outline follows the
    // selection alone — which is what the open-coded border said.
    pointerOver: hover.hovered && button.enabled
    interactive: button.enabled

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

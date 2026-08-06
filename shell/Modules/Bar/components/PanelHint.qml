import QtQuick

// Omarchy's PanelToolTip, kept inside the card: the bar's tooltips belong to
// the bar window, which a panel is not. Reparents itself under `anchor` and
// hangs off its bottom-right corner.
Rectangle {
    id: hintBox

    required property var theme
    property Item anchor: null
    property string text: ""

    parent: hintBox.anchor
    anchors.right: hintBox.anchor ? hintBox.anchor.right : undefined
    anchors.top: hintBox.anchor ? hintBox.anchor.bottom : undefined
    anchors.topMargin: theme.space(1)
    width: hintLabel.implicitWidth + theme.space(3)
    height: hintLabel.implicitHeight + theme.space(2)
    radius: theme.radius(0.75)
    color: theme.surface2
    border.width: theme.borderWidth
    border.color: theme.surface3
    z: 10

    Text {
        id: hintLabel
        anchors.centerIn: parent
        text: hintBox.text
        color: hintBox.theme.textPrimary
        font.family: hintBox.theme.fontUi
        font.pixelSize: hintBox.theme.fontPx(0.833)
    }
}

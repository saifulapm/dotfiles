import QtQuick

// Omarchy's PanelToolTip, kept inside the card: the bar's tooltips belong to
// the bar window, which a panel is not. Reparents itself under `anchor` and
// hangs off its bottom-right corner — or off the top-right one with `above`,
// for anchors near the card's bottom edge where the default would land on
// the next row's controls (and be painted over by them: a later sibling row
// stacks above an earlier row's children, whatever this z says).
Rectangle {
    id: hintBox

    required property var theme
    property Item anchor: null
    property string text: ""
    property bool above: false

    parent: hintBox.anchor
    anchors.right: hintBox.anchor ? hintBox.anchor.right : undefined
    anchors.top: !hintBox.above && hintBox.anchor ? hintBox.anchor.bottom : undefined
    anchors.bottom: hintBox.above && hintBox.anchor ? hintBox.anchor.top : undefined
    anchors.topMargin: theme.space(1)
    anchors.bottomMargin: theme.space(1)
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

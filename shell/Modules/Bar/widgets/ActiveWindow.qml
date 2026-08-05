import QtQuick

Item {
    id: rootItem

    required property var theme
    required property var niri
    property int maxWidth: 420

    implicitWidth: Math.min(label.implicitWidth, maxWidth)
    implicitHeight: parent ? parent.height : label.implicitHeight
    visible: rootItem.niri.focusedTitle !== ""

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, rootItem.maxWidth)
        elide: Text.ElideRight
        color: rootItem.theme.textMuted
        font.family: rootItem.theme.fontUi
        font.pixelSize: rootItem.theme.fontPx(0.917)
        text: rootItem.niri.focusedTitle
    }
}

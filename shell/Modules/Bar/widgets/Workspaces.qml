import QtQuick

Item {
    id: rootItem

    required property var theme
    required property var niri
    property string screenName: ""

    readonly property var shown: niri.workspaces.filter(w => screenName === "" || w.output === screenName)

    implicitWidth: row.implicitWidth
    implicitHeight: parent ? parent.height : row.implicitHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: rootItem.theme.space(1)

        Repeater {
            model: rootItem.shown

            delegate: Rectangle {
                id: pill

                required property var modelData

                width: Math.max(height, wsLabel.implicitWidth + rootItem.theme.space(3))
                height: rootItem.theme.barHeight - rootItem.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                radius: rootItem.theme.radius(0.5)
                color: modelData.is_active ? rootItem.theme.alpha(rootItem.theme.accent, 0.25) : (hover.hovered ? rootItem.theme.alpha(rootItem.theme.textPrimary, 0.08) : "transparent")
                border.width: modelData.is_urgent ? rootItem.theme.borderWidth : 0
                border.color: rootItem.theme.error

                Behavior on color {
                    ColorAnimation {
                        duration: rootItem.theme.time(0.6)
                        easing.type: rootItem.theme.easing
                    }
                }

                Text {
                    id: wsLabel
                    anchors.centerIn: parent
                    color: pill.modelData.is_active ? rootItem.theme.accent : rootItem.theme.textMuted
                    font.family: rootItem.theme.fontMono
                    font.pixelSize: rootItem.theme.fontPx(0.917)
                    text: pill.modelData.name || pill.modelData.idx
                }

                HoverHandler {
                    id: hover
                }

                TapHandler {
                    onTapped: rootItem.niri.focusWorkspace(pill.modelData.id)
                }
            }
        }
    }
}

import QtQuick
import "../components"

// Omarchy-style workspaces: the focused one is a filled circle glyph, the
// rest show their number; empty workspaces sit at half strength; urgent
// turns the attention color. 20 px slots, chrome-less.
Item {
    id: rootItem

    required property var theme
    required property var niri
    property var bar: null
    property string screenName: ""

    readonly property var shown: niri.workspaces.filter(w => screenName === "" || w.output === screenName)

    implicitWidth: row.implicitWidth
    implicitHeight: parent ? parent.height : row.implicitHeight

    Row {
        id: row
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 1

        Repeater {
            model: rootItem.shown

            delegate: BarButton {
                id: wsButton

                required property var modelData

                theme: rootItem.theme
                bar: rootItem.bar
                fixedWidth: 20
                active: modelData.is_urgent === true
                opacity: modelData.is_active || modelData.active_window_id !== null ? 1 : 0.5

                onTapped: rootItem.niri.focusWorkspace(wsButton.modelData.id)

                OpticalGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: wsButton.modelData.is_active === true
                    text: "󱓻" // md-circle_medium, omarchy's focused marker
                    color: wsButton.contentColor
                    pixelSize: 13
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: wsButton.modelData.is_active !== true
                    text: wsButton.modelData.name || wsButton.modelData.idx
                    color: wsButton.contentColor
                    font.family: rootItem.theme.fontMono
                    font.pixelSize: rootItem.theme.fontPx(1.0)
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}

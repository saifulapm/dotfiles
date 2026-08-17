import QtQuick
import Quickshell.Services.SystemTray
import "../components"
import "../../../components"

// Tray manage card — omarchy's tray manage popup in our tokens. Lists every
// item the tray knows about, including hidden ones and the passive items the
// bar itself never shows, with Pin / Hide toggles that rewrite the widget's
// persisted id lists.
BarPanel {
    id: panel

    property var tray: null

    readonly property var items: tray ? tray.manageItems : []

    panelTitle: "Tray icons"

    Text {
        width: parent.width
        text: "Pinned icons stay on the bar. Hidden icons never show. Everything else lives in the drawer."
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.833)
        wrapMode: Text.WordWrap
    }

    Text {
        visible: panel.items.length === 0
        text: "No tray items reporting."
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.917)
        font.italic: true
    }

    Repeater {
        model: panel.items

        delegate: Item {
            id: row

            required property var modelData

            readonly property string itemId: String(modelData.id || "")
            readonly property bool isPinned: panel.tray && panel.tray.pinnedIds.indexOf(itemId) !== -1
            readonly property bool isHidden: panel.tray && panel.tray.hiddenIds.indexOf(itemId) !== -1
            // Passive items are listed so they can be pinned ahead of time,
            // but they are dimmed: their app is not asking to be seen.
            readonly property bool passive: modelData.status === Status.Passive

            width: parent.width
            implicitHeight: panel.theme.space(7)
            opacity: passive ? 0.55 : 1

            TrayIcon {
                id: rowIcon

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                icon: row.modelData.icon
                tint: panel.theme.textPrimary
            }

            Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: hideButton.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: panel.tray ? panel.tray.displayName(row.modelData) : ""
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
                elide: Text.ElideRight
            }

            PanelButton {
                id: hideButton

                anchors.right: pinButton.left
                anchors.rightMargin: panel.theme.space(1.5)
                anchors.verticalCenter: parent.verticalCenter
                theme: panel.theme
                label: row.isHidden ? "Show" : "Hide"
                selected: row.isHidden
                onClicked: panel.tray.toggleHide(row.itemId)
            }

            PanelButton {
                id: pinButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                theme: panel.theme
                label: row.isPinned ? "Unpin" : "Pin"
                selected: row.isPinned
                onClicked: panel.tray.togglePin(row.itemId)
            }
        }
    }
}

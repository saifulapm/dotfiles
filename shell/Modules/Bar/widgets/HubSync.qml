import QtQuick
import "../components"
import "../../../components"
import "HubSyncModel.js" as Model

// Sync — the Dropbox hub's six units as one bar button, in the dufs/rclone
// widget shape.
//
// The mark is md-sync (U+F04E6). It carries the state the way the family
// does: full foreground while every unit is healthy, dimmed while nothing has
// synced yet, and the error color under a "!" badge the moment a unit fails —
// the badge being TailscaleIcon's recipe, a corner disc ringed in the bar's
// own background so it reads as a hole punched in the mark.
//
// The mark also TURNS while a round is in flight, whoever started it: the
// service watches status.json, and the 15-minute timer writes that file the
// same way the panel's own button does. So the bar shows a background sync
// happening without the shell having started or polled anything.
//
// Left click opens the panel, right click runs a full round.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // The shared service, injected by the bar's registry — ONE instance
    // however many screens carry this widget (S2).
    required property HubSyncService sync

    readonly property bool failing: sync.anyFailing
    readonly property bool healthy: !failing && sync.okCount > 0

    tooltipText: Model.tooltip(sync.status, sync.nowMs)

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("HubSyncPanel.qml", {
                theme: rootItem.theme,
                sync: rootItem.sync
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            sync.syncAll();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    Item {
        implicitWidth: 13
        implicitHeight: 13

        OpticalGlyph {
            id: mark

            anchors.centerIn: parent
            text: "󰓦" // md-sync
            pixelSize: 13
            verticalInkCenter: true
            color: rootItem.failing ? rootItem.theme.error : (rootItem.healthy ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55))
            opacity: rootItem.healthy || rootItem.failing ? 1.0 : 0.6
            colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true

            // Turns only while a round is actually in flight, so a spinning
            // mark always means work is happening somewhere.
            RotationAnimator on rotation {
                running: rootItem.sync.running
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1400
            }
            onRotationChanged: if (!rootItem.sync.running && rotation !== 0)
                rotation = 0
        }

        Rectangle {
            id: badge

            visible: rootItem.failing
            width: Math.max(height, badgeLabel.implicitWidth + 3)
            height: Math.max(7, parent.height * 0.42)
            radius: height / 2
            color: rootItem.theme.error
            border.width: 1
            border.color: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            Text {
                id: badgeLabel
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "!"
                color: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
                font.family: rootItem.theme.fontUi
                font.pixelSize: Math.max(6, badge.height * 0.72)
                font.bold: true
            }
        }
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    PanelLoader {
        id: panelLoader
    }
}

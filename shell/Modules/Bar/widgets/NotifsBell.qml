import QtQuick
import "../components"

// Notification bell — the history center's bar entry, in the dnd indicator's
// family (omarchy's bell pattern): lit with a count badge while unseen
// notifications wait, revealed-on-hover otherwise, click opens the center.
//
// Hosted inside the Indicators container the panel lives on the container
// (a bell copy in the active block is torn down when the last unseen entry
// clears, which must not take an open panel with it); standalone in a bar
// array the bell itself persists, so it owns its panel Loader.
BarIndicator {
    id: rootItem

    required property var notifs

    readonly property int unseen: notifs.pendingModel.count

    active: unseen > 0
    activeGlyph: "󰂚" // md-bell
    inactiveGlyph: "󰂚"
    activeTooltip: unseen + " unseen notification" + (unseen === 1 ? "" : "s")
    inactiveTooltip: "Notification History"

    // A standalone bell stays on the bar — it is the center's entry point,
    // not a pure status light like dnd: dimmed to the inactive-reveal
    // opacity while caught up, fully lit with the badge while unseen
    // notifications wait. Hosted copies keep the container's block rules.
    visible: indicatorBlock === "single" ? true : belongsInBlock
    opacity: !visible ? 0 : (effectiveActive ? 1 : (indicatorBlock === "single" || inactiveRevealed ? 0.45 : 0))
    enabled: visible && (indicatorBlock === "single" || effectiveActive || inactiveRevealed)

    onTapped: rootItem.openPanel()

    function openPanel() {
        if (rootItem.indicatorHost && typeof rootItem.indicatorHost.openNotifsPanel === "function") {
            rootItem.indicatorHost.openNotifsPanel(rootItem);
            return;
        }
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("NotifsPanel.qml", {
                theme: rootItem.theme,
                notifs: rootItem.notifs
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    // The IPC summon path for a standalone bell — reachable even while the
    // bell is collapsed (a hidden widget is skipped by summonWidget).
    function summonNotifCenter() {
        openPanel();
        return true;
    }

    // Unseen count in the glyph's corner — TailscaleIcon's badge recipe: a
    // pill in the accent color, ringed and printed in the bar background so
    // it reads as punched out of the bell. Reparented onto the button itself
    // (the PanelHint trick): children land in BarButton's content Row by
    // default, and a Row rejects horizontally-anchored items.
    Rectangle {
        id: badge
        parent: rootItem

        readonly property string label: rootItem.unseen > 9 ? "9+" : String(rootItem.unseen)

        visible: rootItem.unseen > 0
        width: Math.max(height, badgeLabel.implicitWidth + 3)
        height: 8
        radius: height / 2
        color: rootItem.theme.accent
        border.width: 1
        border.color: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        anchors.right: parent.right
        anchors.rightMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 5

        Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: badge.label
            color: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
            font.family: rootItem.theme.fontUi
            font.pixelSize: 6
            font.bold: true
        }
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

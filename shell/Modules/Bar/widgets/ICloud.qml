import QtQuick
import Quickshell
import "../components"

// iCloud — ours, in the visual language of the Dropbox widget (which is
// omarchy's design; CREDITS.md). The backend is rclone's iclouddrive remote
// rather than a vendor daemon, and the mark carries the state the way the
// Dropbox mark does: full foreground while the remote is mounted, dimmed
// while it is configured but unmounted, and a "!" badge while the last
// network probe failed — an expired Apple session being the usual reason.
//
// Left click opens the panel, right click runs the reachability probe (the
// one network call this widget ever makes unprompted-by-the-panel), middle
// click opens the mounted folder — the dropbox click map, with the middle
// slot holding the folder because there is no login flow to hold (re-auth is
// interactive Apple 2FA and lives in the panel as a copyable command).
//
// With no rclone on the machine, or no iCloud remote in its config, the
// widget takes no width and draws nothing: it answers one local probe (no
// network) and stays inert.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind a real rclone with an iCloud remote, and never
    // before the local probe has answered.
    visible: icloud.probed && icloud.installed && icloud.configured

    readonly property ICloudService icloud: ICloudService {
        settings: rootItem.settings
    }

    tooltipText: {
        if (icloud.lastProbeFailed)
            return "iCloud — unreachable (session expired?)";
        if (icloud.mounted)
            return "iCloud — mounted at " + icloud.mountPoint;
        return "iCloud — not mounted";
    }

    function openPanel() {
        panelLoader.active = true;
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            icloud.probe();
        else if (button === Qt.MiddleButton)
            icloud.openFolder();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    ICloudIcon {
        iconSize: 13
        color: rootItem.icloud.mountActive ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.icloud.mountActive ? 1.0 : 0.6
        warning: rootItem.icloud.lastProbeFailed
        badgeColor: rootItem.theme.error
        // The badge sits in a ring of the bar's own background, so it reads as
        // a hole punched in the mark (TailscaleIcon's recipe).
        badgeBorderColor: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        badgeTextColor: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        fontFamily: rootItem.theme.fontUi
    }

    LazyLoader {
        id: panelLoader
        active: false
        component: ICloudPanel {
            theme: rootItem.theme
            icloud: rootItem.icloud
        }
    }
}

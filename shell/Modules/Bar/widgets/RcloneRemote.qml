import QtQuick
import Quickshell
import "../components"

// rclone remote — ours, in the visual language of the Dropbox widget (which
// is omarchy's design; CREDITS.md), grown out of the iCloud widget: one
// shared component behind every rclone-backed cloud folder on the bar. Each
// registry id ("icloud", "dropbox-rclone", …) mounts this component with its
// own `defaults` — remote name, backend type, label, mountpoint, mark —
// which an inline shell.json settings entry may override key by key. The
// mark carries the state the way the Dropbox mark does: full foreground
// while the remote is mounted, dimmed while it is configured but unmounted,
// and a "!" badge while the last network probe failed — an expired session
// being the usual reason.
//
// Left click opens the panel, right click runs the network probe (the one
// call this widget ever makes unprompted-by-the-panel), middle click opens
// the mounted folder — the dropbox click map, with the middle slot holding
// the folder because there is no login flow to hold (re-auth is interactive
// and lives in the panel as a copyable command).
//
// With no rclone on the machine, or no matching remote in its config, the
// widget takes no width and draws nothing: it answers one local probe (no
// network) and stays inert. That is the correct state for an instance whose
// remote has simply not been `rclone config`ured yet.
BarButton {
    id: rootItem

    // Per-instance defaults, set where the registry mounts this component;
    // the inline settings entry overrides them key by key.
    property var defaults: ({})

    readonly property var config: {
        const merged = {};
        const base = rootItem.defaults || {};
        for (const key in base)
            merged[key] = base[key];
        const entry = rootItem.settings || {};
        for (const key in entry) {
            if (key !== "id")
                merged[key] = entry[key];
        }
        return merged;
    }

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind a real rclone with a matching remote, and
    // never before the local probe has answered.
    visible: service.probed && service.installed && service.configured

    readonly property RcloneRemoteService service: RcloneRemoteService {
        config: rootItem.config
    }

    tooltipText: {
        if (service.lastProbeFailed)
            return service.label + " — unreachable (session expired?)";
        if (service.mounted)
            return service.label + " — mounted at " + service.mountPoint;
        return service.label + " — not mounted";
    }

    function openPanel() {
        panelLoader.active = true;
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            service.probe();
        else if (button === Qt.MiddleButton)
            service.openFolder();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    RcloneRemoteMark {
        iconSize: 13
        glyph: String(rootItem.config.glyph || "")
        drawnMark: String(rootItem.config.drawnMark || "")
        color: rootItem.service.mountActive ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.service.mountActive ? 1.0 : 0.6
        warning: rootItem.service.lastProbeFailed
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
        component: RcloneRemotePanel {
            theme: rootItem.theme
            service: rootItem.service
        }
    }
}

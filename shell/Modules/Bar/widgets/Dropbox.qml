import QtQuick
import Quickshell
import "../components"

// Dropbox — port of omarchy's dropbox plugin bar button (CREDITS.md).
//
// The mark is their drawn DropboxIcon rather than a font glyph, and it carries
// the whole state the way theirs does: full foreground while an authenticated
// daemon is syncing, dimmed and darkened while it is paused, not logged in, or
// still starting. There is no separate syncing/error glyph upstream and there
// is none here — the daemon's own sentence ("Syncing 3 files…", "Up to date",
// "Dropbox isn't running!") is the tooltip, and errors surface in the panel.
//
// Left click opens the panel, right click runs a full refresh, middle click
// starts the login flow — their click map.
//
// With no Dropbox CLI on the machine the widget takes no width and draws
// nothing: it exists in the registry so `"dropbox"` can be added to a bar
// section, and stays inert everywhere it would have nothing to say. That is
// this machine's case, and every Asahi machine's — Dropbox publishes no
// aarch64 daemon (see packages/manifest.toml).
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind a real CLI, and never before the presence probe
    // has answered.
    visible: dropbox.probed && dropbox.installed

    readonly property DropboxService dropbox: DropboxService {
        settings: rootItem.settings
        // The refresh cadence is scoped to a widget that is actually on
        // screen; nothing ticks when the bar is not there to show it.
        pollingAllowed: rootItem.visible && rootItem.bar !== null
    }

    readonly property string statusLine: {
        const text = String(dropbox.statusText || "").split("\n")[0].trim();
        return text.length > 60 ? text.substring(0, 57) + "…" : text;
    }

    tooltipText: statusLine === "" ? "Dropbox" : "Dropbox — " + statusLine

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("DropboxPanel.qml", {
                theme: rootItem.theme,
                dropbox: rootItem.dropbox
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            dropbox.refreshDetails();
        else if (button === Qt.MiddleButton)
            dropbox.login();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    DropboxIcon {
        iconSize: 13
        color: rootItem.dropbox.authenticated && rootItem.dropbox.active ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.dropbox.active ? 1.0 : 0.6
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

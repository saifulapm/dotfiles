import QtQuick
import Quickshell
import "../components"

// Tailscale — port of omarchy's tailscale plugin bar button.
//
// The mark is their drawn TailscaleIcon rather than a font glyph, and it
// carries the three states theirs does: the plain mark in the bar foreground
// while the tailnet is up, the mark dimmed and struck through while it is
// down, and the mark with a red "!" badge while the device still has to be
// authorized. There is no syncing/error ladder upstream and none here — the
// backend's own word ("Connected", "Needs login", "Disconnected", "Starting")
// is the tooltip, and failures surface in the panel.
//
// Left click opens the panel, right click toggles Tailscale, middle click
// refreshes — their click map.
//
// With no tailscale CLI on the machine the widget takes no width, draws
// nothing and starts nothing after its one presence probe — the bar is
// byte-identical to a bar that never named it. Verified that way; tailscale is
// installed here (see packages/manifest.toml), so the probe says yes.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind a real CLI, and never before the presence probe
    // has answered.
    visible: tailscale.probed && tailscale.installed

    // The shared service, injected by the bar's registry — ONE instance
    // however many screens carry this widget (S2). Its settings and its
    // pollingAllowed gate (any bar visible, widget still in the layout) are
    // bound where it is created, at the bar root.
    required property TailscaleService tailscale

    tooltipText: {
        const base = "Tailscale — " + (tailscale.statusText === "" ? "Unknown" : tailscale.statusText);
        if (tailscale.receivePending > 0)
            return base + " · " + tailscale.receivePending + " file" + (tailscale.receivePending === 1 ? "" : "s") + " waiting in the Taildrop inbox";
        return base;
    }

    // Persist an inline shell.json setting for this widget (the panel's recent
    // Mullvad regions), merging over whatever the entry already carries.
    function persistSettings(values) {
        const entry = {
            id: "tailscale"
        };
        for (const key in settings) {
            if (key !== "id")
                entry[key] = settings[key];
        }
        for (const key in values)
            entry[key] = values[key];
        settings = entry;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
            bar.shell.updateEntryInline("tailscale", entry);
    }

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("TailscalePanel.qml", {
                theme: rootItem.theme,
                tailscale: rootItem.tailscale,
                widget: rootItem
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            tailscale.toggleTailscale();
        else if (button === Qt.MiddleButton)
            tailscale.refreshDetails(true);
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    TailscaleIcon {
        iconSize: 13
        color: rootItem.tailscale.active ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        crossed: !rootItem.tailscale.active && !rootItem.tailscale.needsLogin
        warning: rootItem.tailscale.needsLogin
        // Files sitting in the inbox with nothing collecting them. The healthy
        // loop empties it the instant anything lands, so this can only appear
        // while the receive service is stopped or backing off.
        badgeText: rootItem.tailscale.receivePending > 0 ? (rootItem.tailscale.receivePending > 9 ? "9+" : String(rootItem.tailscale.receivePending)) : ""
        badgeColor: rootItem.tailscale.needsLogin ? rootItem.theme.error : rootItem.theme.accent
        // The badge sits in a ring of the bar's own background, so it reads as
        // a hole punched in the mark rather than a ninth dot.
        badgeBorderColor: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        badgeTextColor: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        fontFamily: rootItem.theme.fontUi
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

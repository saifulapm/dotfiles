import QtQuick
import Quickshell
import "../components"

// Tailscale — port of omarchy's tailscale plugin bar button (CREDITS.md).
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

    fixedWidth: 27

    // Only ever visible behind a real CLI, and never before the presence probe
    // has answered.
    visible: tailscale.probed && tailscale.installed
    // A hidden widget must not leave its slot behind: the bar's WidgetSlot
    // sizes itself from implicitWidth, so an invisible 27 px button would hold
    // a 27 px hole open in the section.
    implicitWidth: visible ? fixedWidth : 0

    readonly property TailscaleService tailscale: TailscaleService {
        settings: rootItem.settings
        // The refresh cadence is scoped to a widget that is actually on
        // screen; nothing ticks when the bar is not there to show it.
        pollingAllowed: rootItem.visible && rootItem.bar !== null
    }

    tooltipText: "Tailscale — " + (tailscale.statusText === "" ? "Unknown" : tailscale.statusText)

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
        panelLoader.active = true;
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
        badgeColor: rootItem.theme.error
        // The badge sits in a ring of the bar's own background, so it reads as
        // a hole punched in the mark rather than a ninth dot.
        badgeBorderColor: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        badgeTextColor: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        fontFamily: rootItem.theme.fontUi
    }

    LazyLoader {
        id: panelLoader
        active: false
        component: TailscalePanel {
            theme: rootItem.theme
            tailscale: rootItem.tailscale
            widget: rootItem
        }
    }
}

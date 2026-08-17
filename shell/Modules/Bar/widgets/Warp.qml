import QtQuick
import Quickshell
import "../components"

// Cloudflare WARP — port of tobi/omarchy-warp's bar button (CREDITS.md).
//
// The mark is their drawn WarpIcon rather than a font glyph, and it carries the
// three states theirs does: the cloud in the bar foreground while the tunnel is
// up, dimmed and struck through while it is down, and a "!" badge while setup is
// still outstanding — an unregistered device or a daemon that is not answering.
// The tooltip is the backend's own word, and failures surface in the panel.
//
// A fourth state is ours: the badge also comes up when the tunnel is up and
// Cloudflare says the traffic did not come through it (WarpService.traceLeaking).
// A silently-not-working VPN is the one failure worth interrupting the bar for,
// and it is the state `warp-cli status` alone cannot see.
//
// Left click opens the panel, right click connects or disconnects, middle click
// refreshes — their click map, and the same one Tailscale uses here.
//
// With no warp-cli on the machine the widget takes no width, draws nothing and
// starts nothing after its one presence probe. That is this bar's contract for
// an optional CLI and it is where the port diverges: their widget stays visible
// without the CLI so the panel can offer to install it from the AUR, which is
// not how software arrives on this machine (packages/manifest.toml owns
// cloudflare-warp, and the apply installs it).
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind a real CLI, and never before the presence probe
    // has answered.
    visible: warp.probed && warp.installed

    // The shared service, injected by the bar's registry — ONE instance however
    // many screens carry this widget. Its settings and its pollingAllowed gate
    // are bound where it is created, at the bar root.
    required property WarpService warp

    // Whatever is most wrong, first: a leak outranks the mode, which outranks
    // nothing at all.
    tooltipText: {
        const head = "Cloudflare WARP — " + (warp.statusText === "" ? "Unknown" : warp.statusText);
        if (warp.traceLeaking)
            return head + " · traffic is not going through WARP";
        if (warp.mode !== "" && warp.active)
            return head + " · " + warp.modeLabel(warp.mode);
        return head;
    }

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("WarpPanel.qml", {
                theme: rootItem.theme,
                warp: rootItem.warp,
                widget: rootItem
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            warp.toggleConnection();
        else if (button === Qt.MiddleButton)
            warp.refreshDetails();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors of
    // its own (and a Row forbids the horizontal ones anyway).
    WarpIcon {
        id: mark

        iconSize: 13
        color: rootItem.warp.active ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        // Struck through only when it is off for ordinary reasons. A device
        // waiting to be registered gets the badge instead — the slash would say
        // "disconnected" when the truth is "not set up yet".
        crossed: !rootItem.warp.active && !rootItem.warp.needsRegistration && !rootItem.warp.daemonDown && !rootItem.warp.needsTos
        warning: rootItem.warp.needsRegistration || rootItem.warp.daemonDown || rootItem.warp.needsTos || rootItem.warp.traceLeaking
        badgeColor: rootItem.theme.error

        // A toggle that has gone out and not yet landed breathes, so the wait
        // is visible without a second mark: the switch has already thrown, and
        // this says the daemon has not agreed yet.
        SequentialAnimation on opacity {
            running: rootItem.warp.settling || rootItem.warp.connecting
            loops: Animation.Infinite

            NumberAnimation {
                to: 0.45
                duration: rootItem.theme.time(3)
                easing.type: rootItem.theme.easing
            }

            NumberAnimation {
                to: 1.0
                duration: rootItem.theme.time(3)
                easing.type: rootItem.theme.easing
            }
        }

        onOpacityChanged: if (!rootItem.warp.settling && !rootItem.warp.connecting && opacity !== 1.0)
            opacity = 1.0
        // The badge sits in a ring of the bar's own background, so it reads as a
        // hole punched in the mark rather than a bump on the cloud.
        badgeBorderColor: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        badgeTextColor: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
        fontFamily: rootItem.theme.fontUi
    }

    // Source-based: the panel compiles on first open, not with the bar.
    Loader {
        id: panelLoader
        visible: false
    }
}

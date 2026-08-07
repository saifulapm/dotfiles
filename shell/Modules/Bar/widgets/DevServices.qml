import QtQuick
import Quickshell
import "../components"
import "DevServicesModel.js" as Model

// devservices — this machine's Herd-like on-demand dev databases (podman
// quadlet containers behind systemd-socket-proxyd; the catalog and lifecycle
// live in DevServicesModel.js) as a bar button in the dropbox widget's shape.
//
// The mark is the md-server rack glyph (U+F048B — user request 2026-08-07,
// replacing the drawn cylinder, which the panel hero still wears via
// DevServicesIcon). It carries the whole state the way the Dropbox mark
// does: full foreground while at least one container runs, dimmed and
// darkened while everything is armed. The exact split lives in the tooltip
// and the panel.
//
// Left click opens the panel, right click re-probes (`podman ps` — the
// live state otherwise arrives entirely through the service's podman-events
// follower).
//
// On a machine without podman or without the proxy socket units the widget
// takes no width and draws nothing: it exists in the registry so
// "devservices" can be added to a bar section, and stays inert everywhere it
// would have nothing to say.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind the real stack, and never before the presence
    // probe has answered.
    visible: devservices.probed && devservices.available

    // The shared service, injected by the bar's registry — ONE instance (and
    // one podman-events follower) however many screens carry this widget (S2).
    required property DevServicesService devservices

    readonly property int runningCount: devservices.runningCount

    tooltipText: "Dev services — " + Model.summaryText(runningCount, devservices.serviceCount)

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("DevServicesPanel.qml", {
                theme: rootItem.theme,
                devservices: rootItem.devservices
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            devservices.refresh();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    OpticalGlyph {
        text: "󰒋"
        pixelSize: 13
        verticalInkCenter: true
        color: rootItem.runningCount > 0 ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.runningCount > 0 ? 1.0 : 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

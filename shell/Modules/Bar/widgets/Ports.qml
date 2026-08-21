import QtQuick
import Quickshell
import "../components"
import "../../../components"

// Ports — what is listening, as a bar button.
//
// The mark goes to the warning colour when something is bound beyond
// loopback. That is the only state worth interrupting a glance for: a dev
// server on 0.0.0.0 is reachable by everyone on whatever network this laptop
// is sitting on, and it is the kind of thing that gets left running for days
// without anyone noticing. Tailnet binds are NOT counted as exposed — that
// is the private network and reaching a dev server across it is the point of
// having one.
//
// Left click opens the panel, right click re-probes.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    visible: ports.probed

    required property PortsService ports

    tooltipText: ports.tooltip

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("PortsPanel.qml", {
                theme: rootItem.theme,
                ports: rootItem.ports
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            ports.refresh();
        else
            openPanel();
    }

    OpticalGlyph {
        text: "󰌘" // md-lan
        pixelSize: 13
        verticalInkCenter: true
        color: rootItem.ports.exposedCount > 0 ? rootItem.theme.warn : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.ports.exposedCount > 0 ? 1.0 : 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    Loader {
        id: panelLoader
        visible: false
    }
}

import QtQuick
import Quickshell
import "../components"
import "../../../components"

// Ports — what is listening, as a bar button.
//
// The icon appears only while something YOU started is listening — a dev
// server running is presence worth a glance, sixteen rows of declared
// plumbing are not (user call 2026-08-26). System/declared listeners never
// activate it; they live behind the panel's "system ports" toggle, and the
// panel stays reachable while the icon is hidden through the launcher's
// "Listening Ports" command (summonWhenHidden below).
//
// The mark goes to the warning colour when one of YOUR listeners is bound
// beyond loopback: a dev server on 0.0.0.0 is reachable by everyone on
// whatever network this laptop is sitting on, and it is the kind of thing
// that gets left running for days without anyone noticing. A declared wide
// bind is deliberate — it is in the manifest — and does not tint the bar.
// Tailnet binds are NOT counted as exposed — that is the private network
// and reaching a dev server across it is the point of having one.
//
// Left click opens the panel, right click re-probes.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    visible: ports.probed && ports.mineCount > 0

    // Lets Bar.summonWidget open the panel while the icon is hidden (the
    // launcher command path); the collapsed slot still anchors sanely.
    readonly property bool summonWhenHidden: true

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
        color: rootItem.ports.exposedMineCount > 0 ? rootItem.theme.warn : rootItem.barFg
        opacity: rootItem.ports.exposedMineCount > 0 ? 1.0 : 0.85
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    PanelLoader {
        id: panelLoader
    }
}

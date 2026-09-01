import QtQuick
import Quickshell
import "../components"
import "../../../components"
import "DnsShieldModel.js" as Model

// dnsshield — the family DNS helper (uBlockDNS chain, see DnsShieldModel.js)
// as a bar button in the family shape.
//
// The mark is the md-shield-half-full glyph: full foreground while the chain
// is verified blocking (the probe's live youtube.com test), dimmed while
// anything in it is down or unproven. The split lives in the tooltip and the
// panel rows.
//
// Left click opens the panel, right click re-probes. On machines without
// the helper unit the widget takes no width — it exists in the registry so
// "dnsshield" can sit in a bar layout everywhere.
BarButton {
    id: rootItem

    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    visible: dnsshield.probed && dnsshield.available

    // The shared service, injected by the bar's registry — ONE instance
    // however many screens carry this widget (S2).
    required property DnsShieldService dnsshield

    tooltipText: "DNS Shield — " + Model.heroMeta(dnsshield.state)

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("DnsShieldPanel.qml", {
                theme: rootItem.theme,
                dnsshield: rootItem.dnsshield
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            dnsshield.refresh();
        else
            openPanel();
    }

    OpticalGlyph {
        text: "󰞀"
        pixelSize: 13
        verticalInkCenter: true
        color: rootItem.dnsshield.healthy ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.dnsshield.healthy ? 1.0 : 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    PanelLoader {
        id: panelLoader
    }
}

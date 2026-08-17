import QtQuick
import Quickshell
import "../components"
import "../../../components"

// dufs — the on-demand file server (bin/dufs-serve behind the dufs.service
// user unit: $HOME over HTTP with basic auth on port 5000) as a bar button in
// the devservices widget's shape.
//
// The mark is md-nas (U+F08F3), a little file-server box. It carries the
// state the way the family does: full foreground while the server runs,
// dimmed and darkened while it is off. The address, the credentials and the
// switch live in the panel.
//
// Left click opens the panel, right click toggles the server, middle click
// re-probes the unit.
//
// On a machine without the dufs binary the widget takes no width and draws
// nothing after its one presence probe — it exists in the registry so "dufs"
// can be named in a bar section, and stays inert where it has nothing to say.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind a real binary, and never before the presence
    // probe has answered.
    visible: dufs.probed && dufs.installed

    // The shared service, injected by the bar's registry — ONE instance
    // however many screens carry this widget (S2).
    required property DufsService dufs

    tooltipText: "File server — " + (dufs.active ? "serving home on port " + dufs.port : "off")

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("DufsPanel.qml", {
                theme: rootItem.theme,
                dufs: rootItem.dufs
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            dufs.toggle();
        else if (button === Qt.MiddleButton)
            dufs.refresh();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    OpticalGlyph {
        text: "󰣳"
        pixelSize: 13
        verticalInkCenter: true
        color: rootItem.dufs.active ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.dufs.active ? 1.0 : 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

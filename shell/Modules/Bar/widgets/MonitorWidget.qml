import QtQuick
import Quickshell
import "../components"
import "../../../components"

// Display — omarchy's monitor plugin on niri IPC. Wheel adjusts brightness,
// click opens the panel that carries the sliders, the scale presets and the
// per-output rows.
//
// The mark is a screen, and the tooltip counts them. Nothing here changes on
// its own, so the icon names the hardware rather than a state: it did carry
// the night-light sun/moon pair until that feature was removed, and with no
// self-changing state left there is nothing else for it to say.
BarIcon {
    id: rootItem

    glyph: "󰍹" // md-monitor
    glyphScale: 1.0

    tooltipText: Quickshell.screens.length + " display" + (Quickshell.screens.length === 1 ? "" : "s")

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("MonitorPanel.qml", {
                theme: rootItem.theme
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: rootItem.openPanel()

    onWheelMoved: delta => {
        Quickshell.execDetached(["qs", "ipc", "call", "osd", delta > 0 ? "brightnessUp" : "brightnessDown"]);
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    PanelLoader {
        id: panelLoader
    }
}

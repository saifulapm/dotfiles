import QtQuick
import Quickshell
import "../components"

// Displays — omarchy's monitor plugin, on niri IPC. Wheel adjusts
// brightness (routed through the OSD like the keys).
BarIcon {
    id: rootItem

    // md-desktop_mac (multi: md-monitor_multiple) — the plain md-monitor's
    // thin outline read smaller than its solid neighbors; the desk base
    // gives it the same visual weight, helped by a nudge of optical scale.
    glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰇄"
    glyphScale: Quickshell.screens.length > 1 ? 1 : 1.1
    tooltipText: Quickshell.screens.length + " display" + (Quickshell.screens.length === 1 ? "" : "s")

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("MonitorPanel.qml", {
                theme: rootItem.theme
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: openPanel()

    onWheelMoved: delta => {
        Quickshell.execDetached(["qs", "ipc", "call", "osd", delta > 0 ? "brightnessUp" : "brightnessDown"]);
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

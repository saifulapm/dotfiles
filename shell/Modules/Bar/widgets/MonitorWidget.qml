import QtQuick
import Quickshell
import "../components"

// Displays — omarchy's monitor plugin, on niri IPC. Wheel adjusts
// brightness (routed through the OSD like the keys).
BarIcon {
    id: rootItem

    glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    tooltipText: Quickshell.screens.length + " display" + (Quickshell.screens.length === 1 ? "" : "s")

    function openPanel() {
        panelLoader.active = true;
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: openPanel()

    onWheelMoved: delta => {
        Quickshell.execDetached(["qs", "ipc", "call", "osd", delta > 0 ? "brightnessUp" : "brightnessDown"]);
    }

    LazyLoader {
        id: panelLoader
        active: false
        component: MonitorPanel {
            theme: rootItem.theme
        }
    }
}

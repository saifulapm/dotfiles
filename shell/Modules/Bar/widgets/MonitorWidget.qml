import QtQuick
import Quickshell
import "../components"

// Displays — omarchy's monitor plugin, on niri IPC. Wheel adjusts
// brightness (routed through the OSD like the keys).
BarIcon {
    id: rootItem

    // The ShellRoot, for the night light service the panel switches.
    required property var shell

    glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    tooltipText: Quickshell.screens.length + " display" + (Quickshell.screens.length === 1 ? "" : "s")

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("MonitorPanel.qml", {
                theme: rootItem.theme,
                nightlight: rootItem.shell ? rootItem.shell.nightlight : null
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

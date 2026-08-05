import QtQuick
import "../components"

// The far-left menu button (omarchy has its logo here). Opens the launcher.
BarIcon {
    id: rootItem

    required property var shell

    glyph: "󰀻" // md-apps grid
    tooltipText: "Apps"

    onTapped: rootItem.shell.toggleLauncher()
}

import QtQuick
import "../components"

// The far-left menu button (omarchy has its logo here). Left-click opens the
// app launcher, right-click the command menu — their split exactly.
BarIcon {
    id: rootItem

    required property var shell

    glyph: "󰀻" // md-apps grid
    tooltipText: "Apps — right-click for the menu"

    onTapped: button => {
        if (button === Qt.RightButton)
            rootItem.shell.toggleMenu();
        else
            rootItem.shell.toggleLauncher();
    }
}

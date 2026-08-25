import QtQuick
import Quickshell
import "../components"

// The far-left launcher button (omarchy has its logo here). Any click opens
// vicinae — the launcher, command palette and clipboard history in one
// window (2026-08-26: the in-shell Launcher and Menu modules retired).
BarIcon {
    id: rootItem

    required property var shell

    glyph: "󰀻" // md-apps grid
    tooltipText: "Launcher"

    onTapped: Quickshell.execDetached(["vicinae", "toggle"])
}

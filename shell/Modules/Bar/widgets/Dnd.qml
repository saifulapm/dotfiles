import QtQuick
import "../components"

// Do-not-disturb indicator, ported from omarchy's Dnd indicator (CREDITS.md):
// the bell-off glyph with their two tooltip strings, active while
// notifications are silenced, click toggles either way.
BarIndicator {
    id: rootItem

    required property var notifs

    active: notifs.dnd
    activeGlyph: "󰂛" // md-bell-off
    inactiveGlyph: "󰂛"
    activeTooltip: "Allow Notifications"
    inactiveTooltip: "Silence Notifications"

    onTapped: rootItem.notifs.dnd = !rootItem.notifs.dnd
}

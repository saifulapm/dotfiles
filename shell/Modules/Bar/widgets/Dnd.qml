import QtQuick
import "../components"

// Do-not-disturb indicator, omarchy-style status slot: visible only while
// DND is on; click turns it off.
BarIcon {
    id: rootItem

    required property var notifs

    glyph: "󰂛" // bell-off
    status: true
    visible: notifs.dnd
    tooltipText: "Silence Notifications — click to allow"

    onTapped: rootItem.notifs.dnd = false
}

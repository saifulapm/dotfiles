import QtQuick
import "../components"

// Night light indicator, ported from omarchy's NightLight indicator
// (CREDITS.md): their glyph, their two tooltip strings — which name what a
// click does, not what is on — and a click that toggles the service.
BarIndicator {
    id: rootItem

    required property var nightlight

    active: nightlight ? nightlight.enabled : false
    activeGlyph: "󰔎" // md-theme_light_dark
    inactiveGlyph: "󰔎"
    activeTooltip: "Day Light"
    inactiveTooltip: "Night Light"

    onTapped: {
        if (rootItem.nightlight)
            rootItem.nightlight.setNightlight(!rootItem.active);
    }
}

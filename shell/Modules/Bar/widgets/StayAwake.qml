import QtQuick
import "../components"

// Stay-awake indicator, ported from omarchy's StayAwake indicator:
// the coffee glyph, their two tooltip strings, and a click that
// toggles idle detection off and on. Active means the idle service is
// suspended — no monitor blank, no idle lock — which it persists as the
// presence of its flag file.
BarIndicator {
    id: rootItem

    required property var idle

    active: idle ? idle.stayAwake : false
    activeGlyph: "󰅶" // md-coffee
    inactiveGlyph: "󰅶"
    activeTooltip: "Allow Idle Lock & Screensaver"
    inactiveTooltip: "Stay Awake"

    onTapped: {
        if (rootItem.idle)
            rootItem.idle.setStayAwake(!rootItem.idle.stayAwake);
    }
}

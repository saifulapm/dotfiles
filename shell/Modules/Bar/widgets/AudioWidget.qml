import QtQuick
import "../components"

// Volume, omarchy audio-widget style: FA pulseaudio glyph ladder, left/right
// click toggles mute, wheel adjusts ±5%.
BarIcon {
    id: rootItem

    required property var audio

    readonly property int pct: Math.round(rootItem.audio.volume * 100)

    glyph: {
        if (!rootItem.audio.ready || rootItem.audio.muted)
            return "󰖁"; // volume-off
        if (rootItem.audio.volume >= 0.67)
            return "󰕾"; // volume-high
        if (rootItem.audio.volume >= 0.34)
            return "󰖀"; // volume-medium
        return "󰕿";     // volume-low
    }

    visible: audio.ready
    dimmed: audio.muted
    tooltipText: audio.muted ? "Muted" : pct + "%"

    onTapped: rootItem.audio.toggleMute()
    onWheelMoved: delta => rootItem.audio.setVolume(rootItem.audio.volume + (delta > 0 ? 0.05 : -0.05))
}

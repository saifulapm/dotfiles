import QtQuick
import "../components"

// Microphone mute toggle, omarchy glyphs. Wheel adjusts source volume.
BarIcon {
    id: rootItem

    required property var audio

    glyph: audio.micMuted ? "󰍭" : "󰍬" // mic-off / mic
    visible: audio.source !== null
    dimmed: audio.micMuted
    tooltipText: audio.micMuted ? "Microphone muted" : "Microphone live"

    onTapped: rootItem.audio.toggleMicMute()
    onWheelMoved: delta => {
        const a = rootItem.audio.source && rootItem.audio.source.audio;
        if (a)
            a.volume = Math.max(0, Math.min(1, a.volume + (delta > 0 ? 0.05 : -0.05)));
    }
}

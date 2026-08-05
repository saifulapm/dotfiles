import QtQuick
import Quickshell
import "../components"
import "AudioModel.js" as Model

// Volume, omarchy audio-widget style: glyph ladder (headphones when the
// default sink is a headset, as theirs does), left click opens the panel,
// right click toggles mute, wheel adjusts ±5%.
BarIcon {
    id: rootItem

    required property var audio

    readonly property int pct: Math.round(rootItem.audio.volume * 100)

    glyph: {
        if (!rootItem.audio.ready || rootItem.audio.muted)
            return "󰖁"; // volume-off
        if (Model.isHeadphones(rootItem.audio.sink))
            return "󰋋"; // headphones
        if (rootItem.audio.volume >= 0.67)
            return "󰕾"; // volume-high
        if (rootItem.audio.volume >= 0.34)
            return "󰖀"; // volume-medium
        return "󰕿";     // volume-low
    }

    visible: audio.ready
    dimmed: audio.muted
    tooltipText: audio.muted ? "Muted" : pct + "%"

    function openPanel() {
        panelLoader.active = true;
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.LeftButton) {
            openPanel();
        } else {
            rootItem.audio.toggleMute();
        }
    }
    onWheelMoved: delta => rootItem.audio.setVolume(rootItem.audio.volume + (delta > 0 ? 0.05 : -0.05))

    LazyLoader {
        id: panelLoader
        active: false
        component: AudioPanel {
            theme: rootItem.theme
        }
    }
}

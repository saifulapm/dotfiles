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

    // The volume ladder's ink tops out at 0.73em — visibly under the 0.83em
    // neighbors without compensation.
    glyphScale: 1.1
    visible: audio.ready
    dimmed: audio.muted
    tooltipText: audio.muted ? "Muted" : pct + "%"

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("AudioPanel.qml", {
                theme: rootItem.theme,
                media: rootItem.bar && rootItem.bar.shell ? rootItem.bar.shell.media : null
            });
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

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

import Quickshell.Services.Pipewire
import QtQuick
import "lib/control.mjs" as Lib

// Control's Audio section: every sink, then every source, from PipeWire's own change events.
Item {
    id: audio

    required property var theme
    property int selected: 0

    readonly property var all: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var nodes: all.filter(n => n.isSink).concat(all.filter(n => !n.isSink))
    // The preferred node is the one Enter sets; the session manager then makes it the default.
    readonly property PwNode defaultSink: Pipewire.preferredDefaultAudioSink ?? Pipewire.defaultAudioSink
    readonly property PwNode defaultSource: Pipewire.preferredDefaultAudioSource ?? Pipewire.defaultAudioSource
    readonly property var rows: nodes.map(n => Lib.audioRow({
                name: n.name,
                description: n.description,
                isSink: n.isSink,
                volume: n.audio.volume,
                muted: n.audio.muted,
                isDefault: n === (n.isSink ? defaultSink : defaultSource)
            }))

    function key(event) {
        const node = nodes[selected];
        if (!node)
            return false;
        if (event.key === Qt.Key_H || event.key === Qt.Key_L)
            node.audio.volume = Lib.stepVolume(node.audio.volume, event.key === Qt.Key_L ? 1 : -1);
        else if (event.key === Qt.Key_M)
            node.audio.muted = !node.audio.muted;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (node.isSink)
                Pipewire.preferredDefaultAudioSink = node;
            else
                Pipewire.preferredDefaultAudioSource = node;
        } else
            return false;
        return true;
    }

    function state() {
        return {
            defaultSink: defaultSink ? defaultSink.name : null,
            defaultSource: defaultSource ? defaultSource.name : null
        };
    }

    implicitHeight: hint.implicitHeight

    PwObjectTracker {
        objects: audio.nodes
    }

    Text {
        id: hint
        textFormat: Text.PlainText
        leftPadding: 20
        text: "H/L VOLUME · ↵ DEFAULT · M MUTE"
        color: audio.theme.color.muted
        font.family: audio.theme.tokens ? audio.theme.tokens.type.ui : ""
        font.pixelSize: 10
        font.letterSpacing: 1.2
    }
}

import Quickshell.Services.Pipewire
import QtQuick
import "lib/control.mjs" as Lib
import "lib/voice.mjs" as V

// Control's Audio section: every sink, then every source, from PipeWire's own change events.
Item {
    id: audio

    required property var theme
    property int selected: 0
    readonly property var look: V.listLook(theme.tokens)

    readonly property var all: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var nodes: all.filter(n => n.isSink).concat(all.filter(n => !n.isSink))
    // The preferred node is the one Enter sets, which the session manager then makes the default; one binding per Pipewire property, since Quickshell 0.3.2 hands a binding that reads both a freed node while the default vanishes.
    readonly property PwNode preferredSink: Pipewire.preferredDefaultAudioSink
    readonly property PwNode currentSink: Pipewire.defaultAudioSink
    readonly property PwNode preferredSource: Pipewire.preferredDefaultAudioSource
    readonly property PwNode currentSource: Pipewire.defaultAudioSource
    readonly property PwNode defaultSink: preferredSink ?? currentSink
    readonly property PwNode defaultSource: preferredSource ?? currentSource
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
            defaultSource: defaultSource ? defaultSource.name : null,
            hint: hint.text
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
        text: audio.look.tabText("h/l volume · ↵ default · m mute")
        color: audio.look.small.color
        font.family: audio.look.small.font
        font.pixelSize: audio.look.small.size
        font.letterSpacing: audio.look.small.spacing
    }
}

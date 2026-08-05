import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Thin wrapper over the PipeWire default sink/source. Eager but tiny: the
// PwObjectTracker binding is what keeps node properties live (nodes are
// inert without one — see quickshell src/services/pipewire/qml.hpp).
QtObject {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false
    readonly property bool ready: Pipewire.ready && sink !== null

    property PwObjectTracker tracker: PwObjectTracker {
        objects: [root.sink, root.source].filter(n => n !== null)
    }
}

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

    // Latched, not live: a wireplumber restart tears the whole graph down and
    // rebuilds it inside a few seconds, and every widget bound to `ready`
    // would blink out with it. Becoming ready propagates immediately; losing
    // the sink only propagates if it stays lost past the hold.
    readonly property bool readyNow: Pipewire.ready && sink !== null
    property bool ready: false
    onReadyNowChanged: {
        if (readyNow) {
            readyHold.stop();
            ready = true;
        } else {
            readyHold.restart();
        }
    }
    property Timer readyHold: Timer {
        interval: 4000
        onTriggered: root.ready = root.readyNow
    }

    // An application holds the microphone: any live capture stream, minus the
    // asahi-audio effect chain's own streams and the shell's mic-meter node
    // (PwNodePeakMonitor spawns a "quickshell" AudioInStream while the audio
    // panel is open, which must not light the indicator). Presence-based on
    // purpose — per-stream mute state would need a tracker per stream node,
    // and "an app has the mic open" is the signal omarchy's widget carries.
    // Re-evaluates only when the node list changes; no polling.
    readonly property bool micInUse: !micMuted && Pipewire.nodes.values.some(n => {
        if (!n || !n.isStream || n.isSink)
            return false;
        const name = n.name || "";
        return !name.startsWith("effect_") && !name.startsWith("audio_effect.") && name !== "quickshell";
    })

    function setVolume(v) {
        if (sink && sink.audio)
            sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMute() {
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function toggleMicMute() {
        if (source && source.audio)
            source.audio.muted = !source.audio.muted;
    }

    property PwObjectTracker tracker: PwObjectTracker {
        objects: [root.sink, root.source].filter(n => n !== null)
    }
}

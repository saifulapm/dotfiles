import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import ".." as Root
import "../lib/island.mjs" as I

// The island's OSD slot: the default sink's volume when PipeWire reports a change, and brightness after brightnessctl sets it.
Scope {
    id: osd

    // {kind: 'volume'|'brightness', value: 0-100}, null while no OSD shows.
    property var current: null
    readonly property PwNode sink: Pipewire.defaultAudioSink
    // The last volume seen on this sink, -1 until it is ready, so binding a sink shows nothing.
    property int last: -1

    function show(kind, value) {
        current = { kind, value };
        hold.restart();
    }

    function level() {
        return sink.audio.muted ? 0 : Math.round(sink.audio.volume * 100);
    }

    function changed() {
        if (!sink?.ready)
            return;
        const value = level();
        if (last >= 0 && value !== last)
            show("volume", value);
        last = value;
    }

    // Only steps like 5%+ or an absolute 1% to 100% reach brightnessctl, as argv, so a call cannot pass it anything else.
    function brightness(step) {
        if (!I.brightnessStep(step) || setter.running)
            return;
        setter.command = ["brightnessctl", "-m", "set", step];
        setter.running = true;
    }

    onSinkChanged: last = -1

    PwObjectTracker {
        objects: [osd.sink]
    }

    Connections {
        target: osd.sink?.audio ?? null
        function onVolumesChanged() {
            osd.changed();
        }
        function onMutedChanged() {
            osd.changed();
        }
    }

    Connections {
        target: osd.sink
        function onReadyChanged() {
            osd.changed();
        }
    }

    // brightnessctl -m prints device,class,current,percent,max; the percent is like 45%.
    Process {
        id: setter
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.split(",")[3]);
                if (!isNaN(value))
                    osd.show("brightness", value);
            }
        }
    }

    Root.Tick {
        id: hold
        interval: 1500
        onTriggered: osd.current = null
    }
}

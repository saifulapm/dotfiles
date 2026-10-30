import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import "lib/control.mjs" as Lib
import "lib/control-audio.mjs" as A
import "lib/voice.mjs" as V

// Control's Audio section: every sink, then every playing app, then every source, from PipeWire's own change events.
Item {
    id: audio

    required property var theme
    property int selected: 0
    readonly property var look: V.listLook(theme.tokens)

    readonly property var all: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var sinks: all.filter(n => n.isSink)
    readonly property var sources: all.filter(n => !n.isSink)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream)
    // A group's node can go a moment before the group does, so each end is read with a null check (research-v26-platform).
    readonly property var links: Pipewire.linkGroups.values.map(g => ({
                source: g.source?.id ?? -1,
                target: g.target?.id ?? -1,
                active: g.state === PwLinkState.Active
            }))
    readonly property var apps: A.appStreams(streams.map(n => ({
                id: n.id,
                props: n.properties ?? {}
            })), links, sinks.map(n => n.id)).map(a => ({
                node: streams.find(n => n.id === a.id),
                sink: sinks.find(n => n.id === a.sink)
            }))
    // Each row's node, and for an app the sink it plays on.
    readonly property var entries: sinks.map(n => ({
                node: n
            })).concat(apps, sources.map(n => ({
                node: n
            })))
    readonly property var nodes: entries.map(e => e.node)
    // The preferred node is the one Enter sets, which the session manager then makes the default; one binding per Pipewire property, since Quickshell 0.3.2 hands a binding that reads both a freed node while the default vanishes.
    readonly property PwNode preferredSink: Pipewire.preferredDefaultAudioSink
    readonly property PwNode currentSink: Pipewire.defaultAudioSink
    readonly property PwNode preferredSource: Pipewire.preferredDefaultAudioSource
    readonly property PwNode currentSource: Pipewire.defaultAudioSource
    readonly property PwNode defaultSink: preferredSink ?? currentSink
    readonly property PwNode defaultSource: preferredSource ?? currentSource
    // Every device's profiles and ports, by id, as pw-dump last read them; Quickshell has no API for either.
    property var devices: ({})
    // A profile change makes its device's nodes anew, so a new set of nodes is read again.
    readonly property string nodeIds: all.map(n => n.id).join(",")
    readonly property var rows: entries.map(e => e.sink ? A.appRow({
                    title: A.appTitle(e.node.properties ?? {}),
                    sink: e.sink.description || e.sink.name,
                    volume: e.node.audio.volume,
                    muted: e.node.audio.muted
                }) : Lib.audioRow({
                    name: e.node.name,
                    description: e.node.description,
                    isSink: e.node.isSink,
                    volume: e.node.audio.volume,
                    muted: e.node.audio.muted,
                    isDefault: e.node === (e.node.isSink ? defaultSink : defaultSource),
                    device: deviceOf(e.node) ? A.deviceParts(deviceOf(e.node), direction(e.node), cardDevice(e.node)) : []
                }))

    // An app that stops takes its row, so the selection never points past the last.
    onRowsChanged: selected = Math.min(selected, Math.max(0, rows.length - 1))
    onVisibleChanged: readDevices()
    onNodeIdsChanged: readDevices()

    // Quickshell hands node properties over as strings.
    function deviceOf(node) {
        const id = node.properties?.["device.id"];
        return id === undefined ? null : devices[id] ?? null;
    }

    function cardDevice(node) {
        const d = node.properties?.["card.profile.device"];
        return d === undefined ? null : Number(d);
    }

    function direction(node) {
        return node.isSink ? "Output" : "Input";
    }

    function readDevices() {
        if (visible)
            dumper.running = true;
    }

    // p takes the device's id, r the node's own, which wpctl resolves to its device.
    function cycleDevice(node, port) {
        const device = deviceOf(node);
        if (!device)
            return false;
        const index = port ? A.nextRoute(device, direction(node), cardDevice(node)) : A.nextProfile(device);
        if (index === null)
            return false;
        setter.command = port ? ["wpctl", "set-route", String(node.id), String(index)] : ["wpctl", "set-profile", node.properties["device.id"], String(index)];
        setter.running = true;
        return true;
    }

    function key(event) {
        const entry = entries[selected];
        if (!entry)
            return false;
        const node = entry.node;
        if (event.key === Qt.Key_H || event.key === Qt.Key_L)
            node.audio.volume = Lib.stepVolume(node.audio.volume, event.key === Qt.Key_L ? 1 : -1);
        else if (event.key === Qt.Key_M)
            node.audio.muted = !node.audio.muted;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (entry.sink)
                moveApp(entry);
            else if (node.isSink)
                Pipewire.preferredDefaultAudioSink = node;
            else
                Pipewire.preferredDefaultAudioSource = node;
        } else if (event.key === Qt.Key_P || event.key === Qt.Key_R)
            return !entry.sink && cycleDevice(node, event.key === Qt.Key_R);
        else
            return false;
        return true;
    }

    // The session manager moves a stream to the sink its target.object names, by serial.
    function moveApp(entry) {
        const next = sinks.find(n => n.id === A.nextSink(sinks.map(n => n.id), entry.sink.id));
        if (!next || next === entry.sink)
            return;
        mover.command = ["pw-metadata", "-n", "default", String(entry.node.id), "target.object", String(next.properties["object.serial"])];
        mover.running = true;
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
        objects: audio.all
    }

    Process {
        id: mover
    }

    Process {
        id: setter
        onExited: audio.readDevices()
    }

    Process {
        id: dumper
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    audio.devices = A.devices(JSON.parse(text));
                } catch (e) {
                    audio.devices = {};
                }
            }
        }
    }

    // A stream's properties, volume and mute, and a link's state, arrive only once bound, so they are bound while the section is drawn.
    PwObjectTracker {
        objects: audio.visible ? audio.streams.concat(Pipewire.linkGroups.values) : []
    }

    Text {
        id: hint
        textFormat: Text.PlainText
        leftPadding: 20
        text: audio.look.tabText("h/l volume · ↵ default or move · m mute · p profile · r port")
        color: audio.look.small.color
        font.family: audio.look.small.font
        font.pixelSize: audio.look.small.size
        font.letterSpacing: audio.look.small.spacing
    }
}

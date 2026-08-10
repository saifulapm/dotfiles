import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../components"
import "AudioModel.js" as Model

// Audio panel — full port of omarchy's audio plugin Panel.qml in our own
// tokens: hero with the now-playing context and a master mute switch, then
// OUTPUT (volume + sink picker), INPUT (mic volume + live peak meter +
// source picker) and SOURCES (per-application playback streams, each with
// its own slider and mute).
//
// One cursor model drives both mouse and keyboard: hovering a row moves the
// cursor, j/k walk it, h/l adjust the slider it sits on, Enter activates and
// m mutes. Every list is a snapshot refreshed off a settle timer — PipeWire
// can drop nodes while quickshell is dispatching the removal, and rebuilding
// a Repeater from that signal path is what destabilizes their service.
BarPanel {
    id: panel

    panelTitle: ""
    cardWidth: theme.space(95)

    // ------------------------------------------------------------- sources
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.ready && Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
    // The media service's ladder-selected player — upstream's audio panel
    // reads the media service's activePlayer, so the "active stream"
    // highlight agrees with the bar widget and the OSD. The naive
    // whatever-is-playing pick remains as the no-service fallback.
    property var media: null
    readonly property var activePlayer: {
        if (media && media.activePlayer)
            return media.activePlayer;
        const all = panel.mprisPlayers;
        return all.find(p => p.isPlaying) || all[0] || null;
    }

    // quickshell exposes PwNode.type as a numeric flags enum; the model's
    // media.class string tests read the resolved name instead.
    function typeName(node) {
        if (!node)
            return "";
        try {
            return String(PwNodeType.toString(node.type));
        } catch (e) {
            return "";
        }
    }

    readonly property var candidateSinks: panel.nodes.filter(n => n && n.isSink && !n.isStream)

    readonly property var candidateSources: panel.nodes.filter(n => n && !n.isSink && !n.isStream && String(n.name || "") !== "quickshell" && Model.isAudioSource(n, panel.typeName(n)))

    // A DSP chain's output is a playback stream too, but it is the processing
    // itself rather than an application, so it does not belong in the list.
    // omarchy filters their speaker tuning by name; on this box the same node
    // is asahi-audio's convolver (effect_output.j493-convolver).
    function isProcessingStream(node) {
        const name = String(node.name || "");
        return name.indexOf("omarchy_speaker_tuning") === 0 || name.indexOf("effect_output.") === 0 || name.indexOf("audio_effect.") === 0;
    }

    readonly property var candidateStreams: panel.nodes.filter(n => n && n.isStream && !panel.isProcessingStream(n) && Model.isPlaybackStream(n, panel.typeName(n)))

    // The default device always belongs in its list even if PipeWire has not
    // published it as a candidate yet.
    readonly property var audioSinks: {
        const list = panel.candidateSinks.slice();
        if (panel.sink && list.indexOf(panel.sink) < 0)
            list.unshift(panel.sink);
        return list;
    }

    readonly property var audioSources: {
        const list = panel.candidateSources.slice();
        if (panel.source && list.indexOf(panel.source) < 0)
            list.unshift(panel.source);
        return list;
    }

    readonly property var audioStreams: panel.candidateStreams.filter(n => n.audio)

    // Repeaters read these snapshots, never the live PipeWire model.
    property var displaySinks: []
    property var displaySources: []
    property var displayStreams: []

    readonly property real outputVolume: panel.sink && panel.sink.audio ? panel.sink.audio.volume : 0
    readonly property bool outputMuted: panel.sink && panel.sink.audio ? panel.sink.audio.muted : false
    readonly property real inputVolume: panel.source && panel.source.audio ? panel.source.audio.volume : 0
    readonly property bool inputMuted: panel.source && panel.source.audio ? panel.source.audio.muted : false

    // Only channels that exist get a vote: a box with no source would other-
    // wise report "input unmuted" forever, leaving the hero switch able to
    // mute but never to unmute.
    readonly property bool hasOutput: !!(panel.sink && panel.sink.audio)
    readonly property bool hasInput: !!(panel.source && panel.source.audio)
    readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)
    readonly property string toggleHint: anyAudible ? "Mute" : "Unmute"

    onAudioSinksChanged: panel.scheduleRefresh()
    onAudioSourcesChanged: panel.scheduleRefresh()
    onAudioStreamsChanged: panel.scheduleRefresh()

    onPanelOpened: {
        panel.refreshModels();
        panel.focusSection = "output";
        panel.selectedIndex = -1;
        panel.cursorActive = false;
        scroller.contentY = 0;
    }
    onPanelClosed: {
        refreshTimer.stop();
        panel.displaySinks = [];
        panel.displaySources = [];
        panel.displayStreams = [];
    }

    function refreshModels() {
        if (!panel.opened)
            return;
        panel.displaySinks = Model.listSnapshot(panel.audioSinks);
        panel.displaySources = Model.listSnapshot(panel.audioSources);
        panel.displayStreams = Model.listSnapshot(panel.audioStreams);
        panel.clampCursor();
    }

    // Dummy Output (auto_null) is what PipeWire parks the default on while
    // the real devices are gone, so it does not count as a device here.
    function realDeviceCount(list) {
        return list.filter(n => n && String(n.name || "") !== "auto_null").length;
    }

    function scheduleRefresh() {
        if (!panel.opened)
            return;
        // Gains settle at 75ms as before. A shrinking device list gets held
        // back: a wireplumber restart drops every sink and source and then
        // rebuilds them within a second or two, and committing the shrink
        // immediately renders the AirPods -> Dummy -> rebuilt cycle as
        // flapping. If the devices are genuinely gone the hold expires and
        // the honest shrink commits.
        const shrinking = panel.realDeviceCount(panel.audioSinks) < panel.realDeviceCount(panel.displaySinks)
            || panel.audioSources.length < panel.displaySources.length;
        refreshTimer.interval = shrinking ? 1500 : 75;
        refreshTimer.restart();
    }

    Timer {
        id: refreshTimer
        interval: 75
        onTriggered: panel.refreshModels()
    }

    // Nodes are inert without a tracker, and only the open panel needs them
    // bound — the bar's own Audio service tracks the two default nodes.
    PwObjectTracker {
        objects: panel.opened ? panel.candidateSinks.concat(panel.candidateSources).concat(panel.candidateStreams) : []
    }

    // Live microphone level. omarchy reads it from PwNodePeakMonitor, which
    // taps the node's own stream through PipeWire rather than polling
    // anything; quickshell 0.3 ships the same type (verified in the Pipewire
    // qmltypes) and it only runs while the panel is open.
    PwNodePeakMonitor {
        id: inputPeak
        node: panel.opened ? panel.source : null
        enabled: panel.opened && panel.source !== null
    }

    // ------------------------------------------------------------- writing
    // Measured on this MacBook: the mono headset-mic node takes scalar and
    // vector writes cleanly; the node quickshell 0.3 refuses is the convolver
    // output stream ("channelVolumes and channelMap are not the same size.
    // Sizes: 2 4"), which it complains about for as long as anything tracks
    // it — isProcessingStream keeps it out of the list, so nothing does.
    // This guard is the belt to that brace: write a correctly sized vector
    // when a node's volume list disagrees with its channel map, and never
    // re-write a value the node already holds, so a refused write on any
    // future odd node stays one line in the log instead of a loop.
    function writeVolume(node, v, max) {
        if (!node || !node.audio)
            return 0;
        const nodeAudio = node.audio;
        const ceiling = max === undefined ? 1 : max;
        const target = Math.max(0, Math.min(ceiling, v));
        if (Math.abs(nodeAudio.volume - target) < 0.001)
            return target;
        const channels = nodeAudio.channels ? nodeAudio.channels.length : 0;
        if (channels > 0 && nodeAudio.volumes && nodeAudio.volumes.length !== channels) {
            const vols = [];
            for (let i = 0; i < channels; i++)
                vols.push(target);
            nodeAudio.volumes = vols;
            return target;
        }
        nodeAudio.volume = target;
        return target;
    }

    function setOutputVolume(v) {
        return panel.writeVolume(panel.sink, v);
    }

    function setInputVolume(v) {
        return panel.writeVolume(panel.source, v);
    }

    function toggleMute(node) {
        if (node && node.audio)
            node.audio.muted = !node.audio.muted;
    }

    function toggleOutputMute() {
        panel.toggleMute(panel.sink);
    }

    function toggleInputMute() {
        panel.toggleMute(panel.source);
    }

    // The hero switch is the whole panel's on/off, so it carries both
    // channels. It reads as on while anything is still audible, which keeps
    // muting one channel below from flipping the master switch.
    function toggleAllMuted() {
        const mute = panel.anyAudible;
        if (panel.hasOutput)
            panel.sink.audio.muted = mute;
        if (panel.hasInput)
            panel.source.audio.muted = mute;
    }

    function setDefaultSink(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        if (node)
            Pipewire.preferredDefaultAudioSource = node;
    }

    // -------------------------------------------------------------- labels
    function nodeLabel(node) {
        return Model.nodeLabel(node);
    }

    function streamLabel(node) {
        return Model.streamLabel(node, panel.mprisPlayers, panel.displayStreams);
    }

    // Speaker ladder in the Material Design range: the FontAwesome glyphs
    // omarchy uses don't render under our Symbols Nerd Font fallback.
    function outputIcon() {
        if (!panel.hasOutput || panel.outputMuted)
            return "󰖁";
        if (Model.isHeadphones(panel.sink))
            return "󰋋";
        const v = panel.outputVolume;
        if (v >= 0.67)
            return "󰕾";
        if (v >= 0.34)
            return "󰖀";
        if (v > 0)
            return "󰕿";
        return "󰝟";
    }

    readonly property string heroSubtitle: {
        const player = panel.activePlayer;
        if (player && player.isPlaying) {
            const identity = Model.mprisPlayerLabel(player) || "Playing";
            const title = player.trackTitle || "";
            return title ? identity + " · " + title : identity;
        }
        return Model.outputVolumeName(outputSlider.dragging ? outputSlider.liveValue : panel.outputVolume, panel.outputMuted);
    }

    // -------------------------------------------------------------- cursor
    // Sections: "header" (virtual, the master switch), "output", "input",
    // "streams". selectedIndex -1 is the section's slider row, 0..N-1 a
    // device or stream row. Visuals come from this model alone, never from
    // containsMouse, so the highlight stays unique across mouse + keyboard.
    property string focusSection: "output"
    property int selectedIndex: -1
    property bool cursorActive: false

    readonly property bool headerHasCursor: cursorActive && focusSection === "header"

    function sectionCount(section) {
        if (section === "output")
            return panel.displaySinks.length;
        if (section === "input")
            return panel.displaySources.length;
        if (section === "streams")
            return panel.displayStreams.length;
        return 0;
    }

    function sectionVisible(section) {
        if (section === "output")
            return true;
        if (section === "input")
            return panel.displaySources.length > 0 || !!panel.source;
        if (section === "streams")
            return panel.displayStreams.length > 0;
        return false;
    }

    function sectionHasSlider(section) {
        if (section === "output")
            return true;
        if (section === "input")
            return !!panel.source;
        // Stream rows carry their own sliders inline.
        return false;
    }

    readonly property var visibleSections: {
        const list = [];
        if (panel.sectionVisible("output"))
            list.push("output");
        if (panel.sectionVisible("input"))
            list.push("input");
        if (panel.sectionVisible("streams"))
            list.push("streams");
        return list;
    }

    function moveCursor(delta) {
        const sections = panel.visibleSections;
        if (sections.length === 0)
            return;
        if (panel.focusSection === "header") {
            if (delta > 0) {
                panel.focusSection = sections[0];
                panel.selectedIndex = panel.sectionHasSlider(sections[0]) ? -1 : 0;
            }
            return;
        }
        const sectionIndex = sections.indexOf(panel.focusSection);
        if (sectionIndex < 0) {
            panel.focusSection = sections[0];
            panel.selectedIndex = panel.sectionHasSlider(panel.focusSection) ? -1 : 0;
            return;
        }

        const idx = panel.selectedIndex;
        const max = panel.sectionCount(panel.focusSection) - 1;
        const floor = panel.sectionHasSlider(panel.focusSection) ? -1 : 0;

        if (delta > 0) {
            if (idx < max) {
                panel.selectedIndex = idx + 1;
                return;
            }
            if (sectionIndex < sections.length - 1) {
                panel.focusSection = sections[sectionIndex + 1];
                panel.selectedIndex = panel.sectionHasSlider(panel.focusSection) ? -1 : 0;
            }
        } else {
            if (idx > floor) {
                panel.selectedIndex = idx - 1;
                return;
            }
            if (sectionIndex > 0) {
                panel.focusSection = sections[sectionIndex - 1];
                const prevMax = panel.sectionCount(panel.focusSection) - 1;
                panel.selectedIndex = prevMax >= 0 ? prevMax : (panel.sectionHasSlider(panel.focusSection) ? -1 : 0);
            } else {
                panel.focusSection = "header";
            }
        }
    }

    function setCursor(section, index) {
        panel.cursorActive = true;
        panel.focusSection = section;
        panel.selectedIndex = index;
    }

    // h/l on a slider row is a volume control; on a stream row it adjusts
    // that stream. On a device row it is a no-op — the cursor is on a
    // discrete row, and moving the global slider there would surprise.
    function adjustVolume(delta) {
        if (panel.focusSection === "output" && panel.selectedIndex === -1) {
            panel.setOutputVolume(panel.outputVolume + delta);
            return;
        }
        if (panel.focusSection === "input" && panel.selectedIndex === -1) {
            panel.setInputVolume(panel.inputVolume + delta);
            return;
        }
        if (panel.focusSection === "streams" && panel.selectedIndex >= 0 && panel.selectedIndex < panel.displayStreams.length) {
            const stream = panel.displayStreams[panel.selectedIndex];
            if (stream && stream.audio)
                panel.writeVolume(stream, stream.audio.volume + delta, 1.5);
        }
    }

    function activateCursor() {
        if (panel.focusSection === "header") {
            panel.toggleAllMuted();
            return;
        }
        if (panel.focusSection === "output") {
            if (panel.selectedIndex === -1)
                panel.toggleOutputMute();
            else
                panel.setDefaultSink(panel.displaySinks[panel.selectedIndex]);
            return;
        }
        if (panel.focusSection === "input") {
            if (panel.selectedIndex === -1)
                panel.toggleInputMute();
            else
                panel.setDefaultSource(panel.displaySources[panel.selectedIndex]);
            return;
        }
        if (panel.focusSection === "streams" && panel.selectedIndex >= 0)
            panel.toggleMute(panel.displayStreams[panel.selectedIndex]);
    }

    function muteAtCursor() {
        if (panel.focusSection === "streams" && panel.selectedIndex >= 0 && panel.selectedIndex < panel.displayStreams.length)
            panel.toggleMute(panel.displayStreams[panel.selectedIndex]);
        else if (panel.focusSection === "input")
            panel.toggleInputMute();
        else
            panel.toggleOutputMute();
    }

    // "header" is virtual and never appears in visibleSections, so it has to
    // be let through: muting republishes the snapshot, and clamping would
    // knock the cursor off the master switch on every toggle.
    function clampCursor() {
        const sections = panel.visibleSections;
        if (!sections.length || panel.focusSection === "header")
            return;
        if (sections.indexOf(panel.focusSection) < 0) {
            panel.focusSection = sections[0];
            panel.selectedIndex = panel.sectionHasSlider(panel.focusSection) ? -1 : 0;
            return;
        }
        const count = panel.sectionCount(panel.focusSection);
        const floor = panel.sectionHasSlider(panel.focusSection) ? -1 : 0;
        if (panel.selectedIndex > count - 1)
            panel.selectedIndex = Math.max(floor, count - 1);
        if (panel.selectedIndex < floor)
            panel.selectedIndex = floor;
    }

    // The first arrow press only reveals the cursor, as theirs does.
    function moveRequest(dx, dy) {
        if (!panel.cursorActive) {
            panel.cursorActive = true;
            return;
        }
        if (dy !== 0)
            panel.moveCursor(dy);
        else if (dx !== 0)
            panel.adjustVolume(dx * 0.05);
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            panel.moveRequest(0, 1);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            panel.moveRequest(0, -1);
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            panel.moveRequest(1, 0);
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            panel.moveRequest(-1, 0);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (panel.cursorActive)
                panel.activateCursor();
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_M:
            if (panel.cursorActive)
                panel.muteAtCursor();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // Keep the keyboard-focused row inside the viewport; j/k would otherwise
    // walk the selection off the bottom of the card.
    function ensureCursorVisible(item) {
        if (!item || !scroller.interactive)
            return;
        const margin = panel.theme.space(2);
        const maxY = Math.max(0, scroller.contentHeight - scroller.height);
        const top = item.mapToItem(sections, 0, 0).y;
        const bottom = top + item.height;
        if (top < scroller.contentY + margin)
            scroller.contentY = Math.max(0, Math.min(maxY, top - margin));
        else if (bottom > scroller.contentY + scroller.height - margin)
            scroller.contentY = Math.max(0, Math.min(maxY, bottom + margin - scroller.height));
    }

    // ------------------------------------------------------------- content
    Flickable {
        id: scroller

        width: parent.width
        height: Math.min(sections.implicitHeight, panel.height - panel.theme.barHeight - panel.theme.space(14))
        contentWidth: width
        contentHeight: sections.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: sections

            width: scroller.width
            spacing: panel.theme.space(3)

            // ------------------------------------------------------- hero
            PanelHero {
                theme: panel.theme
                width: parent.width
                title: "Audio"
                meta: panel.heroSubtitle.toUpperCase()
                metaWeight: Font.Normal

                icon: OpticalGlyph {
                    text: panel.outputIcon()
                    color: panel.theme.textPrimary
                    opacity: panel.outputMuted ? 0.5 : 1
                    pixelSize: panel.theme.fontPx(1.6)
                }

                // Master switch: checked while anything is still audible, so
                // muting everything reads as switching audio off.
                trailing: PanelSwitch {
                    theme: panel.theme
                    anchors.verticalCenter: parent.verticalCenter
                    checked: panel.anyAudible
                    hasCursor: panel.headerHasCursor
                    hint: panel.toggleHint
                    onHovered: panel.setCursor("header", -1)
                    onToggled: panel.toggleAllMuted()
                }
            }

            // ----------------------------------------------------- output
            Separator {
                theme: panel.theme
            }

            Column {
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "OUTPUT"
                    value: Math.round((outputSlider.dragging ? outputSlider.liveValue : panel.outputVolume) * 100) + "%"
                    dimmed: panel.outputMuted
                }

                CursorSurface {
                    id: outputSliderRow
                    theme: panel.theme

                    width: parent.width
                    implicitHeight: outputSlider.implicitHeight + panel.theme.space(1)
                    hasCursor: panel.cursorActive && panel.focusSection === "output" && panel.selectedIndex === -1
                    onHasCursorChanged: if (hasCursor)
                        panel.ensureCursorVisible(outputSliderRow)

                    HoverHandler {
                        onHoveredChanged: if (hovered)
                            panel.setCursor("output", -1)
                    }

                    PanelSlider {
                        id: outputSlider
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: panel.theme.space(2)
                        anchors.rightMargin: panel.theme.space(2)
                        anchors.verticalCenter: parent.verticalCenter
                        theme: panel.theme
                        enabled: panel.hasOutput
                        opacity: panel.outputMuted ? 0.5 : 1
                        value: panel.outputVolume
                        onMoved: v => panel.setOutputVolume(v)
                        onRightClicked: panel.toggleOutputMute()
                    }
                }

                Repeater {
                    model: panel.displaySinks

                    DeviceRow {
                        required property var modelData
                        required property int index

                        width: sections.width
                        node: modelData
                        rowIndex: index
                        section: "output"
                        glyph: Model.sinkGlyph(modelData)
                        isActive: panel.sink === modelData
                        onActivated: panel.setDefaultSink(modelData)
                    }
                }
            }

            // ------------------------------------------------------ input
            Separator {
                theme: panel.theme
                visible: panel.sectionVisible("input")
            }

            Column {
                width: parent.width
                spacing: panel.theme.space(1.5)
                visible: panel.sectionVisible("input")

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "INPUT"
                    value: panel.hasInput ? Math.round((inputSlider.dragging ? inputSlider.liveValue : panel.inputVolume) * 100) + "%" : "—"
                    dimmed: panel.inputMuted
                }

                CursorSurface {
                    id: inputSliderRow
                    theme: panel.theme

                    width: parent.width
                    visible: panel.hasInput
                    implicitHeight: inputControls.implicitHeight + panel.theme.space(1)
                    hasCursor: panel.cursorActive && panel.focusSection === "input" && panel.selectedIndex === -1
                    onHasCursorChanged: if (hasCursor)
                        panel.ensureCursorVisible(inputSliderRow)

                    HoverHandler {
                        onHoveredChanged: if (hovered)
                            panel.setCursor("input", -1)
                    }

                    Column {
                        id: inputControls
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: panel.theme.space(2)
                        anchors.rightMargin: panel.theme.space(2)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: panel.theme.space(1)

                        PanelSlider {
                            id: inputSlider
                            width: parent.width
                            theme: panel.theme
                            enabled: panel.hasInput
                            opacity: panel.inputMuted ? 0.5 : 1
                            value: panel.inputVolume
                            onMoved: v => panel.setInputVolume(v)
                            onRightClicked: panel.toggleInputMute()
                        }

                        // Live microphone level.
                        Rectangle {
                            width: parent.width
                            height: panel.theme.space(1)
                            radius: height / 2
                            color: panel.theme.alpha(panel.theme.textPrimary, 0.18)
                            opacity: panel.inputMuted ? 0.35 : 1

                            Rectangle {
                                height: parent.height
                                radius: height / 2
                                width: parent.width * Math.max(0, Math.min(1, inputPeak.peak))
                                color: panel.theme.accent

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 70
                                    }
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: panel.displaySources

                    DeviceRow {
                        required property var modelData
                        required property int index

                        width: sections.width
                        node: modelData
                        rowIndex: index
                        section: "input"
                        glyph: Model.sourceGlyph(modelData)
                        isActive: panel.source === modelData
                        onActivated: panel.setDefaultSource(modelData)
                    }
                }
            }

            // ---------------------------------------------------- streams
            Separator {
                theme: panel.theme
                visible: panel.displayStreams.length > 0
            }

            Column {
                width: parent.width
                spacing: panel.theme.space(1.5)
                visible: panel.displayStreams.length > 0

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "SOURCES"
                }

                Repeater {
                    model: panel.displayStreams

                    StreamRow {
                        required property var modelData
                        required property int index

                        width: sections.width
                        node: modelData
                        rowIndex: index
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- components
    // Output/input device row — click switches the PipeWire default.
    component DeviceRow: CursorSurface {
        id: deviceRow

        theme: panel.theme

        property var node: null
        property int rowIndex: 0
        property string section: "output"
        property string glyph: ""
        property bool isActive: false

        signal activated

        hasCursor: panel.cursorActive && panel.focusSection === section && panel.selectedIndex === rowIndex
        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(deviceRow)
        current: isActive
        implicitHeight: panel.theme.space(8)

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(2.5)

            OpticalGlyph {
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(5)
                text: deviceRow.glyph
                color: deviceRow.isActive ? panel.theme.accent : panel.theme.textPrimary
                pixelSize: panel.theme.fontPx(1.083)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - panel.theme.space(7.5)
                elide: Text.ElideRight
                text: panel.nodeLabel(deviceRow.node)
                color: deviceRow.isActive ? panel.theme.accent : panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
                font.weight: deviceRow.isActive ? Font.DemiBold : Font.Normal
            }
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                panel.setCursor(deviceRow.section, deviceRow.rowIndex)
        }

        TapHandler {
            onTapped: deviceRow.activated()
        }
    }

    // Per-application playback stream: name, own volume, own mute.
    component StreamRow: CursorSurface {
        id: streamRow

        theme: panel.theme

        property var node: null
        property int rowIndex: 0

        readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
        readonly property bool streamMuted: node && node.audio ? node.audio.muted : false
        readonly property bool isActive: Model.streamRepresentsPlayer(node, panel.activePlayer, panel.mprisPlayers, panel.displayStreams)

        hasCursor: panel.cursorActive && panel.focusSection === "streams" && panel.selectedIndex === rowIndex
        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(streamRow)
        current: isActive
        implicitHeight: streamColumn.implicitHeight + panel.theme.space(2)

        Column {
            id: streamColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(0.5)

            Item {
                width: parent.width
                height: streamName.implicitHeight + panel.theme.space(1)

                OpticalGlyph {
                    id: streamMuteIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.theme.space(5)
                    text: streamRow.streamMuted ? "󰝟" : "󰕾"
                    color: panel.theme.textPrimary
                    opacity: streamRow.streamMuted ? 0.5 : 1
                    pixelSize: panel.theme.fontPx(1.083)

                    TapHandler {
                        onTapped: panel.toggleMute(streamRow.node)
                    }
                }

                Text {
                    id: streamName
                    anchors.left: streamMuteIcon.right
                    anchors.leftMargin: panel.theme.space(2.5)
                    anchors.right: streamPercent.left
                    anchors.rightMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: panel.streamLabel(streamRow.node)
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    font.weight: streamRow.isActive ? Font.DemiBold : Font.Normal
                }

                Text {
                    id: streamPercent
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round((streamSlider.dragging ? streamSlider.liveValue : streamRow.streamVolume) * 100) + "%"
                    opacity: streamRow.streamMuted ? 0.5 : 1
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                    font.weight: Font.DemiBold
                }
            }

            PanelSlider {
                id: streamSlider
                width: parent.width
                theme: panel.theme
                // Streams may be boosted past unity, as they can in omarchy.
                maximum: 1.5
                opacity: streamRow.streamMuted ? 0.5 : 1
                value: streamRow.streamVolume
                onMoved: v => panel.writeVolume(streamRow.node, v, 1.5)
                onRightClicked: panel.toggleMute(streamRow.node)
            }
        }

        HoverHandler {
            onHoveredChanged: if (hovered)
                panel.setCursor("streams", streamRow.rowIndex)
        }
    }
}

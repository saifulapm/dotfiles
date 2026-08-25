import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "../../../components"
import "MonitorModel.js" as Model
import "NightLightModel.js" as NightModel

// Display panel — port of omarchy's monitor plugin on niri's IPC: a hero
// naming the current brightness mood, a live brightness slider per output
// that has a backlight, their scale presets filtered down to the ones this
// mode can actually land on, and the per-output enable rows.
//
// Night light lives here too, rather than in a panel of its own. Brightness
// and colour temperature are the same question — how this screen should look
// right now — and splitting them cost two bar widgets and two keybindings to
// answer it. The MODE radio and the warmth nudge are the night-light panel's,
// unchanged; what went away is its hero, which duplicated this one's job.
//
// One probe process gathers everything (`niri msg --json outputs`, the
// focused output and `brightnessctl -lm`), on their 5 s cadence and only
// while the panel is open. Brightness writes are debounced 180 ms like
// theirs, and the value we just wrote is authoritative — the probe never
// gets to bounce the slider back mid-drag. Night light is not part of that
// probe: NightLightService follows sunsetr's own stream and pushes.
BarPanel {
    id: panel

    panelTitle: ""
    cardWidth: theme.space(95)

    property var outputs: []
    property string focused: ""
    property var backlights: []

    // The shared NightLightService, threaded down through the bar the same
    // way autoBrightness is. Null until the bar hands it over, and every
    // night-light row is gated on it having probed a real sunsetr.
    property var nightlight: null
    readonly property bool nightLightAvailable: !!nightlight && nightlight.probed && nightlight.available
    readonly property var nightLightModes: NightModel.MODES

    // The shell's AutoBrightness service, threaded down from shell.qml
    // through the bar. Null on a panel opened before the service exists, and
    // the hero switch is gated on the service reporting BOTH an ambient-light
    // sensor and a battery — see AutoBrightness.available.
    property var autoBrightness: null
    readonly property bool autoBrightnessAvailable: !!autoBrightness && autoBrightness.available
    readonly property bool autoBrightnessOn: autoBrightnessAvailable && autoBrightness.enabled

    // Live brightness per backlight device, keyed by device name. Set locally
    // on every move so the slider is never fighting the probe.
    property var brightness: ({})
    property var pendingBrightness: ({})

    // Their preset row, plus the two fractional scales these machines
    // actually run: niri takes any fractional scale, so a preset only has to
    // be useful — 1.1 is the Mac mini's and 1.5 the MacBook's.
    readonly property var scalePresets: ["1", "1.1", "1.25", "1.5", "1.75", "2", "3"]
    readonly property var focusedOutput: outputs.find(o => o && o.name === focused) || outputs[0] || null

    readonly property var brightnessRows: {
        const rows = [];
        for (let i = 0; i < outputs.length; i++) {
            const device = Model.backlightForOutput(outputs[i].name, outputs, backlights);
            if (device)
                rows.push({
                    output: outputs[i].name,
                    device: device.device
                });
        }
        // External displays answer over DDC/CI instead (omarchy gap item 1):
        // same row, pseudo-device "ddc:<connector>", writes routed through
        // bin/brightness-display. A connector already carrying a backlight
        // row never doubles up.
        for (let i = 0; i < ddcOutputs.length; i++) {
            const name = ddcOutputs[i].output;
            if (!rows.some(r => r.output === name))
                rows.push({
                    output: name,
                    device: "ddc:" + name
                });
        }
        return rows;
    }
    property var ddcOutputs: []

    function percentFor(device) {
        const value = brightness[device];
        return value === undefined ? 0 : value;
    }

    readonly property int heroPercent: brightnessRows.length > 0 ? percentFor(brightnessRows[0].device) : -1
    // Live "58%" for the BRIGHTNESS header when there is exactly one row —
    // written by the row delegate, whose slider knows the drag-live value.
    property string brightnessHeaderText: ""

    // ------------------------------------------------------------- probing
    function refresh() {
        if (!stateProc.running)
            stateProc.running = true;
    }

    function applyState(raw) {
        const state = Model.parseState(raw);
        if (state.outputs.length === 0)
            return;
        outputs = state.outputs;
        focused = state.focused;
        backlights = state.backlights;
        ddcOutputs = state.ddc || [];

        // Adopt the hardware's values only for devices with no write in
        // flight — otherwise a probe landing mid-drag snaps the knob back.
        const next = Object.assign({}, brightness);
        for (let i = 0; i < state.backlights.length; i++) {
            const b = state.backlights[i];
            if (pendingBrightness[b.device] === undefined)
                next[b.device] = b.percent;
        }
        for (let i = 0; i < ddcOutputs.length; i++) {
            const d = ddcOutputs[i];
            const key = "ddc:" + d.output;
            if (pendingBrightness[key] === undefined)
                next[key] = d.percent;
        }
        brightness = next;
    }

    onPanelOpened: {
        refresh();
        cursorActive = false;
        // Probe-on-open, the night-light panel's contract: one snapshot
        // squares the rows with reality and re-arms a follower that gave up
        // while the daemon was down.
        if (nightlight)
            nightlight.refresh();
    }

    Process {
        id: stateProc
        command: ["bash", "-c", "echo '##outputs'; niri msg --json outputs; echo '##focused'; niri msg --json focused-output; echo '##backlights'; brightnessctl -lm --class=backlight 2>/dev/null; echo '##ddc'; if command -v ddcutil >/dev/null 2>&1; then niri msg --json outputs | jq -r 'keys[]' | while read -r o; do case \"$o\" in eDP*|LVDS*|DSI*) ;; *) p=$(brightness-display-ddc \"$o\" 2>/dev/null) && echo \"$o $p\";; esac; done; fi"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.applyState(text)
        }
    }

    Timer {
        interval: 5000
        running: panel.opened
        repeat: true
        onTriggered: panel.refresh()
    }

    // Re-probe shortly after an action so the panel shows what actually took.
    Timer {
        id: settleTimer
        interval: 600
        onTriggered: panel.refresh()
    }

    // ---------------------------------------------------------- brightness
    function previewBrightness(device, value) {
        const percent = Model.clampBrightness(value);
        const next = Object.assign({}, brightness);
        next[device] = percent;
        brightness = next;
        const pending = Object.assign({}, pendingBrightness);
        pending[device] = percent;
        pendingBrightness = pending;
        brightnessDebounce.restart();
    }

    function commitBrightness(device, value) {
        brightnessDebounce.stop();
        previewBrightnessImmediate(device, Model.clampBrightness(value));
    }

    function previewBrightnessImmediate(device, percent) {
        const next = Object.assign({}, brightness);
        next[device] = percent;
        brightness = next;
        const pending = Object.assign({}, pendingBrightness);
        pending[device] = percent;
        pendingBrightness = pending;
        flushBrightness();
    }

    // One write at a time through a real Process: a detached spawn gives no
    // exit signal, and clearing pendingBrightness before the write lands lets
    // a racing probe adopt the pre-write hardware value and snap the slider
    // back.
    function flushBrightness() {
        if (brightnessProc.running)
            return;
        const devices = Object.keys(pendingBrightness);
        if (devices.length === 0)
            return;
        const device = devices[0];
        brightnessProc.device = device;
        brightnessProc.writtenPercent = pendingBrightness[device];
        // ddc:<connector> pseudo-devices write over DDC/CI through the same
        // script the brightness keys use; real devices stay on brightnessctl.
        if (device.indexOf("ddc:") === 0)
            brightnessProc.command = ["brightness-display", "--no-osd", "--monitor", device.substring(4), pendingBrightness[device] + "%"];
        else
            brightnessProc.command = ["brightnessctl", "--class=backlight", "-d", device, "-q", "set", pendingBrightness[device] + "%"];
        brightnessProc.running = true;
    }

    Process {
        id: brightnessProc
        property string device: ""
        property int writtenPercent: -1
        onExited: {
            // Only clear if the slider has not moved on to a newer value.
            if (panel.pendingBrightness[device] === writtenPercent) {
                const pending = Object.assign({}, panel.pendingBrightness);
                delete pending[device];
                panel.pendingBrightness = pending;
            }
            panel.flushBrightness();
        }
    }

    Timer {
        id: brightnessDebounce
        interval: 180
        onTriggered: panel.flushBrightness()
    }

    // -------------------------------------------------------------- actions
    function setScale(name, scale) {
        Quickshell.execDetached(["niri", "msg", "output", name, "scale", String(scale)]);
        settleTimer.restart();
    }

    function setPower(name, on) {
        if (!on && Model.enabledCount(outputs) <= 1)
            return;
        Quickshell.execDetached(["niri", "msg", "output", name, on ? "on" : "off"]);
        settleTimer.restart();
    }

    // ------------------------------------------------------- cursor model
    // Their sections, with the display list only present when there is one:
    // j/k walks rows and falls through between sections, h/l adjusts the
    // brightness slider or walks the scale pills, Enter activates.
    property string focusSection: "brightness"
    property int selectedIndex: 0
    property bool cursorActive: false

    readonly property var scaleValues: scalePresets

    readonly property var visibleSections: {
        const list = [];
        if (brightnessRows.length > 0)
            list.push("brightness");
        if (nightLightAvailable)
            list.push("nightlight");
        list.push("scale");
        if (outputs.length > 1)
            list.push("displays");
        return list;
    }

    function sectionCount(section) {
        if (section === "brightness")
            return brightnessRows.length;
        if (section === "nightlight")
            return nightLightModes.length;
        if (section === "scale")
            return scaleValues.length;
        if (section === "displays")
            return outputs.length;
        return 0;
    }

    // The scale pills sit side by side, so j/k treats them as one row.
    function sectionIsSingleRow(section) {
        return section === "scale";
    }

    function moveCursor(delta) {
        const sections = visibleSections;
        if (sections.length === 0)
            return;
        const sIdx = sections.indexOf(focusSection);
        if (sIdx < 0) {
            focusSection = sections[0];
            selectedIndex = 0;
            return;
        }
        const single = sectionIsSingleRow(focusSection);
        const max = single ? 0 : sectionCount(focusSection) - 1;
        if (delta > 0) {
            if (!single && selectedIndex < max) {
                selectedIndex++;
                return;
            }
            if (sIdx < sections.length - 1) {
                focusSection = sections[sIdx + 1];
                selectedIndex = 0;
            }
        } else {
            if (!single && selectedIndex > 0) {
                selectedIndex--;
                return;
            }
            if (sIdx > 0) {
                const prev = sections[sIdx - 1];
                focusSection = prev;
                selectedIndex = sectionIsSingleRow(prev) ? 0 : Math.max(0, sectionCount(prev) - 1);
            }
        }
    }

    function moveCursorH(delta) {
        if (focusSection === "brightness") {
            const row = brightnessRows[selectedIndex];
            if (row)
                commitBrightness(row.device, percentFor(row.device) + delta * 5);
            return;
        }
        if (focusSection === "scale")
            selectedIndex = Math.max(0, Math.min(scaleValues.length - 1, selectedIndex + delta));
    }

    function activateCursor() {
        if (focusSection === "scale" && focusedOutput)
            setScale(focusedOutput.name, scaleValues[selectedIndex]);
        else if (focusSection === "nightlight") {
            // A radio, not a toggle: re-choosing the active mode is a no-op.
            const mode = nightLightModes[selectedIndex];
            if (mode && !(nightlight.running && mode.key === nightlight.modeKey))
                nightlight.setMode(mode.key);
        } else if (focusSection === "displays") {
            const out = outputs[selectedIndex];
            if (out)
                setPower(out.name, !Model.isEnabled(out));
        }
    }

    function takeCursor(section, index) {
        cursorActive = true;
        focusSection = section;
        selectedIndex = index;
    }

    onContentKey: event => {
        let dy = 0;
        let dx = 0;
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J)
            dy = 1;
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
            dy = -1;
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_L)
            dx = 1;
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
            dx = -1;

        if (dy !== 0 || dx !== 0) {
            if (!cursorActive)
                cursorActive = true;
            else if (dy !== 0)
                moveCursor(dy);
            else
                moveCursorH(dx);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (cursorActive)
                activateCursor();
            event.accepted = true;
        } else if (nightLightAvailable && (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight)) {
            // The night-light panel's warmth keys, kept: [ cooler, ] warmer.
            nightlight.nudgeNightTemp(event.key === Qt.Key_BracketLeft ? -100 : 100);
            event.accepted = true;
        }
    }

    // ------------------------------------------------------------- hero row
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Display"
        // A bare switch on a hero that says "Display" would read as a power
        // switch, which is not a mistake worth risking on a control that
        // hands the backlight over to a sensor. The meta line already names
        // the brightness; it names who is choosing it too.
        meta: {
            const mood = panel.heroPercent < 0 ? "FIXED BRIGHTNESS" : Model.brightnessName(panel.heroPercent).toUpperCase();
            return panel.autoBrightnessOn ? mood + " · AUTO" : mood;
        }

        // The bar mark, at hero size: the same sun/moon pair, so the panel
        // and the icon that opened it are recognisably one thing. A screen
        // glyph here named the hardware, which the DISPLAYS rows already do
        // and which was never what the hero is for.
        icon: OpticalGlyph {
            text: panel.nightLightAvailable && panel.nightlight.warm ? "󰖔" // md-weather_night
            : "󰖙" // md-white_balance_sunny
            color: panel.nightLightAvailable && panel.nightlight.running && panel.nightlight.forced ? panel.theme.accent : panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(2.0)
            verticalInkCenter: true
        }

        // Auto-brightness, the panel's headline control — the same slot the
        // audio, bluetooth and warp heroes put their one switch in. Present
        // only where the service has both an ambient-light sensor and a
        // battery to justify following it; invisible trailing controls take
        // no space, so the hero closes up on the machines without one.
        trailing: PanelSwitch {
            theme: panel.theme
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.autoBrightnessAvailable
            checked: panel.autoBrightnessOn
            hint: {
                const lux = panel.autoBrightness && panel.autoBrightness.smoothedLux >= 0 ? Math.round(panel.autoBrightness.smoothedLux) + " lx" : "no reading yet";
                return (panel.autoBrightnessOn ? "Stop following the ambient light" : "Follow the ambient light") + " — " + lux;
            }
            onToggled: {
                if (panel.autoBrightness)
                    panel.autoBrightness.setEnabled(!panel.autoBrightness.enabled);
            }
        }
    }

    Separator {
        theme: panel.theme
        visible: panel.brightnessRows.length > 0
    }

    // ---------------------------------------------------------- brightness
    Column {
        visible: panel.brightnessRows.length > 0
        width: parent.width
        spacing: panel.theme.space(2)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "BRIGHTNESS"
            // With a single backlight the per-row label line is one
            // right-aligned number on an otherwise empty line — carry the
            // value on the header instead, as the audio panel's OUTPUT does.
            value: panel.brightnessRows.length === 1 ? panel.brightnessHeaderText : ""
        }

        Repeater {
            model: panel.brightnessRows

            Column {
                id: brightnessRow

                required property var modelData
                required property int index

                readonly property bool hasCursor: panel.cursorActive && panel.focusSection === "brightness" && panel.selectedIndex === index
                readonly property string percentText: Math.round(slider.dragging ? slider.liveValue : panel.percentFor(modelData.device)) + "%"

                onPercentTextChanged: if (panel.brightnessRows.length === 1)
                    panel.brightnessHeaderText = percentText
                Component.onCompleted: if (panel.brightnessRows.length === 1)
                    panel.brightnessHeaderText = percentText

                width: parent.width
                spacing: panel.theme.space(1)

                // Only worth a line of its own when more than one output has
                // a backlight; a single display's number rides the header.
                Item {
                    visible: panel.brightnessRows.length > 1
                    width: parent.width
                    height: rowLabel.implicitHeight

                    StyledText {
                        id: rowLabel
                        theme: panel.theme
                        role: StyledText.Small
                        muted: true
                        anchors.left: parent.left
                        text: brightnessRow.modelData.output
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Small
                        mono: true
                        muted: true

                        anchors.right: parent.right
                        text: brightnessRow.percentText
                    }
                }

                Rectangle {
                    width: parent.width
                    height: slider.implicitHeight + panel.theme.space(1)
                    radius: panel.theme.radius(0.75)
                    color: brightnessRow.hasCursor ? panel.theme.alpha(panel.theme.accent, 0.12) : "transparent"

                    PanelSlider {
                        id: slider
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: panel.theme.space(1)
                        anchors.rightMargin: panel.theme.space(1)
                        theme: panel.theme
                        minimum: 1
                        maximum: 100
                        step: 5
                        value: panel.percentFor(brightnessRow.modelData.device)
                        onMoved: v => panel.previewBrightness(brightnessRow.modelData.device, v)
                    }

                    HoverHandler {
                        onHoveredChanged: if (hovered)
                            panel.takeCursor("brightness", brightnessRow.index)
                    }
                }
            }
        }
    }

    // Outputs with no backlight of their own: say why rather than showing a
    // dead slider.
    StyledText {
        theme: panel.theme
        role: StyledText.Small
        muted: true

        visible: panel.outputs.length > panel.brightnessRows.length
        width: parent.width
        text: panel.brightnessRows.length === 0 ? "No controllable backlight on this machine." : "External displays have no backlight control — they need DDC/CI."
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
        visible: panel.nightLightAvailable
    }

    // ---------------------------------------------------------- night light
    // The night-light panel's MODE radio and warmth nudge, next to brightness
    // because they answer the same question. Absent entirely without a
    // sunsetr on the machine — this bar's contract for an optional CLI.
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)
        visible: panel.nightLightAvailable

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "NIGHT LIGHT"
            // The schedule's next move, where there is one. A hold has none,
            // and says so rather than showing a stale time.
            value: {
                if (!panel.nightlight || !panel.nightlight.running)
                    return "OFF";
                return panel.nightlight.nextText !== "" ? panel.nightlight.nextText.toUpperCase() : "HELD";
            }
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Small

            visible: !!panel.nightlight && panel.nightlight.lastError !== ""
            width: parent.width
            text: panel.nightlight ? panel.nightlight.lastError : ""
            color: panel.theme.error
            wrapMode: Text.WordWrap
        }

        Column {
            id: nightRowColumn

            width: parent.width
            spacing: panel.theme.space(0.5)

            Repeater {
                model: panel.nightLightModes

                NightModeRow {
                    required property var modelData
                    required property int index

                    width: nightRowColumn.width
                    mode: modelData
                    rowIndex: index
                }
            }
        }

        // Only worth saying when it is the actionable fact; a running
        // schedule explains itself through the rows.
        StyledText {
            theme: panel.theme
            role: StyledText.Caption
            muted: true

            visible: !!panel.nightlight && !panel.nightlight.running
            width: parent.width
            text: "sunsetr is not running — choose a mode to start it."
            wrapMode: Text.WordWrap
        }
    }

    // ------------------------------------------------------ night warmth
    // Hidden under a day hold: the control would still write the config, but
    // nothing on the glass would move, and a slider that does nothing is
    // worse than no slider.
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)
        visible: panel.nightLightAvailable && panel.nightlight.running && panel.nightlight.modeKey !== "day"

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "NIGHT WARMTH"
            value: panel.nightlight ? NightModel.kelvinText(panel.nightlight.dayTemp) + " NEUTRAL" : ""
        }

        Item {
            width: parent.width
            implicitHeight: Math.max(warmerButton.implicitHeight, nudgeLabel.implicitHeight)

            NudgeButton {
                id: coolerButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰍶" // md-minus-circle-outline
                hint: "Cooler"
                delta: 100
            }

            StyledText {
                id: nudgeLabel

                theme: panel.theme
                anchors.centerIn: parent
                text: panel.nightlight ? NightModel.moodName(panel.nightlight.temp) : ""
                color: panel.theme.textPrimary
                elide: Text.ElideRight
            }

            NudgeButton {
                id: warmerButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰐗" // md-plus-circle-outline
                hint: "Warmer"
                delta: -100
            }
        }
    }

    Separator {
        theme: panel.theme
    }

    // --------------------------------------------------------------- scale
    Column {
        width: parent.width
        spacing: panel.theme.space(2)

        Item {
            width: parent.width
            height: scaleHeader.implicitHeight

            SectionHeader {
                id: scaleHeader
                theme: panel.theme
                width: parent.width
                anchors.left: parent.left
                label: "SCALE"
            }

            // SCALE only applies to the focused output, so name it once there
            // is more than one.
            StyledText {
                theme: panel.theme
                role: StyledText.Caption
                mono: true
                muted: true

                anchors.right: parent.right
                visible: panel.outputs.length > 1 && panel.focused !== ""
                text: panel.focused
            }
        }

        Row {
            id: scaleRow
            width: parent.width
            spacing: panel.theme.space(1.5)

            readonly property real cellWidth: panel.scaleValues.length > 0 ? (width - spacing * (panel.scaleValues.length - 1)) / panel.scaleValues.length : 0

            readonly property int activeIndex: {
                const out = panel.focusedOutput;
                if (!out || !out.logical)
                    return -1;
                return Model.matchingScaleIndex(panel.scaleValues, out.logical.scale);
            }

            Repeater {
                model: panel.scaleValues

                Pill {
                    required property string modelData
                    required property int index

                    width: scaleRow.cellWidth
                    label: modelData + "x"
                    isActive: scaleRow.activeIndex === index
                    hasCursor: panel.cursorActive && panel.focusSection === "scale" && panel.selectedIndex === index
                    onHovered: panel.takeCursor("scale", index)
                    onActivated: if (panel.focusedOutput)
                        panel.setScale(panel.focusedOutput.name, modelData)
                }
            }
        }
    }

    Separator {
        theme: panel.theme
        visible: panel.outputs.length > 0
    }

    // ------------------------------------------------------------ displays
    Column {
        width: parent.width
        spacing: panel.theme.space(2)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "DISPLAYS"
        }

        Repeater {
            model: panel.outputs

            Rectangle {
                id: outputRow

                required property var modelData
                required property int index

                readonly property bool powered: Model.isEnabled(modelData)
                readonly property bool isFocused: modelData.name === panel.focused
                readonly property bool canToggle: !powered || Model.enabledCount(panel.outputs) > 1
                readonly property bool hasCursor: panel.cursorActive && panel.focusSection === "displays" && panel.selectedIndex === index

                width: parent.width
                implicitHeight: outputInner.implicitHeight + panel.theme.space(3)
                radius: panel.theme.radius(0.75)
                color: hasCursor ? panel.theme.alpha(panel.theme.accent, 0.12) : (isFocused ? panel.theme.alpha(panel.theme.textPrimary, 0.05) : "transparent")
                opacity: canToggle ? 1 : 0.45

                Row {
                    id: outputInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: panel.theme.space(1.5)
                    anchors.rightMargin: panel.theme.space(1.5)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(2)

                    OpticalGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍹"
                        color: panel.theme.textPrimary
                        pixelSize: panel.theme.fontPx(1.333)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - panel.theme.space(9)

                        StyledText {
                            theme: panel.theme

                            width: parent.width
                            text: outputRow.modelData.name + (outputRow.isFocused ? " · focused" : "") + (outputRow.modelData.model && outputRow.modelData.model !== "Unknown" ? " · " + outputRow.modelData.model : "")
                            elide: Text.ElideRight
                        }

                        StyledText {
                            theme: panel.theme
                            role: StyledText.Caption
                            mono: true
                            muted: true

                            text: Model.modeLine(outputRow.modelData)
                        }
                    }

                    OpticalGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: outputRow.powered ? "󰄬" : ""
                        color: panel.theme.accent
                        pixelSize: panel.theme.fontPx(1.333)
                    }
                }

                HoverHandler {
                    cursorShape: outputRow.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onHoveredChanged: if (hovered)
                        panel.takeCursor("displays", outputRow.index)
                }

                TapHandler {
                    enabled: outputRow.canToggle
                    onTapped: panel.setPower(outputRow.modelData.name, !outputRow.powered)
                }
            }
        }
    }

    StyledText {
        theme: panel.theme
        muted: true

        visible: panel.outputs.length === 0
        text: "Querying outputs…"
    }

    // ---------------------------------------------------------- components
    // The night-light panel's ModeRow, unchanged except for reading this
    // panel's shared cursor (focusSection/selectedIndex) instead of its own.
    component NightModeRow: CursorSurface {
        id: row

        theme: panel.theme

        property var mode: null
        property int rowIndex: 0

        readonly property bool rowSelected: panel.cursorActive && panel.focusSection === "nightlight" && panel.selectedIndex === rowIndex
        readonly property bool isActive: !!panel.nightlight && panel.nightlight.running && !!mode && mode.key === panel.nightlight.modeKey

        hasCursor: rowSelected
        current: isActive
        implicitHeight: rowContent.implicitHeight + panel.theme.space(3)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse)
                panel.takeCursor("nightlight", row.rowIndex)
            // A radio, not a toggle: re-choosing the active mode is a no-op.
            onClicked: if (!row.isActive)
                panel.nightlight.setMode(row.mode.key)
        }

        PanelHint {
            theme: panel.theme
            visible: rowMouse.containsMouse && !row.isActive
            anchor: row
            above: true
            text: row.mode ? row.mode.detail : ""
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(rowMark.implicitHeight, rowLabels.implicitHeight, rowCheck.implicitHeight)

            // Fixed-width slot so the label column lines up across rows
            // whatever each glyph's ink width is.
            OpticalGlyph {
                id: rowMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(5)
                text: row.mode ? row.mode.glyph : ""
                verticalInkCenter: true
                color: row.isActive ? panel.theme.textPrimary : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.083)
            }

            Column {
                id: rowLabels

                anchors.left: rowMark.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: rowCheck.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                StyledText {
                    theme: panel.theme

                    width: parent.width
                    text: row.mode ? row.mode.label : ""
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true

                    width: parent.width
                    // The active row states the fact; the others state the
                    // offer. "Auto" showing its next transition is the one
                    // line in this panel that changes on its own.
                    text: {
                        if (!row.mode)
                            return "";
                        if (!row.isActive)
                            return row.mode.detail;
                        if (row.mode.key === "auto")
                            return panel.nightlight.nextText !== "" ? panel.nightlight.nextText : row.mode.detail;
                        return "Held — " + NightModel.kelvinText(panel.nightlight.temp);
                    }
                    color: row.isActive ? panel.theme.textPrimary : panel.theme.textMuted
                    elide: Text.ElideRight
                }
            }

            OpticalGlyph {
                id: rowCheck
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(4)
                text: row.isActive ? "󰄬" // md-check
                : ""
                verticalInkCenter: true
                color: panel.theme.accent
                pixelSize: panel.theme.fontPx(1.0)
            }
        }
    }

    // A bordered square holding one glyph. `delta` is signed the way sunsetr
    // counts: LOWER kelvin is warmer, so "warmer" carries a negative step.
    component NudgeButton: ChipSurface {
        id: chip

        property string glyph: ""
        property string hint: ""
        property int delta: 0

        theme: panel.theme
        implicitWidth: panel.theme.space(8)
        implicitHeight: panel.theme.space(7)
        // An action, not a choice — `chosen` never fires.
        pointerOver: chipMouse.containsMouse

        OpticalGlyph {
            anchors.centerIn: parent
            text: chip.glyph
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(1.0)
        }

        // A MouseArea rather than a TapHandler: a TapHandler's passive grab
        // lets the press fall through to anything underneath.
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.nightlight.nudgeNightTemp(chip.delta)
        }

        PanelHint {
            theme: panel.theme
            visible: chipMouse.containsMouse
            anchor: chip
            above: true
            text: chip.hint
        }
    }

    component Pill: ChipSurface {
        id: pill

        property string label: ""
        property bool isActive: false
        property bool selectable: true

        signal hovered
        signal activated

        theme: panel.theme
        implicitHeight: pillText.implicitHeight + panel.theme.space(2.5)
        chosen: pill.isActive
        pointerOver: pillHover.hovered
        interactive: pill.selectable

        StyledText {
            id: pillText
            theme: panel.theme
            role: StyledText.Small
            anchors.centerIn: parent
            text: pill.label
            color: pill.isActive ? panel.theme.accent : panel.theme.textPrimary
        }

        HoverHandler {
            id: pillHover
            enabled: pill.selectable
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                pill.hovered()
        }

        TapHandler {
            enabled: pill.selectable
            onTapped: pill.activated()
        }
    }
}

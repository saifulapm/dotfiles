import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "MonitorModel.js" as Model

// Display panel — port of omarchy's monitor plugin on niri's IPC: a hero
// naming the current brightness mood, a live brightness slider per output
// that has a backlight, their scale presets filtered down to the ones this
// mode can actually land on, a VRR toggle, and the per-output enable rows.
//
// One probe process gathers everything (`niri msg --json outputs`, the
// focused output, `brightnessctl -lm` and the wlsunset check), on their 5 s
// cadence and only while the panel is open. Brightness writes are debounced
// 180 ms like theirs, and the value we just wrote is authoritative — the
// probe never gets to bounce the slider back mid-drag.
BarPanel {
    id: panel

    panelTitle: ""
    cardWidth: theme.space(95)

    // The shell's night light service (Services/Nightlight.qml).
    property var nightlight: null

    property var outputs: []
    property string focused: ""
    property var backlights: []
    property bool nightLightAvailable: false
    readonly property bool nightLightOn: nightlight ? nightlight.enabled : false
    // wlsunset installed, a service to drive it, and a compositor that has not
    // already refused gamma control on this hardware.
    readonly property bool nightLightUsable: nightLightAvailable && !!nightlight

    // Live brightness per backlight device, keyed by device name. Set locally
    // on every move so the slider is never fighting the probe.
    property var brightness: ({})
    property var pendingBrightness: ({})

    // Their preset row, with 1.5 added: niri takes any fractional scale, and
    // 1.5 is both its common step and this machine's own.
    readonly property var scalePresets: ["1", "1.25", "1.5", "1.75", "2", "3"]
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
        return rows;
    }

    function percentFor(device) {
        const value = brightness[device];
        return value === undefined ? 0 : value;
    }

    readonly property int heroPercent: brightnessRows.length > 0 ? percentFor(brightnessRows[0].device) : -1

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
        nightLightAvailable = state.nightLight;

        // Adopt the hardware's values only for devices with no write in
        // flight — otherwise a probe landing mid-drag snaps the knob back.
        const next = Object.assign({}, brightness);
        for (let i = 0; i < state.backlights.length; i++) {
            const b = state.backlights[i];
            if (pendingBrightness[b.device] === undefined)
                next[b.device] = b.percent;
        }
        brightness = next;
    }

    onPanelOpened: {
        refresh();
        cursorActive = false;
    }

    Process {
        id: stateProc
        command: ["bash", "-c", "echo '##outputs'; niri msg --json outputs; echo '##focused'; niri msg --json focused-output; echo '##backlights'; brightnessctl -lm --class=backlight 2>/dev/null; echo '##nightlight'; command -v wlsunset >/dev/null && echo yes"]
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

    function setVrr(name, on) {
        Quickshell.execDetached(["niri", "msg", "output", name, "vrr", on ? "on" : "off"]);
        settleTimer.restart();
    }

    function setNightLight(on) {
        if (nightLightUsable)
            nightlight.setNightlight(on);
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
        list.push("scale");
        if (focusedOutput && focusedOutput.vrr_supported)
            list.push("vrr");
        if (nightLightUsable)
            list.push("nightlight");
        if (outputs.length > 1)
            list.push("displays");
        return list;
    }

    function sectionCount(section) {
        if (section === "brightness")
            return brightnessRows.length;
        if (section === "scale")
            return scaleValues.length;
        if (section === "vrr" || section === "nightlight")
            return 1;
        if (section === "displays")
            return outputs.length;
        return 0;
    }

    // The scale pills sit side by side, so j/k treats them as one row.
    function sectionIsSingleRow(section) {
        return section === "scale" || section === "vrr" || section === "nightlight";
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
        else if (focusSection === "vrr" && focusedOutput)
            setVrr(focusedOutput.name, !focusedOutput.vrr_enabled);
        else if (focusSection === "nightlight")
            setNightLight(!nightLightOn);
        else if (focusSection === "displays") {
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
        }
    }

    // ------------------------------------------------------------- hero row
    Item {
        width: parent.width
        height: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

        OpticalGlyph {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.outputs.length > 1 ? "󰍺" : "󰍹"
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(2.333)
        }

        Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: panel.theme.space(3)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(0.5)

            Text {
                width: parent.width
                text: "Display"
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(1.083)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: panel.heroPercent < 0 ? "FIXED BRIGHTNESS" : Model.brightnessName(panel.heroPercent).toUpperCase()
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.75)
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                elide: Text.ElideRight
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
            text: "BRIGHTNESS"
        }

        Repeater {
            model: panel.brightnessRows

            Column {
                id: brightnessRow

                required property var modelData
                required property int index

                readonly property bool hasCursor: panel.cursorActive && panel.focusSection === "brightness" && panel.selectedIndex === index

                width: parent.width
                spacing: panel.theme.space(1)

                Item {
                    width: parent.width
                    height: rowLabel.implicitHeight

                    Text {
                        id: rowLabel
                        anchors.left: parent.left
                        // Only worth naming the output when more than one has
                        // a backlight of its own.
                        visible: panel.brightnessRows.length > 1
                        text: brightnessRow.modelData.output
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.833)
                    }

                    Text {
                        anchors.right: parent.right
                        text: Math.round(slider.dragging ? slider.liveValue : panel.percentFor(brightnessRow.modelData.device)) + "%"
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontMono
                        font.pixelSize: panel.theme.fontPx(0.833)
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
    Text {
        visible: panel.outputs.length > panel.brightnessRows.length
        width: parent.width
        text: panel.brightnessRows.length === 0 ? "No controllable backlight on this machine." : "External displays have no backlight control — they need DDC/CI."
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.833)
        wrapMode: Text.WordWrap
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
                anchors.left: parent.left
                text: "SCALE"
            }

            // SCALE only applies to the focused output, so name it once there
            // is more than one.
            Text {
                anchors.right: parent.right
                visible: panel.outputs.length > 1 && panel.focused !== ""
                text: panel.focused
                color: panel.theme.textMuted
                font.family: panel.theme.fontMono
                font.pixelSize: panel.theme.fontPx(0.75)
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
    }

    // ----------------------------------------------------------------- vrr
    Column {
        width: parent.width
        spacing: panel.theme.space(2)

        SectionHeader {
            text: "VARIABLE REFRESH RATE"
        }

        Row {
            id: vrrRow

            readonly property bool supported: !!(panel.focusedOutput && panel.focusedOutput.vrr_supported)
            readonly property bool enabledNow: !!(panel.focusedOutput && panel.focusedOutput.vrr_enabled)
            readonly property real cellWidth: (width - panel.theme.space(1.5)) / 2

            width: parent.width
            spacing: panel.theme.space(1.5)

            Pill {
                width: vrrRow.cellWidth
                label: "Off"
                selectable: vrrRow.supported
                isActive: vrrRow.supported && !vrrRow.enabledNow
                hasCursor: panel.cursorActive && panel.focusSection === "vrr" && panel.selectedIndex === 0
                onHovered: panel.takeCursor("vrr", 0)
                onActivated: if (panel.focusedOutput)
                    panel.setVrr(panel.focusedOutput.name, false)
            }

            Pill {
                width: vrrRow.cellWidth
                label: "On"
                selectable: vrrRow.supported
                isActive: vrrRow.supported && vrrRow.enabledNow
                onHovered: panel.takeCursor("vrr", 0)
                onActivated: if (panel.focusedOutput)
                    panel.setVrr(panel.focusedOutput.name, true)
            }
        }

        InfoNote {

            theme: panel.theme
            visible: !(panel.focusedOutput && panel.focusedOutput.vrr_supported)
            text: "This display does not report variable refresh rate support."
        }
    }

    Separator {
        theme: panel.theme
    }

    // ---------------------------------------------------------- night light
    Column {
        width: parent.width
        spacing: panel.theme.space(2)

        SectionHeader {
            text: "NIGHT LIGHT"
        }

        Row {
            id: nightLightRow

            readonly property real cellWidth: (width - panel.theme.space(1.5)) / 2

            width: parent.width
            spacing: panel.theme.space(1.5)

            Pill {
                width: nightLightRow.cellWidth
                label: "Off"
                selectable: panel.nightLightUsable
                isActive: !panel.nightLightOn
                hasCursor: panel.cursorActive && panel.focusSection === "nightlight" && panel.selectedIndex === 0
                onHovered: panel.takeCursor("nightlight", 0)
                onActivated: panel.setNightLight(false)
            }

            Pill {
                width: nightLightRow.cellWidth
                label: "On"
                selectable: panel.nightLightUsable
                isActive: panel.nightLightOn
                hasCursor: panel.cursorActive && panel.focusSection === "nightlight" && panel.selectedIndex === 0
                onHovered: panel.takeCursor("nightlight", 0)
                onActivated: panel.setNightLight(true)
            }
        }

        InfoNote {

            theme: panel.theme
            visible: text !== ""
            text: {
                if (!panel.nightLightAvailable)
                    return "wlsunset is not installed, so night light cannot be switched.";
                if (panel.nightlight && !panel.nightlight.gammaSupported)
                    return "This display reports no gamma table, so wlsunset runs but the colors do not change.";
                return "";
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
            text: "DISPLAYS"
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

                        Text {
                            width: parent.width
                            text: outputRow.modelData.name + (outputRow.isFocused ? " · focused" : "") + (outputRow.modelData.model && outputRow.modelData.model !== "Unknown" ? " · " + outputRow.modelData.model : "")
                            color: panel.theme.textPrimary
                            font.family: panel.theme.fontUi
                            font.pixelSize: panel.theme.fontPx(0.917)
                            elide: Text.ElideRight
                        }

                        Text {
                            text: Model.modeLine(outputRow.modelData)
                            color: panel.theme.textMuted
                            font.family: panel.theme.fontMono
                            font.pixelSize: panel.theme.fontPx(0.75)
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

    Text {
        visible: panel.outputs.length === 0
        text: "Querying outputs…"
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.917)
    }

    // ---------------------------------------------------------- components
    component SectionHeader: Text {
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.75)
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }

    component Pill: Rectangle {
        id: pill

        property string label: ""
        property bool isActive: false
        property bool hasCursor: false
        property bool selectable: true

        signal hovered
        signal activated

        implicitHeight: pillText.implicitHeight + panel.theme.space(2.5)
        radius: panel.theme.radius(0.75)
        color: isActive ? panel.theme.alpha(panel.theme.accent, 0.25) : (hasCursor || pillHover.hovered ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2)
        border.width: panel.theme.borderWidth
        border.color: isActive || hasCursor ? panel.theme.accent : panel.theme.surface3
        opacity: selectable ? 1 : 0.45

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.isActive ? panel.theme.accent : panel.theme.textPrimary
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.833)
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

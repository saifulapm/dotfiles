import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../components"
import "../../../components"
import "BluetoothModel.js" as Model

// AirPods panel — a hero of the pods with their BlueZ alias and live ear
// state, a battery bar per component (left, right, case), and the noise-mode
// picker in the power panel's profile-cell shape: hover or h/l parks the
// cursor, Enter or a click applies, the active mode wears the accent.
//
// Everything on screen is the librepods daemon's own state relayed through
// LibrePodsService; a click is optimistic and the device's ack re-confirms
// it a beat later through the same stream.
BarPanel {
    id: panel

    panelTitle: ""
    cardWidth: theme.space(80)

    required property var service

    // The stream carries the address; BlueZ carries the human name the user
    // may have set. Fall back rather than render an empty hero on the frame
    // between connect and BlueZ's device list catching up.
    readonly property var btDevice: {
        const devices = Bluetooth.devices ? Bluetooth.devices.values : [];
        return devices.find(d => d && String(d.address).toUpperCase() === panel.service.address) || null;
    }
    readonly property string deviceName: btDevice ? (btDevice.name || "AirPods") : "AirPods"

    // The daemon omits a component it is not hearing from, so an empty
    // battery object is the disconnected case rather than a zeroed one.
    readonly property bool hasBattery: {
        const battery = panel.service.battery;
        return !!battery && Object.keys(battery).length > 0;
    }

    readonly property string earText: {
        const left = panel.service.leftInEar, right = panel.service.rightInEar;
        if (left && right)
            return "Both in ear";
        if (left || right)
            return "One in ear";
        return "Not in ear";
    }

    // ------------------------------------------------------- noise picker
    // Display in intensity order; the service speaks librepods ints.
    //
    // Transparency and ANC wear md-ear_hearing and md-ear_hearing_off: one
    // pair, one negation, readable as opposites at 14 px. They used to be
    // md-headphones_box and md-headphones_settings, adjacent codepoints that
    // draw as near-identical headphone squares — the two cells a user most
    // needs to tell apart were the two that looked the same.
    readonly property var allModes: [
        {
            mode: 0,
            label: "Off",
            glyph: "󰝟"
        },
        {
            mode: 2,
            label: "Transparency",
            glyph: "󰟅"
        },
        {
            mode: 3,
            label: "Adaptive",
            glyph: "󰧑"
        },
        {
            mode: 1,
            label: "ANC",
            glyph: "󰩅"
        }
    ]

    // The device decides which of those it actually has. A chip the hardware
    // silently refuses is worse than a missing one: it looks like the panel
    // is broken rather than like the mode does not exist.
    readonly property var modes: panel.allModes.filter(entry => {
        if (entry.mode === 0)
            return panel.service.supportsNoiseOff;
        if (entry.mode === 3)
            return panel.service.proControls;
        return true;
    })

    // The adaptive level is a property of adaptive mode, and the daemon's
    // setter is a no-op in any other, so the slider only exists there.
    readonly property bool adaptiveVisible: panel.service.proControls && panel.service.noise === 3
    readonly property int adaptiveStep: 5

    // Rebuilt whenever a section appears or leaves, so j/k never park on a
    // control that is not drawn.
    readonly property var rows: {
        const list = ["modes"];
        if (panel.adaptiveVisible)
            list.push("adaptive");
        if (panel.service.proControls) {
            list.push("ca");
            list.push("onebud");
        }
        list.push("ear");
        return list;
    }

    property int rowIndex: 0
    readonly property string cursorRow: panel.rows[Math.max(0, Math.min(panel.rowIndex, panel.rows.length - 1))]
    function rowHasCursor(name) {
        return panel.cursorActive && panel.cursorRow === name;
    }

    // Which mode chip the cursor sits on, once the cursor is on the mode row.
    property int cursorIndex: 0
    property bool cursorActive: false

    onPanelOpened: {
        cursorActive = false;
        rowIndex = 0;
        const current = panel.modes.findIndex(m => m.mode === panel.service.noise);
        cursorIndex = current >= 0 ? current : 0;
    }

    // The power panel's keyboard model, one axis wider now that the modes are
    // not the only thing here: the first arrow press parks the cursor, j/k
    // walk the rows, h/l walk the mode chips or nudge the adaptive level, and
    // Enter applies whatever the cursor sits on.
    onContentKey: event => {
        const key = event.key;
        let vertical = 0;
        if (key === Qt.Key_Up || key === Qt.Key_K)
            vertical = -1;
        else if (key === Qt.Key_Down || key === Qt.Key_J)
            vertical = 1;

        let horizontal = 0;
        if (key === Qt.Key_Left || key === Qt.Key_H)
            horizontal = -1;
        else if (key === Qt.Key_Right || key === Qt.Key_L)
            horizontal = 1;

        if (vertical !== 0 || horizontal !== 0) {
            if (!panel.cursorActive) {
                panel.cursorActive = true;
            } else if (vertical !== 0) {
                panel.rowIndex = Math.min(panel.rows.length - 1, Math.max(0, panel.rowIndex + vertical));
            } else if (panel.cursorRow === "modes") {
                panel.cursorIndex = Math.min(panel.modes.length - 1, Math.max(0, panel.cursorIndex + horizontal));
            } else if (panel.cursorRow === "adaptive") {
                panel.service.setAdaptiveNoise(panel.service.adaptiveNoise + horizontal * panel.adaptiveStep);
            }
            event.accepted = true;
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (panel.cursorActive)
                panel.activateRow();
            event.accepted = true;
        }
    }

    function activateRow() {
        switch (panel.cursorRow) {
        case "modes":
            // The list shrinks on a device without Off or without Adaptive,
            // and the cursor may still be sitting past the new end.
            const chip = panel.modes[panel.cursorIndex];
            if (chip)
                panel.service.setNoise(chip.mode);
            break;
        case "ca":
            panel.service.setConversationalAwareness(!panel.service.conversationalAwareness);
            break;
        case "onebud":
            panel.service.setOneBudANC(!panel.service.oneBudANC);
            break;
        case "ear":
            panel.service.cycleEarDetection();
            break;
        }
    }

    function focusRow(name) {
        const at = panel.rows.indexOf(name);
        if (at < 0)
            return;
        panel.cursorActive = true;
        panel.rowIndex = at;
    }

    // -------------------------------------------------------------- hero
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: panel.deviceName
        meta: (panel.service.connected ? panel.earText : "Disconnected").toUpperCase()
        metaFamily: panel.theme.fontUi

        icon: OpticalGlyph {
            text: "󱡏"
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(2)
        }

        // No trailing mode text: the picker below already carries the active
        // mode in accent, and saying it twice reads as clutter (user call,
        // 2026-08-11).
    }

    Separator {
        theme: panel.theme
    }

    // ------------------------------------------------------------ battery
    // Every row here can be absent at once — disconnected pods report no
    // component at all — and a BATTERY heading over nothing reads as a panel
    // that failed rather than one with nothing to say.
    SectionHeader {
        theme: panel.theme
        width: parent.width
        label: "BATTERY"
        visible: panel.hasBattery
    }

    Column {
        width: parent.width
        visible: panel.hasBattery
        spacing: panel.theme.space(2)

        Repeater {
            model: [
                {
                    key: "left",
                    label: "Left",
                    inEar: panel.service.leftInEar
                },
                {
                    key: "right",
                    label: "Right",
                    inEar: panel.service.rightInEar
                },
                {
                    key: "case",
                    label: "Case",
                    inEar: false
                },
                {
                    key: "single",
                    label: "Pods",
                    inEar: panel.service.leftInEar
                }
            ]

            Column {
                required property var modelData

                // A component the device is not reporting (case out of range,
                // no "single" on stereo pods) simply has no row.
                readonly property var reading: panel.service.battery[modelData.key] || null
                visible: reading !== null
                width: parent.width
                spacing: panel.theme.space(0.75)

                Item {
                    width: parent.width
                    height: rowLabel.implicitHeight

                    StyledText {
                        id: rowLabel
                        theme: panel.theme
                        anchors.left: parent.left
                        text: parent.parent.modelData.label + (parent.parent.modelData.inEar ? "  ·  in ear" : "")
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Small
                        mono: true
                        muted: true

                        anchors.right: parent.right
                        text: parent.parent.reading ? parent.parent.reading.level + "%" + (parent.parent.reading.charging ? " 󰂄" : "") : ""
                        font.weight: Font.DemiBold
                    }
                }

                Item {
                    width: parent.width
                    height: panel.theme.space(1.25)

                    Rectangle {
                        id: track
                        anchors.fill: parent
                        radius: height / 2
                        color: panel.theme.alpha(panel.theme.textPrimary, 0.12)
                    }

                    Rectangle {
                        anchors.left: track.left
                        anchors.verticalCenter: track.verticalCenter
                        height: track.height
                        radius: track.radius
                        color: parent.parent.reading && parent.parent.reading.level <= 20 ? panel.theme.danger : panel.theme.accent
                        width: parent.parent.reading ? Math.max(track.height, track.width * parent.parent.reading.level / 100) : 0

                        Behavior on width {
                            NumberAnimation {
                                duration: panel.theme.time(2.13)
                                easing.type: panel.theme.motion.easing
                            }
                        }
                    }
                }
            }
        }
    }

    // Goes with the battery block above it, or the hero would sit under two
    // rules in a row with nothing between them.
    Separator {
        theme: panel.theme
        visible: panel.hasBattery
    }

    // -------------------------------------------------------- noise modes
    SectionHeader {
        theme: panel.theme
        width: parent.width
        label: "NOISE CONTROL"
    }

    Row {
        id: modeRow
        width: parent.width
        spacing: panel.theme.space(1.5)

        readonly property real cellWidth: (width - spacing * (panel.modes.length - 1)) / panel.modes.length

        Repeater {
            model: panel.modes

            ChipSurface {
                id: modeCell

                required property var modelData
                required property int index

                readonly property bool isActive: panel.service.noise === modelData.mode

                theme: panel.theme
                width: modeRow.cellWidth
                implicitHeight: modeContent.implicitHeight + panel.theme.space(3)
                chosen: modeCell.isActive
                hasCursor: panel.rowHasCursor("modes") && panel.cursorIndex === index
                pointerOver: cellHover.hovered

                Column {
                    id: modeContent
                    anchors.centerIn: parent
                    spacing: panel.theme.space(0.5)

                    OpticalGlyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modeCell.modelData.glyph
                        color: modeCell.isActive ? panel.theme.accent : panel.theme.textPrimary
                        pixelSize: panel.theme.fontPx(1.167)
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Caption

                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modeCell.modelData.label
                        color: modeCell.isActive ? panel.theme.accent : panel.theme.textPrimary
                    }
                }

                HoverHandler {
                    id: cellHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered) {
                        panel.focusRow("modes");
                        panel.cursorIndex = modeCell.index;
                    }
                }

                TapHandler {
                    onTapped: panel.service.setNoise(modeCell.modelData.mode)
                }
            }
        }
    }

    // How much of the world adaptive mode lets through. Only drawn in that
    // mode, because the daemon's setter is a no-op in any other and a slider
    // that silently does nothing is worse than no slider.
    Column {
        width: parent.width
        visible: panel.adaptiveVisible
        spacing: panel.theme.space(1)

        Item {
            width: parent.width
            height: adaptiveLabel.implicitHeight

            StyledText {
                id: adaptiveLabel
                theme: panel.theme
                role: StyledText.Small
                muted: true
                anchors.left: parent.left
                text: "ADAPTIVE NOISE"
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Small
                mono: true
                muted: true
                anchors.right: parent.right
                text: panel.service.adaptiveNoise + "%"
                font.weight: Font.DemiBold
            }
        }

        PanelSlider {
            width: parent.width
            theme: panel.theme
            minimum: 0
            maximum: 100
            step: panel.adaptiveStep
            value: panel.service.adaptiveNoise
            onMoved: v => panel.service.setAdaptiveNoise(v)
        }
    }

    Separator {
        theme: panel.theme
        visible: panel.service.proControls
    }

    // The two Pro switches. Both are the pods' own settings, not ours — they
    // persist in the buds and macOS shows the same pair.
    Column {
        width: parent.width
        visible: panel.service.proControls
        spacing: panel.theme.space(1)

        SwitchRow {
            width: parent.width
            rowName: "ca"
            label: "Conversation Awareness"
            caption: "Lower the volume when you start talking"
            checked: panel.service.conversationalAwareness
            onToggled: panel.service.setConversationalAwareness(!panel.service.conversationalAwareness)
        }

        SwitchRow {
            width: parent.width
            rowName: "onebud"
            label: "One-Bud ANC"
            caption: "Keep noise cancellation on with one pod in"
            checked: panel.service.oneBudANC
            onToggled: panel.service.setOneBudANC(!panel.service.oneBudANC)
        }
    }

    Separator {
        theme: panel.theme
    }

    // Ear detection is the one control here the pods do not own: it is what
    // the daemon does to playback when a pod comes out, so it applies to every
    // model and survives in the daemon's own settings.
    CursorSurface {
        id: earRow
        theme: panel.theme
        width: parent.width
        implicitHeight: earLabel.implicitHeight + panel.theme.space(3)
        hasCursor: panel.rowHasCursor("ear")

        StyledText {
            id: earLabel
            theme: panel.theme
            anchors.left: parent.left
            anchors.leftMargin: panel.theme.space(1.5)
            anchors.verticalCenter: parent.verticalCenter
            text: "Ear detection"
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Small
            muted: true
            anchors.right: parent.right
            anchors.rightMargin: panel.theme.space(1.5)
            anchors.verticalCenter: parent.verticalCenter
            text: panel.service.earBehaviorName
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                panel.focusRow("ear")
        }

        TapHandler {
            onTapped: panel.service.cycleEarDetection()
        }
    }

    // The daemon owns every fact above; without it the panel is a ghost, so
    // say why rather than letting the picker look broken.
    InfoNote {
        theme: panel.theme
        visible: !panel.service.connected
        text: "AirPods not connected, or librepods.service is not running."
    }

    // Label, one line of what it actually does, and the shell's own switch.
    // The whole row is the target — the switch alone is a small thing to hit,
    // and the caption is the part that explains it.
    component SwitchRow: CursorSurface {
        id: switchRow

        required property string rowName
        property string label: ""
        property string caption: ""
        property bool checked: false

        signal toggled

        theme: panel.theme
        implicitHeight: switchText.implicitHeight + panel.theme.space(3)
        hasCursor: panel.rowHasCursor(switchRow.rowName)

        Column {
            id: switchText
            anchors.left: parent.left
            anchors.leftMargin: panel.theme.space(1.5)
            anchors.right: rowSwitch.left
            anchors.rightMargin: panel.theme.space(1.5)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(0.25)

            StyledText {
                theme: panel.theme
                width: parent.width
                text: switchRow.label
                elide: Text.ElideRight
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Caption
                muted: true
                width: parent.width
                text: switchRow.caption
                elide: Text.ElideRight
            }
        }

        // Deliberately NOT wired to `toggled`. PanelSwitch carries its own
        // TapHandler, and pointer handlers do not consume a tap the way a
        // MouseArea does — both it and the row's handler below fire for a tap
        // that lands on the switch. That ran the setter twice, the second call
        // reading the value the first had already flipped optimistically, so
        // clicking the switch itself toggled and untoggled and looked dead
        // while clicking the row worked. The row owns the gesture; the switch
        // is the indicator.
        PanelSwitch {
            id: rowSwitch
            theme: panel.theme
            anchors.right: parent.right
            anchors.rightMargin: panel.theme.space(1.5)
            anchors.verticalCenter: parent.verticalCenter
            checked: switchRow.checked
            hasCursor: switchRow.hasCursor
            onHovered: panel.focusRow(switchRow.rowName)
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                panel.focusRow(switchRow.rowName)
        }

        TapHandler {
            onTapped: switchRow.toggled()
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../components"
import "PowerModel.js" as Model

// Power panel — full port of omarchy's power plugin Panel.qml in our tokens:
// a hero of the battery glyph, a rotating status phrase and the percentage
// over a charge bar that pulses while current is flowing in, then the battery
// facts as label/value pairs, the live system vitals, and the power-profile
// picker.
//
// Everything UPower publishes comes from UPower. The rest — charge cycles,
// the charge limit, kernel health, CPU/memory/load/temperature — comes from
// one `bin/system-stats` run, sampled on their 5 s cadence and ONLY while the
// panel is open.
BarPanel {
    id: panel

    panelTitle: ""
    cardWidth: 380

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"

    // ------------------------------------------------------------- battery
    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isPresent
    readonly property bool onBattery: UPower.onBattery

    readonly property var states: ({
            Charging: UPowerDeviceState.Charging,
            Discharging: UPowerDeviceState.Discharging,
            FullyCharged: UPowerDeviceState.FullyCharged,
            PendingCharge: UPowerDeviceState.PendingCharge
        })

    readonly property real batteryFraction: Model.batteryFraction(device)
    readonly property int pct: Math.round(batteryFraction * 100)
    readonly property bool chargeThresholdActive: Model.chargeThresholdActive(device, onBattery, states)
    readonly property bool fullyCharged: present && device.state === UPowerDeviceState.FullyCharged && !chargeThresholdActive
    readonly property bool discharging: present && onBattery
    readonly property bool batteryFull: fullyCharged || (!discharging && batteryFraction >= 1)
    readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive
    readonly property bool charging: present && !onBattery && !batteryFlowIdle

    readonly property string batteryIcon: Model.batteryIcon(device, onBattery, states)

    readonly property string rateText: present ? Model.formatWatts(device.changeRate) : ""
    readonly property string sizeText: present ? Model.formatCapacity(device.energyCapacity) : ""
    readonly property string timeText: {
        if (!present)
            return "";
        return Model.formatDuration(discharging ? device.timeToEmpty : device.timeToFull);
    }

    // Cute agent-flavoured phrases for the hero status line, rotated while
    // current is flowing either way so the panel feels alive.
    readonly property var chargingPhrases: ["Pumping power", "Injecting electrons", "Pouring juice", "Amassing watts", "Hoarding joules", "Sucking volts", "Topping reserves", "Soaking amps", "Inhaling kilowatts"]
    readonly property var onBatteryPhrases: ["Slurping power", "Spending joules", "Draining watts", "Burning electrons", "Sipping juice", "Spending coulombs", "Bleeding amps", "Guzzling volts", "Munching reserves"]
    property int phraseIndex: 0

    readonly property var activePhrases: {
        if (fullyCharged)
            return [];
        if (charging)
            return chargingPhrases;
        if (discharging)
            return onBatteryPhrases;
        return [];
    }
    readonly property bool rotatingPhrases: activePhrases.length > 0

    readonly property string heroStatusText: {
        if (fullyCharged)
            return "Fully charged";
        if (rotatingPhrases)
            return activePhrases[phraseIndex % activePhrases.length];
        return Model.modeLabel(device, onBattery, states);
    }

    // ------------------------------------------------------- system vitals
    property var systemInfo: ({})
    readonly property bool profilesAvailable: String(systemInfo.power_profiles || "") !== "missing"

    function applyStats(raw) {
        const next = Model.parseKeyValue(raw);
        // Keep the last known good sample if a run briefly returns nothing —
        // otherwise the section collapses mid-transition.
        if (Object.keys(next).length === 0)
            return;
        systemInfo = next;
    }

    function refresh() {
        if (!statsProc.running)
            statsProc.running = true;
    }

    onPanelOpened: {
        refresh();
        cursorActive = false;
        profileIndex = Math.max(0, profileNames.indexOf(activeProfileName));
    }

    Process {
        id: statsProc
        command: [panel.binDir + "system-stats"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.applyStats(text)
        }
    }

    Timer {
        interval: 5000
        running: panel.opened
        repeat: true
        onTriggered: panel.refresh()
    }

    // The phrase swap is wrapped in a fade so the changeover reads as one
    // organism rather than a hard cut.
    PhraseRotator {
        theme: panel.theme
        target: heroStatus
        running: panel.opened && panel.rotatingPhrases
        onAdvance: {
            const n = panel.activePhrases.length;
            if (n > 0)
                panel.phraseIndex = (panel.phraseIndex + 1) % n;
        }
    }

    // ------------------------------------------------------------ profiles
    readonly property var profileNames: ["power-saver", "balanced", "performance"]
    readonly property var profileValues: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
    readonly property string activeProfileName: {
        const idx = profileValues.indexOf(PowerProfiles.profile);
        return idx >= 0 ? profileNames[idx] : "";
    }
    property int profileIndex: 1
    property bool cursorActive: false

    function setProfile(index) {
        if (!profilesAvailable || index < 0 || index >= profileValues.length)
            return;
        PowerProfiles.profile = profileValues[index];
    }

    // Their keyboard model: the first arrow press parks the cursor, later
    // ones walk the profile row, Enter activates what it sits on.
    onContentKey: event => {
        let delta = 0;
        if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Up || event.key === Qt.Key_K)
            delta = -1;
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Down || event.key === Qt.Key_J)
            delta = 1;

        if (delta !== 0) {
            if (!cursorActive)
                cursorActive = true;
            else
                profileIndex = Model.selectProfileIndex(profileIndex, delta, profileNames);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (cursorActive)
                setProfile(profileIndex);
            event.accepted = true;
        }
    }

    // ------------------------------------------------------------- hero row
    Item {
        width: parent.width
        height: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

        OpticalGlyph {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.batteryIcon || "󰂑"
            color: panel.theme.textPrimary
            pixelSize: 28
        }

        Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: panel.theme.space(3)
            anchors.right: heroPercent.left
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(0.5)

            Text {
                width: parent.width
                text: "Battery"
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(1.083)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                id: heroStatus
                width: parent.width
                text: panel.heroStatusText.toUpperCase()
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.75)
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                elide: Text.ElideRight
            }
        }

        Text {
            id: heroPercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: panel.present ? panel.pct + "%" : "—"
            color: panel.theme.textPrimary
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(1.833)
            font.weight: Font.DemiBold
        }
    }

    // ---------------------------------------------------------- charge bar
    Item {
        width: parent.width
        height: panel.theme.space(2)

        Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: panel.theme.alpha(panel.theme.textPrimary, 0.12)
        }

        Rectangle {
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: panel.theme.textPrimary
            width: Math.max(barTrack.height, barTrack.width * panel.batteryFraction)

            Behavior on width {
                NumberAnimation {
                    duration: 320
                    easing.type: Easing.OutCubic
                }
            }

            // Subtle pulse while charging — a visible signal that energy is
            // flowing in.
            SequentialAnimation on opacity {
                running: panel.charging && !panel.fullyCharged && panel.opened
                loops: Animation.Infinite
                alwaysRunToEnd: true

                NumberAnimation {
                    from: 1.0
                    to: 0.55
                    duration: 950
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    from: 0.55
                    to: 1.0
                    duration: 950
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    Text {
        visible: !panel.present
        text: "No battery — on mains power"
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.917)
    }

    // ------------------------------------------------------- battery facts
    Row {
        visible: panel.present
        width: parent.width
        spacing: panel.theme.space(5)

        Column {
            width: (parent.width - parent.spacing) / 2
            spacing: panel.theme.space(1)

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: "Battery size"
                value: panel.sizeText
            }

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: "Charge cycles"
                value: panel.systemInfo.cycles || "—"
            }

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: "Health"
                value: {
                    if (panel.present && panel.device.healthSupported)
                        return Math.round(panel.device.healthPercentage) + "%";
                    return panel.systemInfo.health || "—";
                }
            }
        }

        Column {
            width: (parent.width - parent.spacing) / 2
            spacing: panel.theme.space(1)

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: panel.chargeThresholdActive ? "Charge limit" : (panel.discharging ? "Time left" : "Time to full")
                value: panel.chargeThresholdActive ? (panel.systemInfo.threshold || "-") : (panel.batteryFlowIdle ? "-" : (panel.timeText || "—"))
            }

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: panel.chargeThresholdActive ? "Battery state" : (panel.discharging ? "Discharging" : "Charging")
                value: panel.chargeThresholdActive ? "Holding" : (panel.batteryFull ? "-" : (panel.rateText || "—"))
            }

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                visible: !panel.chargeThresholdActive && panel.systemInfo.threshold !== undefined
                label: "Charge limit"
                value: panel.systemInfo.threshold || "—"
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: panel.theme.surface3
    }

    // -------------------------------------------------------------- system
    SectionHeader {
        text: "SYSTEM"
    }

    Row {
        width: parent.width
        spacing: panel.theme.space(5)

        Column {
            width: (parent.width - parent.spacing) / 2
            spacing: panel.theme.space(1)

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: "CPU"
                value: panel.systemInfo.cpu || "—"
            }

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: "Load"
                value: panel.systemInfo.load || "—"
            }
        }

        Column {
            width: (parent.width - parent.spacing) / 2
            spacing: panel.theme.space(1)

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: "Memory"
                value: panel.systemInfo.memory || "—"
            }

            InfoPair {
                theme: panel.theme

                labelColor: panel.theme.textMuted

                labelOpacity: 1
                label: panel.systemInfo.temperature_label || "Temperature"
                value: panel.systemInfo.temperature || "—"
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: panel.theme.surface3
    }

    // ------------------------------------------------------------ profiles
    SectionHeader {
        text: "POWER PROFILE"
    }

    Row {
        id: profileRow
        width: parent.width
        spacing: panel.theme.space(1.5)

        readonly property real cellWidth: (width - spacing * (panel.profileNames.length - 1)) / panel.profileNames.length

        Repeater {
            model: panel.profileNames

            Rectangle {
                id: profileCell

                required property string modelData
                required property int index

                readonly property bool isActive: panel.profilesAvailable && panel.activeProfileName === modelData
                readonly property bool hasCursor: panel.cursorActive && panel.profileIndex === index
                readonly property bool selectable: panel.profilesAvailable && (modelData !== "performance" || PowerProfiles.hasPerformanceProfile)

                width: profileRow.cellWidth
                implicitHeight: profileContent.implicitHeight + panel.theme.space(3)
                radius: panel.theme.radius(0.75)
                color: isActive ? panel.theme.alpha(panel.theme.accent, 0.25) : (hasCursor || cellHover.hovered ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2)
                border.width: panel.theme.borderWidth
                border.color: isActive || hasCursor ? panel.theme.accent : panel.theme.surface3
                opacity: selectable ? 1 : 0.45

                Column {
                    id: profileContent
                    anchors.centerIn: parent
                    spacing: panel.theme.space(0.5)

                    OpticalGlyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Model.profileIcon(profileCell.modelData)
                        color: profileCell.isActive ? panel.theme.accent : panel.theme.textPrimary
                        pixelSize: 16
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: profileCell.modelData === "power-saver" ? "Saver" : (profileCell.modelData.charAt(0).toUpperCase() + profileCell.modelData.slice(1))
                        color: profileCell.isActive ? panel.theme.accent : panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.833)
                    }
                }

                HoverHandler {
                    id: cellHover
                    enabled: profileCell.selectable
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered) {
                        panel.cursorActive = true;
                        panel.profileIndex = profileCell.index;
                    }
                }

                TapHandler {
                    enabled: profileCell.selectable
                    onTapped: panel.setProfile(profileCell.index)
                }
            }
        }
    }

    // power-profiles-daemon owns the profile D-Bus service; without it the
    // buttons above are inert, so say why rather than letting them look broken.
    InfoNote {
        theme: panel.theme
        visible: !panel.profilesAvailable
        text: "power-profiles-daemon is not installed — profiles cannot be switched."
    }

    // ---------------------------------------------------------- components
    component SectionHeader: Text {
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.75)
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }
}

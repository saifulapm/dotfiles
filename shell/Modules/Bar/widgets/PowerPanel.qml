import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../components"
import "../../../components"
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
    cardWidth: theme.space(95)

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
    // systemInfo is passed so a cap that is switched OFF settles this
    // outright — without it the heuristic can read a genuinely slow charge as
    // a held one. Absent (before the first probe lands) it degrades to
    // exactly the old behaviour.
    readonly property bool chargeThresholdActive: Model.chargeThresholdActive(device, onBattery, states, systemInfo)
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

    // --------------------------------------------------------- charge cap
    // The cap and the health log, both riding the same system-stats probe
    // rather than adding a process of their own. `supported` is the entire
    // MacBook-only gate: the Mac mini and the NUC have no battery that can
    // cap, so every row below is simply absent there — no hostname test
    // exists anywhere in this feature.
    readonly property var chargeCap: Model.chargeLimit(systemInfo)
    readonly property var healthHistory: Model.parseHealthHistory(systemInfo.health_history)
    readonly property var healthTrend: Model.healthTrend(healthHistory)
    readonly property var sparkPoints: Model.sparklinePoints(healthHistory)
    readonly property string capacityHealthText: systemInfo.capacity_health !== undefined ? systemInfo.capacity_health + "%" : ""

    // True from the click until the probe behind it confirms, so the switch
    // dims instead of appearing to do nothing: bin/battery-limit returns as
    // soon as UPower accepts the call, but the sysfs values this panel reads
    // take a moment to follow.
    property bool capBusy: false

    function toggleChargeCap() {
        if (!chargeCap.supported || capBusy)
            return;
        capBusy = true;
        capProc.command = [binDir + "battery-limit", chargeCap.enabled ? "off" : "on"];
        capProc.running = true;
    }

    Process {
        id: capProc
        onExited: {
            panel.refresh();
            // One more probe after the settle window: UPower writes sysfs
            // asynchronously and the immediate re-probe above can still catch
            // the old values.
            capSettle.restart();
        }
    }

    Timer {
        id: capSettle
        interval: 600
        onTriggered: {
            panel.capBusy = false;
            panel.refresh();
        }
    }

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
        target: hero.metaItem
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
        // Immediate for the UI, then bin/power-profile persists the choice
        // under the CURRENT power source (ac/battery) so plugging or
        // unplugging restores it — omarchy's per-source profile memory.
        PowerProfiles.profile = profileValues[index];
        Quickshell.execDetached(["power-profile", "autodetect", profileNames[index]]);
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
    PanelHero {
        id: hero

        theme: panel.theme
        width: parent.width
        labelRightMargin: panel.theme.space(2)
        title: "Battery"
        meta: panel.heroStatusText.toUpperCase()
        metaFamily: panel.theme.fontUi

        icon: OpticalGlyph {
            text: panel.batteryIcon || "󰂑"
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(2.333)
        }

        trailing: Text {
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
                    duration: panel.theme.time(2.13)
                    easing.type: panel.theme.motion.easing
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
                    duration: panel.theme.time(6.33)
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    from: 0.55
                    to: 1.0
                    duration: panel.theme.time(6.33)
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    StyledText {
        theme: panel.theme
        muted: true

        visible: !panel.present
        text: "No battery — on mains power"
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
                // Only where the cap cannot be switched from this panel —
                // with the CHARGE LIMIT section below present, a second row
                // repeating the same number is noise.
                visible: !panel.chargeThresholdActive && !panel.chargeCap.supported && panel.systemInfo.threshold !== undefined
                label: "Charge limit"
                value: panel.systemInfo.threshold || "—"
            }
        }
    }

    Separator {
        theme: panel.theme
        visible: panel.chargeCap.supported
    }

    // -------------------------------------------------------- charge limit
    // The one control in this panel that changes the hardware. It writes
    // through bin/battery-limit, which drives UPower's EnableChargeThreshold
    // over D-Bus — a polkit action marked allow_active=yes, so the toggle
    // costs no password and no prompt, and UPower persists the choice across
    // reboots in /var/lib/upower/charging-threshold-status. Nothing here has
    // any state to keep.
    Column {
        visible: panel.chargeCap.supported
        width: parent.width
        spacing: panel.theme.space(2)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "CHARGE LIMIT"
            // The live range while it holds; the header stays quiet when off
            // rather than announcing a meaningless "100%".
            value: panel.chargeCap.enabled ? panel.chargeCap.text : ""
        }

        Item {
            width: parent.width
            implicitHeight: Math.max(capLabels.implicitHeight, capSwitch.implicitHeight) + panel.theme.space(1)

            Column {
                id: capLabels
                anchors.left: parent.left
                anchors.right: capSwitch.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                StyledText {
                    theme: panel.theme
                    width: parent.width
                    text: panel.chargeCap.enabled ? "Stopping at " + panel.chargeCap.end + "%" : "Charging to 100%"
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    muted: true

                    width: parent.width
                    // The honest reason, both ways round. A cap is a trade —
                    // runtime for calendar life — and the panel should say
                    // which side it is currently on. The resume band is worth
                    // naming because a cap with no gap would micro-cycle the
                    // pack all day trying to sit exactly on the line.
                    text: {
                        if (!panel.chargeCap.enabled)
                            return "Full runtime. The pack ages faster held at 100%.";
                        const band = panel.chargeCap.start > 0 ? "Resumes below " + panel.chargeCap.start + "%. " : "";
                        return band + "Sparing the pack; unplug-and-go runtime is capped too.";
                    }
                    wrapMode: Text.WordWrap
                }
            }

            PanelSwitch {
                id: capSwitch
                theme: panel.theme
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: panel.chargeCap.enabled
                busy: panel.capBusy
                hint: panel.chargeCap.enabled ? "Charge to 100% again" : "Stop charging at 80%"
                onToggled: panel.toggleChargeCap()
            }
        }
    }

    Separator {
        theme: panel.theme
        visible: panel.chargeCap.supported
    }

    // ------------------------------------------------------ health history
    // What bin/battery-health-log has accumulated, one line a day. The
    // section exists as soon as there is a log at all — on day one it says
    // "Tracking since …", which is the truthful thing to show and also tells
    // the user the logging is running.
    Column {
        visible: panel.chargeCap.supported && panel.healthHistory.total > 0
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "CAPACITY HEALTH"
            value: panel.capacityHealthText
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Small
            muted: !panel.healthTrend.ready

            width: parent.width
            text: panel.healthTrend.text
            elide: Text.ElideRight
        }

        // Plotted against real dates, so a stretch with the machine switched
        // off reads as the flat gap it was rather than being compressed away.
        // A plain Item owns the geometry and the Shape merely fills it. The
        // Shape must NOT be the sized element: it derives its own implicit
        // size from its contents, so a path binding that reads the Shape's
        // height is a binding loop — which is exactly what the first version
        // of this did, and Qt says so at runtime rather than misdrawing.
        Item {
            id: sparkBox

            visible: panel.sparkPoints.length >= 2
            width: parent.width
            height: panel.theme.space(10)

            // Half the stroke, top and bottom, so a sample sitting at either
            // extreme is not clipped in half by its own line width.
            readonly property real inset: 2

            Shape {
                anchors.fill: parent
                // The default renderer flattens a 1.5px line into something
                // ragged at this size; the curve renderer antialiases it.
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 1.5
                    strokeColor: panel.theme.accent
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathPolyline {
                        path: {
                            const pts = panel.sparkPoints;
                            const w = sparkBox.width;
                            const h = sparkBox.height - sparkBox.inset * 2;
                            const out = [];
                            for (let i = 0; i < pts.length; i++)
                                out.push(Qt.point(pts[i].x * w, sparkBox.inset + pts[i].y * h));
                            return out;
                        }
                    }
                }
            }
        }
    }

    Separator {
        theme: panel.theme
    }

    // -------------------------------------------------------------- system
    SectionHeader {
        theme: panel.theme
        width: parent.width
        label: "SYSTEM"
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

    Separator {
        theme: panel.theme
    }

    // ------------------------------------------------------------ profiles
    SectionHeader {
        theme: panel.theme
        width: parent.width
        label: "POWER PROFILE"
    }

    Row {
        id: profileRow
        width: parent.width
        spacing: panel.theme.space(1.5)

        readonly property real cellWidth: (width - spacing * (panel.profileNames.length - 1)) / panel.profileNames.length

        Repeater {
            model: panel.profileNames

            ChipSurface {
                id: profileCell

                required property string modelData
                required property int index

                readonly property bool isActive: panel.profilesAvailable && panel.activeProfileName === modelData
                readonly property bool selectable: panel.profilesAvailable && (modelData !== "performance" || PowerProfiles.hasPerformanceProfile)

                theme: panel.theme
                width: profileRow.cellWidth
                implicitHeight: profileContent.implicitHeight + panel.theme.space(3)
                chosen: profileCell.isActive
                hasCursor: panel.cursorActive && panel.profileIndex === index
                pointerOver: cellHover.hovered
                interactive: profileCell.selectable

                Column {
                    id: profileContent
                    anchors.centerIn: parent
                    spacing: panel.theme.space(0.5)

                    OpticalGlyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Model.profileIcon(profileCell.modelData)
                        color: profileCell.isActive ? panel.theme.accent : panel.theme.textPrimary
                        pixelSize: panel.theme.fontPx(1.333)
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Small

                        anchors.horizontalCenter: parent.horizontalCenter
                        text: profileCell.modelData === "power-saver" ? "Saver" : (profileCell.modelData.charAt(0).toUpperCase() + profileCell.modelData.slice(1))
                        color: profileCell.isActive ? panel.theme.accent : panel.theme.textPrimary
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
}

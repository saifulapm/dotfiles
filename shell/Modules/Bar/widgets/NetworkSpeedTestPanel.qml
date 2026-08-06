import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../components"

// Centered speed-test overlay — port of omarchy's SpeedTestPanel.qml: no card,
// two dials (download left, upload right) floating on a darkened scrim, with
// open 270° arcs, a faint tick ring, hubless needles and a digital readout.
// The needles sweep to full scale and back when it opens, then track the live
// readings from bin/network-speedtest. Esc or the scrim close it, Enter runs
// it again.
PanelWindow {
    id: root

    required property var theme
    property bool running: false
    property string phase: ""     // "down" | "up" | ""
    property string downloadMbps: ""
    property string uploadMbps: ""
    property string error: ""
    property string connectionName: ""
    property bool opened: false

    signal closeRequested
    signal runAgainRequested

    // The bar's one-panel-at-a-time slot calls close() on whatever holds it;
    // this card registers there (NetworkPanel.showSpeedTest) so the shell's
    // close-every-panel sweep can drop its keyboard grab too.
    function close() {
        root.closeRequested();
    }

    readonly property real downloadValue: toMbps(downloadMbps)
    readonly property real uploadValue: toMbps(uploadMbps)
    readonly property bool failed: error !== ""

    function toMbps(raw) {
        const value = parseFloat(raw);
        return isFinite(value) && value > 0 ? value : 0;
    }

    visible: opened
    // The window is instantiated hidden, so re-acquire focus after mapping and
    // fire the ignition sweep once the surface is actually on screen.
    onOpenedChanged: if (opened)
        Qt.callLater(function () {
            if (!root.opened)
                return;
            keyCatcher.forceActiveFocus();
            downDial.ignite();
            upDial.ignite();
        })

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qshell-network-speedtest"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.78)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.closeRequested()
        Keys.onReturnPressed: if (!root.running)
            root.runAgainRequested()
        Keys.onEnterPressed: if (!root.running)
            root.runAgainRequested()

        Item {
            id: cluster

            anchors.centerIn: parent
            width: content.implicitWidth
            height: content.implicitHeight
            // Narrow or heavily scaled outputs: shrink the whole cluster
            // rather than clipping it at the screen edge.
            scale: Math.min(1, (keyCatcher.width - root.theme.space(8)) / Math.max(1, width), (keyCatcher.height - root.theme.space(8)) / Math.max(1, height))

            // Swallow clicks so only the scrim outside the cluster dismisses.
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Column {
                id: content

                anchors.fill: parent
                spacing: root.theme.space(4)

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.connectionName !== ""
                    text: root.connectionName.toUpperCase()
                    color: root.theme.textMuted
                    font.family: root.theme.fontMono
                    font.pixelSize: root.theme.fontPx(0.833)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.theme.space(12)

                    SpeedDial {
                        id: downDial
                        label: "DOWNLOAD"
                        value: root.downloadValue
                        live: root.running && root.phase === "down"
                    }

                    SpeedDial {
                        id: upDial
                        label: "UPLOAD"
                        value: root.uploadValue
                        live: root.running && root.phase === "up"
                    }
                }

                // Fades rather than unmounts while a run is in flight, so the
                // cluster never shifts.
                PanelButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    theme: root.theme
                    label: root.running ? "Measuring…" : "Run again"
                    enabled: !root.running
                    opacity: root.running ? 0.45 : 1
                    onClicked: root.runAgainRequested()

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.theme.time(1)
                            easing.type: root.theme.easing
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.failed
                    text: root.error
                    color: root.theme.error
                    font.family: root.theme.fontUi
                    font.pixelSize: root.theme.fontPx(0.917)
                    wrapMode: Text.Wrap
                    width: Math.min(implicitWidth, root.theme.space(100))
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    // One dial: an open 270° scale with the gap at the bottom, a faint tick
    // ring, an accent value arc, a hubless needle that fades toward the pivot,
    // and a digital readout in the middle. All writes to the needle funnel
    // through `shown`, so the ignition sweep and the live readings share one
    // animation.
    component SpeedDial: Item {
        id: dial

        required property string label
        required property real value
        required property bool live

        readonly property real diameter: root.theme.space(52)
        // 0° = 3 o'clock, increasing clockwise (PathAngleArc's convention).
        readonly property real dialStart: 135
        readonly property real dialSweep: 270
        readonly property int tickCount: 46
        readonly property real arcWidth: Math.max(3, root.theme.space(1))
        readonly property real arcRadius: diameter / 2 - arcWidth
        readonly property color trackColor: root.theme.alpha(root.theme.textPrimary, 0.14)
        readonly property color minorTickColor: root.theme.alpha(root.theme.textPrimary, 0.12)
        readonly property color majorTickColor: root.theme.alpha(root.theme.textPrimary, 0.3)
        // The dial that isn't measuring yet sits dimmed until it gets a figure.
        readonly property bool engaged: live || value > 0

        property real shown: 0
        // The readout stays on the real figure while the ignition sweep drives
        // the needle -- a cluster sweeps its gauges, not its numerals.
        readonly property real reading: ignition.running ? value : shown
        property real fullScale: 100
        readonly property var scaleStops: [100, 250, 500, 1000, 2500, 5000, 10000]
        readonly property real fraction: fullScale > 0 ? Math.max(0, Math.min(1, shown / fullScale)) : 0
        readonly property bool arcVisible: fraction > 0.004

        width: diameter
        height: diameter
        opacity: engaged ? 1 : 0.5

        Behavior on opacity {
            NumberAnimation {
                duration: 240
                easing.type: Easing.OutCubic
            }
        }

        // Live readings land once a second; glide between them rather than snap.
        Behavior on shown {
            enabled: !ignition.running
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutCubic
            }
        }

        Behavior on fullScale {
            enabled: !ignition.running
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }

        // A fresh measurement re-ranges from the base scale. Without this, one
        // unusually fast run would compress every later one for the lifetime
        // of the shell process.
        onLiveChanged: if (live)
            fullScale = scaleStops[0]

        onValueChanged: {
            // Latch the scale upward to the next stop when a reading
            // approaches the rim. Never shrink mid-run.
            for (let i = 0; i < scaleStops.length; i++) {
                if (value <= scaleStops[i] * 0.92) {
                    if (scaleStops[i] > fullScale)
                        fullScale = scaleStops[i];
                    break;
                }
                if (i === scaleStops.length - 1)
                    fullScale = scaleStops[i];
            }
            if (!ignition.running)
                shown = value;
        }

        function ignite() {
            ignition.restart();
        }

        SequentialAnimation {
            id: ignition

            NumberAnimation {
                target: dial
                property: "shown"
                to: dial.fullScale
                duration: 550
                easing.type: Easing.InOutCubic
            }

            NumberAnimation {
                target: dial
                property: "shown"
                to: 0
                duration: 650
                easing.type: Easing.OutCubic
            }

            onFinished: dial.shown = dial.value
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Track: the full scale, always visible, dim.
            ShapePath {
                strokeWidth: dial.arcWidth
                strokeColor: dial.trackColor
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: dial.width / 2
                    centerY: dial.height / 2
                    radiusX: dial.arcRadius
                    radiusY: dial.arcRadius
                    startAngle: dial.dialStart
                    sweepAngle: dial.dialSweep
                }
            }

            // Soft under-glow beneath the value arc. Both arcs go transparent
            // at rest, or their round caps leave a stray dot at the foot of
            // the scale.
            ShapePath {
                strokeWidth: dial.arcWidth * 3
                strokeColor: dial.arcVisible ? root.theme.alpha(root.theme.accent, 0.18) : "transparent"
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: dial.width / 2
                    centerY: dial.height / 2
                    radiusX: dial.arcRadius
                    radiusY: dial.arcRadius
                    startAngle: dial.dialStart
                    sweepAngle: dial.dialSweep * dial.fraction
                }
            }

            ShapePath {
                strokeWidth: dial.arcWidth
                strokeColor: dial.arcVisible ? root.theme.accent : "transparent"
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: dial.width / 2
                    centerY: dial.height / 2
                    radiusX: dial.arcRadius
                    radiusY: dial.arcRadius
                    startAngle: dial.dialStart
                    sweepAngle: dial.dialSweep * dial.fraction
                }
            }
        }

        // Faint tick ring just inside the arc; every fifth tick is a major.
        Repeater {
            model: dial.tickCount

            Item {
                required property int index

                readonly property bool major: index % 5 === 0

                anchors.fill: parent
                rotation: dial.dialStart + (index / (dial.tickCount - 1)) * dial.dialSweep - 270

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: dial.arcWidth * 2 + (parent.major ? 0 : root.theme.space(0.5))
                    width: parent.major ? 2 : 1
                    height: parent.major ? root.theme.space(2.5) : root.theme.space(1.5)
                    radius: width / 2
                    color: parent.major ? dial.majorTickColor : dial.minorTickColor
                }
            }
        }

        // Hubless needle: a slender sliver that fades out toward the pivot.
        Item {
            anchors.fill: parent
            rotation: dial.dialStart + dial.fraction * dial.dialSweep - 270

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: dial.arcWidth * 2 + root.theme.space(2.5)
                width: 3
                height: dial.diameter * 0.32
                radius: width / 2

                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: root.theme.accent
                    }

                    GradientStop {
                        position: 0.55
                        color: root.theme.accent
                    }

                    GradientStop {
                        position: 1.0
                        color: "transparent"
                    }
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: root.theme.space(3.5)
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.reading < 10 ? dial.reading.toFixed(1) : Math.round(dial.reading).toString()
                color: root.theme.textPrimary
                font.family: root.theme.fontMono
                font.pixelSize: root.theme.fontPx(1.6)
                font.weight: Font.DemiBold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Mbps"
                color: root.theme.textMuted
                font.family: root.theme.fontUi
                font.pixelSize: root.theme.fontPx(0.833)
            }
        }

        // The 90° gap at the bottom of the scale is where a cluster prints its
        // unit; here it names the direction.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: dial.label
            color: root.theme.textMuted
            font.family: root.theme.fontMono
            font.pixelSize: root.theme.fontPx(0.833)
            font.weight: Font.DemiBold
            font.letterSpacing: 1.5
        }
    }
}

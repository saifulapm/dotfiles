import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../components"
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
    readonly property var modes: [
        { mode: 0, label: "Off",          glyph: "󰝟" },
        { mode: 2, label: "Transparency", glyph: "󰋌" },
        { mode: 3, label: "Adaptive",     glyph: "󰧑" },
        { mode: 1, label: "ANC",          glyph: "󰋍" }
    ]

    property int cursorIndex: 0
    property bool cursorActive: false

    onPanelOpened: {
        cursorActive = false;
        const current = panel.modes.findIndex(m => m.mode === panel.service.noise);
        cursorIndex = current >= 0 ? current : 0;
    }

    // The power panel's keyboard model: the first arrow press parks the
    // cursor, later ones walk the mode row, Enter applies what it sits on.
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
                cursorIndex = Math.min(panel.modes.length - 1, Math.max(0, cursorIndex + delta));
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (cursorActive)
                panel.service.setNoise(panel.modes[cursorIndex].mode);
            event.accepted = true;
        }
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
    SectionHeader {
        theme: panel.theme
        width: parent.width
        label: "BATTERY"
    }

    Column {
        width: parent.width
        spacing: panel.theme.space(2)

        Repeater {
            model: [
                { key: "left",   label: "Left",  inEar: panel.service.leftInEar },
                { key: "right",  label: "Right", inEar: panel.service.rightInEar },
                { key: "case",   label: "Case",  inEar: false },
                { key: "single", label: "Pods",  inEar: panel.service.leftInEar }
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

                    Text {
                        id: rowLabel
                        anchors.left: parent.left
                        text: parent.parent.modelData.label + (parent.parent.modelData.inEar ? "  ·  in ear" : "")
                        color: panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.917)
                    }

                    Text {
                        anchors.right: parent.right
                        text: parent.parent.reading ? parent.parent.reading.level + "%" + (parent.parent.reading.charging ? " 󰂄" : "") : ""
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontMono
                        font.pixelSize: panel.theme.fontPx(0.833)
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
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }

    Separator {
        theme: panel.theme
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

            Rectangle {
                id: modeCell

                required property var modelData
                required property int index

                readonly property bool isActive: panel.service.noise === modelData.mode
                readonly property bool hasCursor: panel.cursorActive && panel.cursorIndex === index

                width: modeRow.cellWidth
                implicitHeight: modeContent.implicitHeight + panel.theme.space(3)
                radius: panel.theme.radius(0.75)
                color: isActive ? panel.theme.alpha(panel.theme.accent, 0.25) : (hasCursor || cellHover.hovered ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2)
                border.width: panel.theme.borderWidth
                border.color: isActive || hasCursor ? panel.theme.accent : panel.theme.surface3

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

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modeCell.modelData.label
                        color: modeCell.isActive ? panel.theme.accent : panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.75)
                    }
                }

                HoverHandler {
                    id: cellHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered) {
                        panel.cursorActive = true;
                        panel.cursorIndex = modeCell.index;
                    }
                }

                TapHandler {
                    onTapped: panel.service.setNoise(modeCell.modelData.mode)
                }
            }
        }
    }

    // The daemon owns every fact above; without it the panel is a ghost, so
    // say why rather than letting the picker look broken.
    InfoNote {
        theme: panel.theme
        visible: !panel.service.connected
        text: "AirPods not connected, or librepods.service is not running."
    }
}

import QtQuick
import Quickshell.Bluetooth
import "../components"

// Bluetooth panel — omarchy's bluetooth plugin: adapter toggle, discovery
// while open, device list with connect/disconnect, pairing and forget.
BarPanel {
    id: panel

    panelTitle: "Bluetooth"

    readonly property var adapter: Bluetooth.defaultAdapter

    onPanelOpened: {
        if (adapter && adapter.enabled)
            adapter.discovering = true;
    }
    onPanelClosed: {
        if (adapter)
            adapter.discovering = false;
    }

    readonly property var deviceList: {
        const list = Bluetooth.devices.values.slice();
        list.sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.paired !== b.paired)
                return a.paired ? -1 : 1;
            return (a.name || a.deviceName || "").localeCompare(b.name || b.deviceName || "");
        });
        return list.filter(d => (d.name || d.deviceName || "") !== "").slice(0, 12);
    }

    function stateLabel(d) {
        if (d.state === BluetoothDeviceState.Connecting)
            return "connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting)
            return "disconnecting…";
        if (d.pairing)
            return "pairing…";
        if (d.connected)
            return d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "connected";
        if (d.paired)
            return "paired";
        return "";
    }

    Row {
        width: parent.width
        spacing: panel.theme.space(2)

        Text {
            width: parent.width - btToggle.width - panel.theme.space(2)
            height: btToggle.height
            verticalAlignment: Text.AlignVCenter
            text: {
                if (!panel.adapter || !panel.adapter.enabled)
                    return "Bluetooth is off";
                return panel.adapter.discovering ? "Scanning…" : "Ready";
            }
            color: panel.theme.textMuted
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.917)
        }

        PanelButton {
            id: btToggle
            theme: panel.theme
            label: panel.adapter && panel.adapter.enabled ? "On" : "Off"
            selected: panel.adapter !== null && panel.adapter.enabled
            onClicked: {
                if (panel.adapter) {
                    panel.adapter.enabled = !panel.adapter.enabled;
                    if (panel.adapter.enabled)
                        panel.adapter.discovering = true;
                }
            }
        }
    }

    Repeater {
        model: panel.deviceList

        Rectangle {
            id: devRow

            required property var modelData

            width: parent.width
            height: panel.theme.space(9)
            radius: panel.theme.radius(0.75)
            color: devRow.modelData.connected ? panel.theme.alpha(panel.theme.accent, 0.18) : (devHover.hovered ? panel.theme.alpha(panel.theme.textPrimary, 0.06) : "transparent")

            HoverHandler {
                id: devHover
            }

            TapHandler {
                onTapped: {
                    const d = devRow.modelData;
                    if (d.connected)
                        d.disconnect();
                    else if (d.paired || d.bonded)
                        d.connect();
                    else
                        d.pair();
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: panel.theme.space(2)
                spacing: panel.theme.space(2.5)

                OpticalGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: devRow.modelData.connected ? "󰂱" : "󰂯"
                    color: devRow.modelData.connected ? panel.theme.accent : panel.theme.textPrimary
                    pixelSize: 13
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: devRow.modelData.name || devRow.modelData.deviceName
                    color: devRow.modelData.connected ? panel.theme.accent : panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(1.0)
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, panel.cardWidth - 150)
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: panel.theme.space(2)
                spacing: panel.theme.space(2)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !devHover.hovered || !devRow.modelData.paired
                    text: panel.stateLabel(devRow.modelData)
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.833)
                }

                PanelButton {
                    theme: panel.theme
                    visible: devRow.modelData.paired === true && devHover.hovered
                    label: "Forget"
                    onClicked: devRow.modelData.forget()
                }
            }
        }
    }

    Text {
        visible: panel.deviceList.length === 0
        text: panel.adapter && panel.adapter.enabled ? "Scanning for devices…" : "Enable Bluetooth to scan"
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.917)
    }
}

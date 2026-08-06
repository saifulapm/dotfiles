import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../components"

// Battery from UPower's display device, omarchy power-widget glyph ladders.
// Icon-only by default; right click toggles the percentage label. Hidden on
// machines without a battery (the Mac mini and NUC).
BarButton {
    id: rootItem

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isLaptopBattery
    // Quickshell docs say 0–1; be robust to either scale.
    readonly property int pct: {
        if (!present)
            return 0;
        const p = device.percentage;
        return Math.round(p <= 1 ? p * 100 : p);
    }
    readonly property bool charging: present && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged)
    readonly property bool low: present && !charging && pct <= 15
    property bool showPercentage: false

    readonly property var dischargeGlyphs: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    readonly property var chargeGlyphs: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]

    function formatMinutes(seconds) {
        const m = Math.round(seconds / 60);
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m";
    }

    // The percentage label is a horizontal-bar affordance (their power widget
    // suppresses it on a vertical bar too); vertically the widget is always
    // the icon slot.
    readonly property bool percentageShown: showPercentage && !vertical

    visible: present
    active: low
    fixedWidth: vertical ? -1 : (percentageShown ? -1 : 27)
    fixedHeight: vertical ? 27 : -1
    tooltipText: {
        if (!present)
            return "";
        const state = charging ? (device.timeToFull > 0 ? formatMinutes(device.timeToFull) + " to full" : "Charging") : (device.timeToEmpty > 0 ? formatMinutes(device.timeToEmpty) + " left" : "On battery");
        return pct + "% · " + state;
    }

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("PowerPanel.qml", {
                theme: rootItem.theme
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton) {
            rootItem.showPercentage = !rootItem.showPercentage;
        } else if (button === Qt.LeftButton) {
            openPanel();
        }
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: {
            const ladder = rootItem.charging ? rootItem.chargeGlyphs : rootItem.dischargeGlyphs;
            return ladder[Math.min(9, Math.floor(rootItem.pct / 10))];
        }
        color: rootItem.contentColor
        pixelSize: 13
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: rootItem.percentageShown
        text: rootItem.pct + "%"
        color: rootItem.contentColor
        font.family: rootItem.theme.fontMono
        font.pixelSize: rootItem.theme.fontPx(0.833)
        renderType: Text.NativeRendering
    }
}

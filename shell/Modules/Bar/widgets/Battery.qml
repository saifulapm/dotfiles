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

    visible: present
    active: low
    fixedWidth: showPercentage ? -1 : 27
    tooltipText: {
        if (!present)
            return "";
        const state = charging ? (device.timeToFull > 0 ? formatMinutes(device.timeToFull) + " to full" : "Charging") : (device.timeToEmpty > 0 ? formatMinutes(device.timeToEmpty) + " left" : "On battery");
        return pct + "% · " + state;
    }

    function openPanel() {
        panelLoader.active = true;
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

    LazyLoader {
        id: panelLoader
        active: false
        component: PowerPanel {
            theme: rootItem.theme
        }
    }

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: {
            const ladder = rootItem.charging ? rootItem.chargeGlyphs : rootItem.dischargeGlyphs;
            return ladder[Math.min(9, Math.floor(rootItem.pct / 10))];
        }
        color: rootItem.contentColor
        pixelSize: 13
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: rootItem.showPercentage
        text: rootItem.pct + "%"
        color: rootItem.contentColor
        font.family: rootItem.theme.fontMono
        font.pixelSize: rootItem.theme.fontPx(0.833)
        renderType: Text.NativeRendering
    }
}

import QtQuick
import Quickshell
import "../components"

// Omarchy's clock: "dddd HH:mm" by default, right click toggles the long
// alternate format ("d MMMM 'W'ww yyyy"), tooltip carries the full date.
BarButton {
    id: rootItem

    property string format: "dddd HH:mm"
    property string altFormat: "d MMMM 'W'ww yyyy"
    property bool showAlt: false

    tooltipText: Qt.formatDateTime(clock.date, "dddd d MMMM yyyy")

    onTapped: button => {
        if (button === Qt.RightButton)
            rootItem.showAlt = !rootItem.showAlt;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        color: rootItem.contentColor
        font.family: rootItem.theme.fontMono
        font.pixelSize: rootItem.theme.fontPx(1.0)
        renderType: Text.NativeRendering
        text: Qt.formatDateTime(clock.date, rootItem.showAlt ? rootItem.altFormat : rootItem.format)
    }
}

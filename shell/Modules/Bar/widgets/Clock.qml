import QtQuick
import Quickshell

Item {
    id: rootItem

    required property var theme
    property string format: "ddd dd MMM  HH:mm"

    implicitWidth: label.implicitWidth
    implicitHeight: parent ? parent.height : label.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: rootItem.theme.textPrimary
        font.family: rootItem.theme.fontMono
        font.pixelSize: rootItem.theme.fontPx(1.0)
        text: Qt.formatDateTime(clock.date, rootItem.format)
    }
}

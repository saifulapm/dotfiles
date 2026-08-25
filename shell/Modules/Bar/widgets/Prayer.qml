import QtQuick
import "../components"
import "../../../components"

// Prayer times — the next prayer's name and time on the bar, the day's full
// table behind it. Port of the omarchy prayer-times plugin family, on our
// widget pattern: the mark warms to the accent inside the last twenty
// minutes, the tooltip carries the whole day, and the notification at the
// prayer's minute comes from the service whether or not the widget is
// visible on this screen.
//
// Left click opens the panel, right click re-reads the cached month.
BarButton {
    id: rootItem

    required property PrayerService prayer

    visible: prayer.probed && prayer.barText !== ""

    tooltipText: prayer.tooltip

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("PrayerPanel.qml", {
                theme: rootItem.theme,
                prayer: rootItem.prayer
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            prayer.refresh();
        else
            openPanel();
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 5

        OpticalGlyph {
            anchors.verticalCenter: parent.verticalCenter
            text: "󱠧" // md-mosque
            pixelSize: 13
            verticalInkCenter: true
            color: rootItem.prayer.imminent ? rootItem.theme.accent : Qt.darker(rootItem.barFg, 1.25)
            colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
        }

        StyledText {
            theme: rootItem.theme
            anchors.verticalCenter: parent.verticalCenter
            text: rootItem.prayer.barText
            color: rootItem.prayer.imminent ? rootItem.theme.accent : rootItem.barFg
            font.pixelSize: rootItem.theme.fontPx(0.917)
        }
    }

    fixedWidth: vertical ? -1 : content.implicitWidth + 12
    fixedHeight: vertical ? content.implicitHeight + 10 : -1

    PanelLoader {
        id: panelLoader
    }
}

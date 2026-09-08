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

    readonly property color markColor: prayer.imminent ? theme.accent : barFg

    Row {
        id: content
        anchors.centerIn: parent
        visible: !rootItem.vertical
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
            color: rootItem.markColor
            font.pixelSize: rootItem.theme.fontPx(0.917)
        }
    }

    // "Asr 16:25" as the vertical bar takes it: name, hour, colon, minutes.
    // The name is cut to three letters because a 28 px column fits no more —
    // Maghrib is legible at no size that fits — and the time is split the way
    // the clock's vertical format splits its own (HH / — / mm) rather than
    // shrunk to a 8 px "16:25" nobody can read (user call 2026-09-08).
    readonly property var verticalLines: {
        const next = prayer.next;
        if (!next)
            return [];
        const parts = String(next.time).split(":");
        return [String(next.name).slice(0, 3), parts[0] || "", ":", parts[1] || ""];
    }

    // The vertical face. One icon-sized line each, optically centered like a
    // glyph is — the same treatment the clock's stack gets, so the two read
    // as one column of marks rather than two typographies.
    Column {
        id: verticalContent
        anchors.centerIn: parent
        visible: rootItem.vertical

        OpticalGlyph {
            width: rootItem.barSize
            height: 18
            text: "󱠧" // md-mosque
            pixelSize: 13
            color: rootItem.prayer.imminent ? rootItem.theme.accent : Qt.darker(rootItem.barFg, 1.25)
            colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
        }

        Repeater {
            model: rootItem.verticalLines

            OpticalGlyph {
                required property string modelData

                width: rootItem.barSize
                height: 20
                text: modelData
                fontFamily: rootItem.theme.fontMono
                pixelSize: rootItem.theme.fontPx(0.917)
                color: rootItem.markColor
                colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
            }
        }
    }

    fixedWidth: vertical ? -1 : content.implicitWidth + 12
    fixedHeight: vertical ? verticalContent.implicitHeight + 10 : -1

    PanelLoader {
        id: panelLoader
    }
}

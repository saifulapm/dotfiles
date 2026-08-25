import QtQuick
import "../components"
import "../../../components"

// Prayer panel — today's table in full: the six marks of the day with the
// next one carrying the accent and the passed ones dimmed, the hijri date
// in the hero. Read-only; Escape closes, as every BarPanel does.
BarPanel {
    id: panel

    required property var prayer

    panelTitle: ""
    cardWidth: theme.space(70)

    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Prayer Times"
        meta: {
            const parts = [];
            if (panel.prayer.next)
                parts.push(panel.prayer.next.name + " " + panel.prayer.countdownText(panel.prayer.next.minutes));
            if (panel.prayer.hijriToday)
                parts.push(panel.prayer.hijriToday);
            return parts.join(" · ").toUpperCase();
        }
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: "󱠧" // md-mosque
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.theme.textPrimary
        }
    }

    Column {
        width: parent.width
        spacing: panel.theme.space(0.5)

        Repeater {
            model: panel.prayer.order

            Item {
                required property string modelData

                readonly property string timeText: panel.prayer.today ? panel.prayer.fmt(panel.prayer.today.timings[modelData]) : ""
                readonly property bool isNext: panel.prayer.next !== null && !panel.prayer.next.tomorrow && panel.prayer.next.name === modelData
                readonly property bool isPast: panel.prayer.today !== null && panel.prayer.minutesOf(panel.prayer.today.timings[modelData]) <= panel.prayer.nowMinute
                readonly property bool isSunrise: modelData === "Sunrise"

                width: parent.width
                height: panel.theme.space(7)

                Rectangle {
                    anchors.fill: parent
                    radius: panel.theme.radius(1)
                    color: parent.isNext ? panel.theme.alpha(panel.theme.accent, 0.14) : "transparent"
                }

                StyledText {
                    theme: panel.theme
                    anchors.left: parent.left
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData
                    color: parent.isNext ? panel.theme.accent : panel.theme.textPrimary
                    opacity: parent.isPast && !parent.isNext ? 0.45 : (parent.isSunrise ? 0.7 : 1)
                    font.weight: parent.isNext ? Font.DemiBold : Font.Normal
                    font.italic: parent.isSunrise
                }

                StyledText {
                    theme: panel.theme
                    mono: true
                    anchors.right: parent.right
                    anchors.rightMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.timeText
                    color: parent.isNext ? panel.theme.accent : panel.theme.textPrimary
                    opacity: parent.isPast && !parent.isNext ? 0.45 : (parent.isSunrise ? 0.7 : 1)
                    font.weight: parent.isNext ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small
        visible: panel.prayer.lastError !== ""
        width: parent.width
        text: panel.prayer.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }
}

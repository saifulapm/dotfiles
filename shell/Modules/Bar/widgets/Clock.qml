import QtQuick
import Quickshell
import "../components"
import "ClockModel.js" as Model

// Omarchy's clock: the format lives in the widget's inline shell.json entry,
// left click opens the calendar panel, and right click walks the common
// label formats — what the bar shows is what shell.json stores, so a cycled
// format is the format from then on rather than something that reverts on
// restart.
BarButton {
    id: rootItem

    readonly property string format: String(setting("format", "dddd HH:mm"))
    readonly property string formatAlt: String(setting("formatAlt", "d MMMM 'W'ww yyyy"))
    readonly property var formatRing: Model.clockFormatRing(format, formatAlt, Model.clockFormats())

    tooltipText: Qt.formatDateTime(clock.date, "dddd d MMMM yyyy")

    // Qt has no ISO week specifier, so a format's 'ww' token is substituted
    // with the computed ISO week before Qt formats the rest.
    function formatted(date) {
        return Qt.formatDateTime(date, format.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())));
    }

    function cycleFormat() {
        const next = Model.nextClockFormat(formatRing, format);
        if (next === "" || next === format)
            return;
        persistSettings({
            format: next
        });
    }

    // Merge values into this widget's inline entry and write it back to
    // shell.json. Applied locally first so the label (or the calendar panel)
    // redraws on the click itself; the config file round trip re-delivers
    // the same value.
    function persistSettings(values) {
        const entry = {
            id: "clock"
        };
        for (const key in settings) {
            if (key !== "id")
                entry[key] = settings[key];
        }
        for (const key in values)
            entry[key] = values[key];
        settings = entry;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
            bar.shell.updateEntryInline("clock", entry);
    }

    function openPanel() {
        calendarLoader.active = true;
        calendarLoader.item.anchorItem = rootItem;
        calendarLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton) {
            cycleFormat();
        } else if (button === Qt.LeftButton) {
            openPanel();
        }
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
        text: rootItem.formatted(clock.date)
    }

    LazyLoader {
        id: calendarLoader
        active: false
        component: CalendarPanel {
            theme: rootItem.theme
            host: rootItem
            settings: rootItem.settings
        }
    }
}

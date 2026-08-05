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

    // A vertical bar gets its own format and its own ring — a run of text
    // does not fit a 28 px column, so the label becomes a stack of short
    // lines (omarchy's verticalFormat / verticalFormatAlt settings and their
    // defaults).
    readonly property string format: vertical ? String(setting("verticalFormat", "HH\n—\nmm")) : String(setting("format", "dddd HH:mm"))
    readonly property string formatAlt: vertical ? String(setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")) : String(setting("formatAlt", "d MMMM 'W'ww yyyy"))
    readonly property var formatRing: Model.clockFormatRing(format, formatAlt, Model.clockFormats(vertical))
    readonly property string displayText: formatted(clock.date)
    readonly property var verticalLines: displayText.split("\n")

    tooltipText: Qt.formatDateTime(clock.date, "dddd d MMMM yyyy")
    // The clock fills more slot than it paints a mark for, at both
    // orientations: horizontally it is a text label in a padded slot, so the
    // pill takes the label width; vertically it is a stack of icon-sized
    // lines, so the pill takes one line — the same mark every icon widget
    // gets, rather than a rule running the height of the whole stack.
    readonly property real openPanelIndicatorWidth: labelWidth
    readonly property real openPanelIndicatorHeight: Math.max(10, Math.round(27 * 0.55))

    horizontalMargin: 8.75
    verticalPadding: 8.75
    // Theirs: the vertical clock is exactly as tall as its stack of lines,
    // one icon slot each. Sizing it from the content instead would make the
    // slot's height depend on a Row that is centered inside that same slot.
    fixedHeight: vertical ? verticalLines.length * 27 : -1

    // Qt has no ISO week specifier, so a format's 'ww' token is substituted
    // with the computed ISO week before Qt formats the rest.
    function formatted(date) {
        return Qt.formatDateTime(date, format.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())));
    }

    function cycleFormat() {
        const next = Model.nextClockFormat(formatRing, format);
        if (next === "" || next === format)
            return;
        // The cycled format is stored under the key the current orientation
        // reads, so cycling a vertical clock never rewrites the horizontal
        // label and vice versa (theirs).
        const values = {};
        values[vertical ? "verticalFormat" : "format"] = next;
        persistSettings(values);
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
        visible: !rootItem.vertical
        color: rootItem.contentColor
        font.family: rootItem.theme.fontMono
        font.pixelSize: rootItem.theme.fontPx(1.0)
        renderType: Text.NativeRendering
        text: rootItem.displayText
    }

    // The vertical face: one icon-slot-tall line per format line, optically
    // centered like a glyph is, and a notch smaller once a line runs past
    // three characters (theirs).
    Column {
        visible: rootItem.vertical

        Repeater {
            model: rootItem.verticalLines

            OpticalGlyph {
                required property string modelData

                width: rootItem.barSize
                height: 27
                text: modelData
                fontFamily: rootItem.theme.fontMono
                pixelSize: modelData.length > 3 ? Math.round(rootItem.theme.fontPx(1.0) * 0.9) : rootItem.theme.fontPx(1.0)
                color: rootItem.contentColor
            }
        }
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

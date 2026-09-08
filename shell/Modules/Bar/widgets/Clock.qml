import QtQuick
import Quickshell
import "../components"
import "../../../components"
import "ClockModel.js" as Model

// Omarchy's clock: the format lives in the widget's inline shell.json entry,
// left click opens the calendar panel, and right click walks the common
// label formats — what the bar shows is what shell.json stores, so a cycled
// format is the format from then on rather than something that reverts on
// restart.
BarButton {
    id: rootItem

    // The niri service, for the minimap strip under the label; and the screen
    // whose workspace that strip draws (injected by the bar's WidgetSlot).
    required property var niri
    property string screenName: ""

    // A vertical bar gets its own format and its own ring — a run of text
    // does not fit a 28 px column, so the label becomes a stack of short
    // lines (omarchy's verticalFormat / verticalFormatAlt settings and their
    // defaults).
    readonly property string format: vertical ? String(setting("verticalFormat", "HH\n—\nmm")) : String(setting("format", "dddd HH:mm"))
    readonly property string formatAlt: vertical ? String(setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")) : String(setting("formatAlt", "d MMMM 'W'ww yyyy"))
    readonly property var formatRing: Model.clockFormatRing(format, formatAlt, Model.clockFormats(vertical))
    // A seconds label needs the clock to tick sixty times as often, and a
    // repaint a second is a price only the formats that print seconds pay.
    readonly property bool showsSeconds: Model.clockNeedsSeconds(format)
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
        if (calendarLoader.status === Loader.Null)
            calendarLoader.setSource("CalendarPanel.qml", {
                theme: rootItem.theme,
                host: rootItem,
                settings: rootItem.settings
            });
        calendarLoader.item.anchorItem = rootItem;
        calendarLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton) {
            cycleFormat();
        } else if (button === Qt.MiddleButton) {
            // Omarchy's clock middle-click: the timezone selector (theirs is
            // a menu route; ours is the fzf picker in a float).
            Quickshell.execDetached(["foot-run", "--app-id=qshell-float", "-e", "timezone-set"]);
        } else if (button === Qt.LeftButton) {
            openPanel();
        }
    }

    SystemClock {
        id: clock
        precision: rootItem.showsSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    StyledText {
        theme: rootItem.theme
        role: StyledText.BodyLarge
        mono: true

        anchors.verticalCenter: parent.verticalCenter
        visible: !rootItem.vertical
        color: rootItem.contentColor
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
                colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
            }
        }
    }

    // The minimap, worn by the clock rather than given a slot of its own: a
    // rail of pills on the bar's inner edge under the date and time, one per
    // column of this screen's workspace.
    //
    // `parent` is set on purpose. Declared children land in BarButton's
    // content Row, which would put the strip BESIDE the label; the strip is
    // chrome under the text, so it is reparented onto the button itself and
    // positioned there. It paints inside the slot the label already claims,
    // so the clock's width — and the bar's center anchor — never move for it.
    MinimapStrip {
        id: minimap

        // The open-panel pill lives 2 px off the same edge and is as wide as
        // the label, so with the calendar open the two would merge into one
        // thick accent bar and the columns would be unreadable. The panel is
        // the state the user is looking at while it is open; the rail comes
        // back when it closes.
        readonly property bool panelOpen: rootItem.bar && rootItem.bar.activePanel && rootItem.bar.activePanel.anchorItem === rootItem
        // Which screen edge the bar is on; "top" until a bar is injected,
        // which is also what the widget renders as until then.
        readonly property string edge: rootItem.bar ? rootItem.bar.position : "top"

        parent: rootItem
        theme: rootItem.theme
        niri: rootItem.niri
        screenName: rootItem.screenName
        screenWidth: rootItem.bar && rootItem.bar.screen ? rootItem.bar.screen.width : 0
        pillColor: rootItem.contentColor
        vertical: rootItem.vertical
        // As long as the face it belongs to: the label's width on a
        // horizontal bar, the stack's height on a vertical one.
        budget: rootItem.vertical ? Math.max(40, rootItem.height) : Math.max(40, rootItem.labelWidth)
        // Flush with the bar's inner edge — the one facing the desktop — so
        // it reads as a border the bar wears rather than a mark floating by
        // the text: it underlines a top bar, overlines a bottom one, and runs
        // down the desktop-facing side of a bar on its side.
        //
        // Placed with x/y rather than anchors, deliberately. The strip starts
        // life in BarButton's content Row (see `parent` above), and a Row
        // refuses horizontal anchors on its children — the anchor is dropped
        // there and does not come back when the reparent lands, which put the
        // vertical rail against the screen edge instead of the desktop one.
        x: rootItem.vertical ? (edge === "left" ? rootItem.width - width : 0) : Math.round((rootItem.width - width) / 2)
        y: rootItem.vertical ? Math.round((rootItem.height - height) / 2) : (edge === "bottom" ? 0 : rootItem.height - height)
        opacity: panelOpen ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: rootItem.theme.motion.standard
                easing.type: rootItem.theme.motion.easing
            }
        }
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    PanelLoader {
        id: calendarLoader
    }

    // setSource props are set-once, but `settings` is reassigned every time
    // a click cycles the format — keep the open calendar's copy live.
    Binding {
        target: calendarLoader.item
        property: "settings"
        value: rootItem.settings
        when: calendarLoader.item !== null
    }
}

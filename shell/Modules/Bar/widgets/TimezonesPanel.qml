import QtQuick
import "../components"
import "../../../components"
import "TimezonesModel.js" as Model
import "WeatherModel.js" as WeatherModel

// Timezones panel — one row per zone, all of them aligned on the same
// absolute hours, so a column is a single moment read in every place at once.
// That alignment IS the feature: "10am here is what there" is a question a
// list of clocks cannot answer and a grid answers by being looked at.
//
// Each row carries the zone, its clock, how far it is from home, and a strip
// of hour numbers with the working day shaded and midnight marked. The
// current hour is a filled column running through every row.
//
// Peak hours get an accent rule along the top of the column. They are stated
// in UTC, not in a local working day, so the rule lands on the same columns in
// every row and reads as one band across the grid.
//
// Hovering a column reads every row at that moment instead of at now — the
// same gesture worldtimebuddy uses, and the reason the grid beats three
// separate clocks.
//
// Keyboard, after omarchy's Elsewhen: up/down (j/k) pick a city row and the
// header reads in it, left/right (h/l) walk the reading column, t flips
// 12/24-hour time, Alt+T flips °C/°F, r re-reads the offsets, Escape
// releases the reading column and then closes. The first up/down only lights
// the cursor, as in the audio panel.
//
// Each city row also carries its current weather (Elsewhen's per-city
// forecast), lined up in one column against the times.
BarPanel {
    id: panel

    required property var timezones

    panelTitle: ""
    cardWidth: theme.space(120)

    readonly property var home: timezones.home
    // Recomputed on the service's minute tick, so every row moves together.
    readonly property var rows: timezones.zones.length > 0 ? Model.grid(timezones.zones, home, timezones.nowMs) : []

    // Which column the pointer is reading, or -1 for "now".
    property int hoverColumn: -1
    readonly property int readColumn: hoverColumn >= 0 ? hoverColumn : Model.GRID_BEFORE

    // The keyboard's picked row, or -1 before the first up/down.
    property int selectedRow: -1
    readonly property var selectedZone: selectedRow >= 0 && selectedRow < rows.length ? rows[selectedRow].zone : null
    // The zone the header reads in: the picked row, else home.
    readonly property var readZone: selectedZone || home

    readonly property bool hour24: timezones.hour24

    function moveRow(step) {
        if (rows.length === 0)
            return;
        if (selectedRow < 0 || selectedRow >= rows.length) {
            // First press lights the cursor on home rather than moving it.
            selectedRow = Math.max(0, rows.indexOf(rows.find(row => row.zone === home)));
            return;
        }
        selectedRow = (selectedRow + step + rows.length) % rows.length;
    }

    // The instant the header is reporting: hovered column, or now.
    readonly property double readInstant: {
        if (!home)
            return timezones.nowMs;
        const instants = Model.gridInstants(home, timezones.nowMs);
        return instants[Math.max(0, Math.min(instants.length - 1, readColumn))];
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_R:
            panel.timezones.refresh();
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            panel.moveRow(-1);
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            panel.moveRow(1);
            break;
        case Qt.Key_T:
            if (event.modifiers & Qt.AltModifier)
                panel.timezones.toggleUnits();
            else
                panel.timezones.toggleHour24();
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            panel.hoverColumn = Math.max(0, panel.readColumn - 1);
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            panel.hoverColumn = Math.min(Model.GRID_COLUMNS - 1, panel.readColumn + 1);
            break;
        case Qt.Key_Escape:
            // Release the reading cursor before closing the panel, the way
            // the ssh panel clears its query first.
            if (panel.hoverColumn >= 0) {
                panel.hoverColumn = -1;
                break;
            }
            return;
        default:
            return;
        }
        event.accepted = true;
    }

    onPanelOpened: {
        panel.hoverColumn = -1;
        panel.selectedRow = -1;
        panel.timezones.refresh();
        panel.timezones.refreshWeather();
    }

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "World Clock"
        // Follows the reading cursor, peak flag included: hovering a column
        // answers "would that moment have been peak" as well as "what time is
        // it there". readInstant is the current hour's column when nothing is
        // hovered, and peak windows are hour-aligned, so this is also the
        // right answer for now.
        meta: {
            const zone = panel.readZone;
            if (!zone)
                return "No zones";
            const state = Model.isPeakInstant(panel.readInstant) ? " · Peak" : " · Off-peak";
            if (panel.hoverColumn >= 0)
                return "Reading " + Model.clockText(zone, panel.readInstant, panel.hour24) + " in " + zone.label + state;
            return zone.label + " · " + Model.clockText(zone, panel.timezones.nowMs, panel.hour24) + state;
        }
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: "󰖟"
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.theme.textPrimary
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.timezones.lastError !== ""
        width: parent.width
        text: panel.timezones.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    // One width for every row's time, so the weather beside it lines up
    // (Elsewhen 25f97952): the widest clock in this mode, plus the longest
    // day word any row is showing at the reading instant.
    readonly property string widestTime: {
        let tail = "";
        for (const row of rows) {
            const delta = home ? Model.dayDeltaText(row.zone, home, readInstant) : "";
            if (delta.length > tail.length)
                tail = delta;
        }
        return (hour24 ? "00:00" : "00:00 PM") + (tail ? "  " + tail : "");
    }

    StyledText {
        id: widestTimeProbe
        theme: panel.theme
        mono: true
        visible: false
        text: panel.widestTime
    }

    // ----------------------------------------------------------------- rows
    Column {
        id: zoneColumn

        width: parent.width
        spacing: panel.theme.space(1)

        Repeater {
            model: panel.rows

            ZoneRow {
                required property var modelData
                required property int index

                width: zoneColumn.width
                row: modelData
                picked: panel.selectedRow === index
            }
        }
    }

    // --------------------------------------------------------------- footer
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        width: parent.width
        text: panel.hoverColumn >= 0 ? "Escape releases the reading cursor." : "Hover or arrow across a column to read every zone at that moment; up/down picks a city, t flips 12/24h, Alt+T °C/°F. The rule above a column marks peak hours — 01:00–04:00 and 06:00–10:00 UTC, Mon–Fri."
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component ZoneRow: Item {
        id: zoneRow

        property var row: null
        property bool picked: false

        readonly property var zone: row ? row.zone : null
        readonly property bool isHome: !!zone && !!panel.home && zone.zone === panel.home.zone
        // No reading (UTC, offline, not fetched yet) draws nothing at all.
        readonly property var weather: zone ? panel.timezones.weather[zone.zone] : undefined

        implicitHeight: rowLabels.implicitHeight + strip.implicitHeight + panel.theme.space(1)

        // The keyboard's pick, drawn with the shell's shared cursor surface.
        CursorSurface {
            theme: panel.theme
            anchors.fill: parent
            anchors.margins: -panel.theme.space(1)
            anchors.bottomMargin: 0
            hasCursor: zoneRow.picked
        }

        Column {
            anchors.fill: parent
            spacing: panel.theme.space(0.5)

            Item {
                id: rowLabels
                width: parent.width
                implicitHeight: Math.max(nameText.implicitHeight, timeText.implicitHeight)

                StyledText {
                    id: nameText

                    theme: panel.theme
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    // The home row is the one everything else is measured
                    // from, so it is the one drawn at full weight.
                    text: zoneRow.zone ? zoneRow.zone.label : ""
                    color: zoneRow.isHome ? panel.theme.textPrimary : panel.theme.textMuted
                    font.weight: zoneRow.isHome ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true

                    anchors.left: nameText.right
                    anchors.leftMargin: panel.theme.space(1.5)
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (!zoneRow.zone)
                            return "";
                        const parts = [];
                        if (zoneRow.zone.abbrev)
                            parts.push(zoneRow.zone.abbrev);
                        if (!zoneRow.isHome && panel.home)
                            parts.push(Model.relativeText(zoneRow.zone, panel.home));
                        return parts.join(" · ");
                    }
                    color: panel.theme.textMuted
                }

                // Temperature, then the condition glyph, right-aligned
                // against the time column so the glyphs line up.
                Row {
                    visible: !!zoneRow.weather
                    anchors.right: timeText.left
                    anchors.rightMargin: panel.theme.space(3)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(1)

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Caption
                        mono: true
                        anchors.verticalCenter: parent.verticalCenter
                        text: zoneRow.weather ? Model.tempText(zoneRow.weather.c, panel.timezones.imperial) : ""
                        color: panel.theme.textMuted
                    }

                    OpticalGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: zoneRow.weather ? WeatherModel.iconForOpenMeteoCode(zoneRow.weather.code, !zoneRow.weather.day) : ""
                        pixelSize: panel.theme.fontPx(1)
                        verticalInkCenter: true
                        color: panel.theme.textMuted
                    }
                }

                StyledText {
                    id: timeText

                    theme: panel.theme
                    mono: true

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(widestTimeProbe.implicitWidth, implicitWidth)
                    // Follows the reading cursor: hovering a column turns
                    // every row's read-out into that moment.
                    text: {
                        if (!zoneRow.zone)
                            return "";
                        const stamp = Model.clockText(zoneRow.zone, panel.readInstant, panel.hour24);
                        const delta = panel.home ? Model.dayDeltaText(zoneRow.zone, panel.home, panel.readInstant) : "";
                        return delta ? stamp + "  " + delta : stamp;
                    }
                    color: panel.theme.textPrimary
                }
            }

            // The hour strip. Cells are laid out by index so every row's
            // column N sits at the same x — that is what makes a column
            // readable as one instant.
            Row {
                id: strip

                width: parent.width
                spacing: 1

                Repeater {
                    model: zoneRow.row ? zoneRow.row.cells : []

                    Rectangle {
                        id: cell

                        required property var modelData
                        required property int index

                        width: (strip.width - (Model.GRID_COLUMNS - 1)) / Model.GRID_COLUMNS
                        height: panel.theme.space(5)
                        radius: panel.theme.radius(0.375)

                        readonly property bool reading: panel.readColumn === index

                        color: {
                            if (reading)
                                return panel.theme.alpha(panel.theme.accent, 0.28);
                            if (modelData.business)
                                return panel.theme.alpha(panel.theme.textPrimary, 0.10);
                            return panel.theme.alpha(panel.theme.textPrimary, 0.03);
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: panel.theme.motion.standard
                                easing.type: panel.theme.motion.easing
                            }
                        }

                        // Peak hours: a rule along the top edge. Because peak
                        // is a property of the instant, the same columns carry
                        // it in every row — so a run of rules reads as one
                        // band down the whole grid rather than a per-zone
                        // decoration, which is exactly what a UTC-defined
                        // window is.
                        Rectangle {
                            visible: cell.modelData.peak
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: Math.max(2, panel.theme.borderWidth * 2)
                            color: panel.theme.accent
                            opacity: 0.85
                        }

                        // Midnight: where the date turns over. Without this
                        // the strip is 18 numbers with no landmark in them.
                        Rectangle {
                            visible: cell.modelData.dayStart
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.max(1, panel.theme.borderWidth)
                            color: panel.theme.accent
                            opacity: 0.7
                        }

                        StyledText {
                            theme: panel.theme
                            role: StyledText.Caption
                            mono: true

                            anchors.centerIn: parent
                            text: Model.hourText(cell.modelData.hour, panel.hour24)
                            color: cell.reading || cell.modelData.business ? panel.theme.textPrimary : panel.theme.textMuted
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onContainsMouseChanged: panel.hoverColumn = containsMouse ? cell.index : -1
                        }
                    }
                }
            }
        }
    }
}

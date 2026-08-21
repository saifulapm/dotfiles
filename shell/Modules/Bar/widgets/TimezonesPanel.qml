import QtQuick
import "../components"
import "../../../components"
import "TimezonesModel.js" as Model

// Timezones panel — one row per zone, all of them aligned on the same
// absolute hours, so a column is a single moment read in every place at once.
// That alignment IS the feature: "10am here is what there" is a question a
// list of clocks cannot answer and a grid answers by being looked at.
//
// Each row carries the zone, its clock, how far it is from home, and a strip
// of hour numbers with the working day shaded and midnight marked. The
// current hour is a filled column running through every row.
//
// Hovering a column reads every row at that moment instead of at now — the
// same gesture worldtimebuddy uses, and the reason the grid beats three
// separate clocks.
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
        panel.timezones.refresh();
    }

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "World Clock"
        meta: panel.home ? (panel.hoverColumn >= 0 ? "Reading " + Model.clockText(panel.home, panel.readInstant) + " in " + panel.home.label : panel.home.label + " · " + Model.clockText(panel.home, panel.timezones.nowMs)) : "No zones"
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

    // ----------------------------------------------------------------- rows
    Column {
        id: zoneColumn

        width: parent.width
        spacing: panel.theme.space(1)

        Repeater {
            model: panel.rows

            ZoneRow {
                required property var modelData

                width: zoneColumn.width
                row: modelData
            }
        }
    }

    // --------------------------------------------------------------- footer
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        width: parent.width
        text: panel.hoverColumn >= 0 ? "Escape releases the reading cursor." : "Hover or arrow across a column to read every zone at that moment."
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component ZoneRow: Item {
        id: zoneRow

        property var row: null

        readonly property var zone: row ? row.zone : null
        readonly property bool isHome: !!zone && !!panel.home && zone.zone === panel.home.zone

        implicitHeight: rowLabels.implicitHeight + strip.implicitHeight + panel.theme.space(1)

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

                StyledText {
                    id: timeText

                    theme: panel.theme
                    mono: true

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    // Follows the reading cursor: hovering a column turns
                    // every row's read-out into that moment.
                    text: {
                        if (!zoneRow.zone)
                            return "";
                        const stamp = Model.clockText(zoneRow.zone, panel.readInstant);
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
                            text: cell.modelData.text
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

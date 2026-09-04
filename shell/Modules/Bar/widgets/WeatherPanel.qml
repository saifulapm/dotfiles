import QtQuick
import Quickshell.Io
import "../components"
import "../../../components"
import "WeatherModel.js" as Model

// Weather panel — full port of omarchy's weather Panel.qml in our tokens:
// a hero of the condition glyph and the temperature beside the location and
// the FEELS / WIND / HUMID read-outs, then the next three days as
// icon + day-name + high/low cells.
//
// The location label is click-to-edit: typing searches Open-Meteo's geocoder
// (debounced, one request in flight at a time), picking a suggestion stores
// the name AND its coordinates in the widget's inline shell.json entry, and
// committing an empty field clears back to IP auto-detect. The widget keeps
// showing the previous report while the new location loads, so nothing is
// ever presented under the wrong label.
BarPanel {
    id: panel

    required property var weather

    panelTitle: ""
    cardWidth: theme.space(107.5)

    // ---------------------------------------------------------- edit state
    property bool editingLocation: false
    property var locationSuggestions: []
    property int suggestionIndex: 0
    property string geocodePendingQuery: ""
    property string geocodeActiveQuery: ""
    // The query the current suggestions were geocoded FOR. Enter must not
    // commit a highlighted suggestion left over from an older query while the
    // newer text is still inside the debounce/fetch window.
    property string suggestionsQuery: ""

    function startEditingLocation() {
        editingLocation = true;
        locationSuggestions = [];
        suggestionIndex = 0;
        Qt.callLater(function () {
            locationField.text = panel.weather.configuredLocation;
            locationField.selectAll();
            locationField.takeFocus();
        });
    }

    function cancelEditingLocation() {
        editingLocation = false;
        locationSuggestions = [];
        geocodeDebounce.stop();
        Qt.callLater(panel.refocusKeys);
    }

    function commitLocation() {
        const suggestions = locationField.text.trim() === suggestionsQuery ? locationSuggestions : [];
        const location = Model.locationCommit(locationField.text, suggestions, suggestionIndex);
        if (location.name === "") {
            clearLocation();
            return;
        }
        panel.weather.persistLocation(location.name, location.latitude, location.longitude);
    }

    function clearLocation() {
        panel.weather.persistLocation("", null, null);
        panel.weather.wttrLocation = "";
        cancelEditingLocation();
    }

    function pickSuggestion(suggestion) {
        if (!suggestion)
            return;
        panel.weather.persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude);
    }

    // Debounced geocoding. Only one curl runs at a time; if the query moved
    // on while a fetch was in flight, the latest query is fetched right after.
    function requestGeocode() {
        const query = locationField.text.trim();
        if (query.length < 2) {
            locationSuggestions = [];
            return;
        }
        geocodePendingQuery = query;
        if (!geocodeProc.running)
            startGeocode();
    }

    function startGeocode() {
        geocodeActiveQuery = geocodePendingQuery;
        geocodeProc.command = ["curl", "-fsS", "--max-time", "5", "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"];
        geocodeProc.running = true;
    }

    onPanelClosed: if (editingLocation)
        cancelEditingLocation()

    // The save finishes when the report for the new location lands.
    Connections {
        target: panel.weather
        function onLocationSaved() {
            panel.cancelEditingLocation();
        }
    }

    Process {
        id: geocodeProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                panel.locationSuggestions = panel.editingLocation ? Model.parseGeocodingResults(text) : [];
                panel.suggestionsQuery = panel.editingLocation ? panel.geocodeActiveQuery : "";
                panel.suggestionIndex = 0;
                if (panel.geocodePendingQuery !== panel.geocodeActiveQuery)
                    Qt.callLater(panel.startGeocode);
            }
        }
    }

    Timer {
        id: geocodeDebounce
        interval: 300
        onTriggered: panel.requestGeocode()
    }

    // Enter on the card (nothing being edited) opens the location editor,
    // matching their PanelKeyCatcher.
    onContentKey: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!panel.editingLocation)
                panel.startEditingLocation();
            event.accepted = true;
        }
    }

    // ------------------------------------------------------------- hero row
    Item {
        width: parent.width
        height: Math.max(heroLeft.height, heroRight.height)

        Row {
            id: heroLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(3)

            OpticalGlyph {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.weather.label || "󰖐"
                color: panel.theme.textPrimary
                pixelSize: 52
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                Text {
                    id: tempBig
                    textFormat: Text.PlainText
                    text: panel.weather.reportTempNum || "—"
                    color: panel.theme.textPrimary
                    // Hero read-out: deliberately outside the font scale.
                    font.pixelSize: 46
                    font.family: panel.theme.fontUi
                    font.weight: Font.DemiBold
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Heading

                    anchors.top: tempBig.top
                    anchors.topMargin: panel.theme.space(2)
                    text: panel.weather.current ? panel.weather.tempUnit : ""
                }
            }
        }

        // The stats row is the widest thing on this side, so it sets the
        // column's width; everything else hangs off the right edge of it.
        Column {
            id: heroRight
            width: weatherStats.implicitWidth
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(3)

            // Location label — click to edit.
            Item {
                width: parent.width
                height: locationRow.implicitHeight
                visible: !panel.editingLocation && panel.weather.reportLocation !== ""

                Row {
                    id: locationRow
                    anchors.right: parent.right
                    spacing: panel.theme.space(1.5)

                    OpticalGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍎"
                        color: panel.theme.textMuted
                        pixelSize: panel.theme.fontPx(0.917)
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Small
                        muted: true

                        anchors.verticalCenter: parent.verticalCenter
                        text: (panel.weather.reportLocation || "").toUpperCase()
                        font.letterSpacing: 1
                    }
                }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: panel.startEditingLocation()
                }
            }

            // Location editor.
            Item {
                width: parent.width
                height: editorRow.implicitHeight
                visible: panel.editingLocation

                Row {
                    id: editorRow
                    anchors.right: parent.right
                    spacing: panel.theme.space(1.5)

                    PanelTextField {
                        id: locationField

                        theme: panel.theme

                        implicitHeight: panel.theme.space(7)

                        inputMargin: panel.theme.space(2)

                        inputFont: panel.theme.fontUi
                        width: panel.theme.space(42)
                        enabled: !panel.weather.savingLocation
                        placeholder: "Search city"

                        onTextEdited: if (panel.editingLocation && !panel.weather.savingLocation)
                            geocodeDebounce.restart()
                        onAccepted: panel.commitLocation()
                        onCancelled: panel.cancelEditingLocation()
                        onMoveRequested: delta => {
                            const next = panel.suggestionIndex + delta;
                            if (next >= 0 && next < panel.locationSuggestions.length)
                                panel.suggestionIndex = next;
                        }
                    }

                    // Clear back to IP auto-detect. While a committed location is
                    // loading this same affordance becomes a spinner.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: panel.theme.space(6)
                        height: width
                        radius: panel.theme.radius(0.75)
                        color: !panel.weather.savingLocation && clearHover.hovered ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : "transparent"

                        OpticalGlyph {
                            anchors.centerIn: parent
                            text: panel.weather.savingLocation ? "󰑐" : "󰅖"
                            color: panel.theme.textMuted
                            pixelSize: panel.theme.fontPx(0.917)

                            RotationAnimator on rotation {
                                running: panel.weather.savingLocation
                                from: 0
                                to: 360
                                duration: panel.theme.time(5.33)
                                loops: Animation.Infinite
                            }
                        }

                        HoverHandler {
                            id: clearHover
                            enabled: !panel.weather.savingLocation
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            enabled: !panel.weather.savingLocation
                            onTapped: panel.clearLocation()
                        }
                    }
                }
            }

            Row {
                id: weatherStats
                visible: !!panel.weather.current
                spacing: panel.theme.space(6)

                Stat {
                    caption: "FEELS"
                    value: panel.weather.reportFeels
                }

                Stat {
                    caption: "WIND"
                    value: panel.weather.reportWind
                }

                Stat {
                    caption: "HUMID"
                    value: panel.weather.reportHumidity
                }
            }
        }
    }

    // ------------------------------------------------ geocoding suggestions
    Column {
        visible: panel.editingLocation && !panel.weather.savingLocation && panel.locationSuggestions.length > 0
        width: parent.width
        spacing: 0

        Repeater {
            model: panel.locationSuggestions

            CursorSurface {
                id: suggestion

                required property var modelData
                required property int index

                theme: panel.theme
                width: parent.width
                height: suggestionRow.implicitHeight + panel.theme.space(3)
                // Arrowing through the suggestions moves the choice itself,
                // so the fill is the whole story.
                bordered: false
                current: index === panel.suggestionIndex

                Row {
                    id: suggestionRow
                    anchors.left: parent.left
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(2)

                    StyledText {
                        theme: panel.theme

                        text: suggestion.modelData.name
                        color: suggestion.index === panel.suggestionIndex ? panel.theme.accent : panel.theme.textPrimary
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Small
                        muted: true

                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        text: suggestion.modelData.description
                    }
                }

                HoverHandler {
                    id: suggestionHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered)
                        panel.suggestionIndex = suggestion.index
                }

                TapHandler {
                    onTapped: panel.pickSuggestion(suggestion.modelData)
                }
            }
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small
        muted: true

        visible: !panel.weather.current
        text: "Fetching forecast…"
        font.italic: true
    }

    Separator {
        theme: panel.theme
        visible: panel.weather.forecastDays.length > 0
    }

    // ---------------------------------------------------------- forecast row
    Item {
        visible: panel.weather.forecastDays.length > 0
        width: parent.width
        height: forecastRow.height

        Row {
            id: forecastRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: panel.theme.space(7)

            Repeater {
                model: panel.weather.forecastDays

                Row {
                    id: dayCell

                    required property var modelData

                    spacing: panel.theme.space(2)

                    OpticalGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.weather.dayIcon(dayCell.modelData)
                        color: panel.theme.textPrimary
                        pixelSize: panel.theme.fontPx(1.833)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: panel.theme.space(0.25)

                        StyledText {
                            theme: panel.theme
                            role: StyledText.Caption
                            muted: true

                            text: panel.weather.dayName(dayCell.modelData.date).toUpperCase()
                            font.letterSpacing: 1
                        }

                        Row {
                            spacing: panel.theme.space(1.5)

                            StyledText {
                                theme: panel.theme
                                mono: true

                                text: panel.weather.bareTempForDay(dayCell.modelData, "max")
                            }

                            StyledText {
                                theme: panel.theme
                                mono: true
                                muted: true

                                text: panel.weather.bareTempForDay(dayCell.modelData, "min")
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ components
    component Stat: Column {
        id: stat

        property string caption: ""
        property string value: ""

        spacing: panel.theme.space(1)

        StyledText {
            theme: panel.theme
            role: StyledText.Caption
            muted: true

            text: stat.caption
            font.letterSpacing: 1
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Title

            text: stat.value
        }
    }
}

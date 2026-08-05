import QtQuick
import Quickshell.Io
import "../components"
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
    cardWidth: 430

    // ---------------------------------------------------------- edit state
    property bool editingLocation: false
    property var locationSuggestions: []
    property int suggestionIndex: 0
    property string geocodePendingQuery: ""
    property string geocodeActiveQuery: ""

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
        const location = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex);
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
                spacing: 1

                Text {
                    id: tempBig
                    text: panel.weather.reportTempNum || "—"
                    color: panel.theme.textPrimary
                    // Hero read-out: deliberately outside the font scale.
                    font.pixelSize: 46
                    font.family: panel.theme.fontUi
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.top: tempBig.top
                    anchors.topMargin: panel.theme.space(2)
                    text: panel.weather.current ? panel.weather.tempUnit : ""
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(1.333)
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

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (panel.weather.reportLocation || "").toUpperCase()
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.833)
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

                    TextField {
                        id: locationField
                        width: panel.theme.space(42)
                        enabled: !panel.weather.savingLocation
                        placeholder: "Search city"

                        onTextEdited: if (panel.editingLocation && !panel.weather.savingLocation)
                            geocodeDebounce.restart()
                        onAccepted: panel.commitLocation()
                        onCancelled: panel.cancelEditingLocation()
                        onStepped: delta => {
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
                                duration: 800
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

            Rectangle {
                id: suggestion

                required property var modelData
                required property int index

                width: parent.width
                height: suggestionRow.implicitHeight + panel.theme.space(3)
                radius: panel.theme.radius(0.75)
                color: index === panel.suggestionIndex ? panel.theme.alpha(panel.theme.accent, 0.18) : "transparent"

                Row {
                    id: suggestionRow
                    anchors.left: parent.left
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(2)

                    Text {
                        text: suggestion.modelData.name
                        color: suggestion.index === panel.suggestionIndex ? panel.theme.accent : panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.917)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        text: suggestion.modelData.description
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.833)
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

    Text {
        visible: !panel.weather.current
        text: "Fetching forecast…"
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.833)
        font.italic: true
    }

    Rectangle {
        visible: panel.weather.forecastDays.length > 0
        width: parent.width
        height: 1
        color: panel.theme.surface3
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
                        pixelSize: 22
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: panel.weather.dayName(dayCell.modelData.date).toUpperCase()
                            color: panel.theme.textMuted
                            font.family: panel.theme.fontUi
                            font.pixelSize: panel.theme.fontPx(0.75)
                            font.letterSpacing: 1
                        }

                        Row {
                            spacing: panel.theme.space(1.5)

                            Text {
                                text: panel.weather.bareTempForDay(dayCell.modelData, "max")
                                color: panel.theme.textPrimary
                                font.family: panel.theme.fontMono
                                font.pixelSize: panel.theme.fontPx(0.917)
                            }

                            Text {
                                text: panel.weather.bareTempForDay(dayCell.modelData, "min")
                                color: panel.theme.textMuted
                                font.family: panel.theme.fontMono
                                font.pixelSize: panel.theme.fontPx(0.917)
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

        Text {
            text: stat.caption
            color: panel.theme.textMuted
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.75)
            font.letterSpacing: 1
        }

        Text {
            text: stat.value
            color: panel.theme.textPrimary
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(1.083)
        }
    }

    // Bordered single-line input for the location search.
    component TextField: Rectangle {
        id: field

        property string placeholder: ""
        property alias text: input.text

        signal textEdited(string text)
        signal accepted
        signal cancelled
        signal stepped(int delta)

        function takeFocus() {
            input.forceActiveFocus();
        }

        function selectAll() {
            input.selectAll();
        }

        implicitHeight: panel.theme.space(7)
        radius: panel.theme.radius(0.75)
        color: panel.theme.surface2
        border.width: panel.theme.borderWidth
        border.color: input.activeFocus ? panel.theme.accent : panel.theme.surface3
        opacity: enabled ? 1 : 0.5

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            verticalAlignment: TextInput.AlignVCenter
            color: panel.theme.textPrimary
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.917)
            clip: true

            onTextChanged: field.textEdited(text)
            onAccepted: field.accepted()
            Keys.onEscapePressed: field.cancelled()
            Keys.onDownPressed: field.stepped(1)
            Keys.onUpPressed: field.stepped(-1)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: field.placeholder
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "WeatherModel.js" as Model

// Weather — full port of omarchy's weather plugin (CREDITS.md). The bar slot
// carries the condition glyph and the temperature; the panel is the detail
// view. DELIBERATE no-polling exception: weather has no event source, so the
// report refreshes on a timer (default 30 min, `refreshMinutes` in the
// widget's inline shell.json entry) plus on panel open and on middle click.
//
// Two sources, as upstream: wttr.in for the full report (conditions text,
// nearest area, hourly forecast) and Open-Meteo for the fast day/night-aware
// current conditions and the daily forecast. Open-Meteo answers in a fraction
// of wttr's time, so with coordinates stored it is fetched straight away and
// drives the bar glyph; wttr fills in behind it.
//
// The location lives in the inline settings entry as `location` (+ optional
// `latitude`/`longitude`); the old plain-text
// ~/.local/state/qshell/weather-location file is still honoured when no
// location has been configured inline.
BarButton {
    id: rootItem

    // ---------------------------------------------------------- configuration
    property string fallbackLocationName: ""

    readonly property var configuredLocationState: Model.parseLocationSettings(setting("location", ""), setting("latitude", null), setting("longitude", null), fallbackLocationName)
    readonly property string configuredLocation: configuredLocationState.name
    readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)
    readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))

    // Auto-refresh interval in minutes; clamped to a sane minimum.
    readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 30), 10) || 30)

    // ---------------------------------------------------------------- report
    // Parsed responses. Kept on failure so stale data stays visible.
    property var report: null
    property var dailyForecastReport: null
    property string wttrLocation: ""
    property string label: ""
    property bool savingLocation: false
    property bool savingLocationQueryStarted: false

    readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
    readonly property var current: (hasConfiguredCoordinates && openMeteoCurrent) ? openMeteoCurrent : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
    readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
    readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""
    readonly property var forecastDays: Model.buildForecastDays(report, dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))

    readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)

    readonly property string reportLocation: configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
    readonly property string reportTempNum: current ? String(useImperial ? current.temp_F : current.temp_C) : ""
    readonly property string tempUnit: "°" + (useImperial ? "F" : "C")
    readonly property string reportFeels: current ? Model.formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC, useImperial) : ""
    readonly property string reportWind: current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
    readonly property string reportHumidity: current ? (current.humidity + "%") : ""
    readonly property string reportDescription: Model.currentDescription(current)

    property int forecastRetries: 0
    property int dailyForecastRetries: 0

    function dayName(dateString) {
        return Model.dayName(dateString, d => Qt.formatDate(d, "dddd"));
    }

    function dayIcon(day) {
        return Model.dayIcon(day);
    }

    function bareTempForDay(day, kind) {
        return Model.bareTempForDay(day, kind, useImperial);
    }

    // ---------------------------------------------------------------- fetching
    function refresh() {
        // Each full refresh cycle gets a fresh retry budget, so an earlier
        // exhausted round (waking with the network still down, say) doesn't
        // starve retries for the rest of the session.
        forecastRetries = 0;
        dailyForecastRetries = 0;
        if (!forecastProc.running)
            forecastProc.running = true;
        if (locationQuery === "" && !locationProc.running)
            locationProc.running = true;
        // With stored coordinates this fetches Open-Meteo right away — no
        // need to wait for the slow wttr response. Without them it's a no-op
        // until wttr reports the detected area.
        refreshDailyForecast(null);
    }

    function refreshDailyForecast(sourceReport) {
        if (dailyForecastProc.running)
            return;

        let lat = parseFloat(String(configuredLocationState.latitude));
        let lon = parseFloat(String(configuredLocationState.longitude));
        if (isNaN(lat) || isNaN(lon)) {
            const area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : areaInfo;
            if (!area)
                return;
            lat = parseFloat(String(area.latitude || ""));
            lon = parseFloat(String(area.longitude || ""));
        }
        if (isNaN(lat) || isNaN(lon))
            return;

        dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", "https://api.open-meteo.com/v1/forecast" + "?latitude=" + encodeURIComponent(String(lat)) + "&longitude=" + encodeURIComponent(String(lon)) + "&daily=weather_code,temperature_2m_max,temperature_2m_min" + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day" + "&forecast_days=4" + "&timezone=auto"];
        dailyForecastProc.running = true;
    }

    // wttr.in can be slow or flaky, especially for a location it has not
    // cached yet. Retry a few times before leaving it to the refresh timer.
    function scheduleForecastRetry() {
        if (forecastRetries >= 3)
            return;
        forecastRetries++;
        forecastRetryTimer.restart();
    }

    // With configured coordinates this fetch is the only thing that updates
    // the bar glyph, so a dropped response must retry rather than wait out
    // the refresh timer showing a stale icon.
    function scheduleDailyForecastRetry() {
        if (dailyForecastRetries >= 3)
            return;
        dailyForecastRetries++;
        dailyForecastRetryTimer.restart();
    }

    // Keep the previous report visible while the new location loads, so
    // stale data is never presented under a newly configured label.
    onLocationQueryChanged: {
        if (savingLocation)
            savingLocationQueryStarted = true;
        forecastRetries = 0;
        dailyForecastRetries = 0;
        forecastProc.running = false;
        dailyForecastProc.running = false;
        Qt.callLater(refresh);
    }

    function finishSavingLocation() {
        if (savingLocation && savingLocationQueryStarted) {
            savingLocation = false;
            savingLocationQueryStarted = false;
            locationSaved();
        }
    }

    signal locationSaved

    // ------------------------------------------------------------ persistence
    function persistSettings(values) {
        const entry = {
            id: "weather"
        };
        for (const key in settings) {
            if (key !== "id")
                entry[key] = settings[key];
        }
        for (const key in values) {
            if (values[key] === null || values[key] === "")
                delete entry[key];
            else
                entry[key] = values[key];
        }
        settings = entry;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
            bar.shell.updateEntryInline("weather", entry);
    }

    // Save a picked location into the inline entry. Clearing it (empty name)
    // returns the widget to IP auto-detect — and drops the legacy state-file
    // fallback with it, so clearing really clears.
    function persistLocation(name, latitude, longitude) {
        const previousQuery = locationQuery;
        savingLocation = name !== "";
        savingLocationQueryStarted = false;
        if (name === "")
            fallbackLocationName = "";
        persistSettings({
            location: name || null,
            latitude: latitude === null || latitude === undefined ? null : latitude,
            longitude: longitude === null || longitude === undefined ? null : longitude
        });
        // Re-picking the location already configured changes no query, so no
        // response is coming to clear the spinner; finish it here.
        if (savingLocation && locationQuery === previousQuery) {
            savingLocationQueryStarted = true;
            finishSavingLocation();
        }
    }

    // --------------------------------------------------------------- bar slot
    visible: label !== ""
    tooltipText: current ? (reportDescription + " · feels like " + reportFeels) : ""

    function openPanel() {
        panelLoader.active = true;
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
        if (panelLoader.item.opened)
            refresh();
    }

    onTapped: button => {
        if (button === Qt.MiddleButton)
            refresh();
        else
            openPanel();
    }

    // Legacy location file: a bare city name, honoured only while no inline
    // location is configured.
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/qshell/weather-location"
        watchChanges: true
        printErrors: false
        onLoaded: rootItem.fallbackLocationName = text().trim()
        onFileChanged: reload()
        onLoadFailed: rootItem.fallbackLocationName = ""
    }

    Process {
        id: forecastProc
        command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/" + rootItem.locationQuery + "?format=j1"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (!raw) {
                    rootItem.scheduleForecastRetry();
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    rootItem.report = parsed;
                    if (!rootItem.hasConfiguredCoordinates)
                        rootItem.label = Model.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], rootItem.label);
                    rootItem.forecastRetries = 0;
                    if (Model.weatherResponseCompletesSave(rootItem.hasConfiguredCoordinates, "wttr"))
                        rootItem.finishSavingLocation();
                    // Stored coordinates already drove the fast Open-Meteo
                    // fetch from refresh(); only auto-detect needs the area
                    // wttr reported.
                    if (isNaN(parseFloat(String(rootItem.configuredLocationState.latitude))))
                        rootItem.refreshDailyForecast(parsed);
                } catch (e) {
                    // Keep last-good report visible, but try again shortly.
                    rootItem.scheduleForecastRetry();
                }
            }
        }
    }

    Process {
        id: dailyForecastProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (!raw) {
                    rootItem.scheduleDailyForecastRetry();
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    rootItem.dailyForecastReport = parsed;
                    rootItem.label = Model.currentIcon(Model.openMeteoCurrentCondition(parsed), rootItem.label);
                    rootItem.dailyForecastRetries = 0;
                    if (Model.weatherResponseCompletesSave(rootItem.hasConfiguredCoordinates, "open-meteo"))
                        rootItem.finishSavingLocation();
                } catch (e) {
                    // Keep last-good daily forecast visible, retry shortly.
                    rootItem.scheduleDailyForecastRetry();
                }
            }
        }
    }

    // Name of the IP-detected area, for the panel's location label.
    Process {
        id: locationProc
        command: ["curl", "-fsS", "--max-time", "4", "https://wttr.in/?format=%l"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (raw)
                    rootItem.wttrLocation = raw.split(",")[0];
            }
        }
    }

    Timer {
        id: forecastRetryTimer
        interval: 2500
        onTriggered: if (!forecastProc.running)
            forecastProc.running = true
    }

    Timer {
        id: dailyForecastRetryTimer
        interval: 2500
        onTriggered: rootItem.refreshDailyForecast(null)
    }

    // Stamp of the last timer-driven refresh, so re-arming (the bar coming
    // back from `bar hide`) doesn't refetch data that is still fresh —
    // triggeredOnStart fires on every re-arm.
    property double lastAutoRefreshMs: 0

    Timer {
        interval: rootItem.refreshMinutes * 60 * 1000
        // The refresh cadence is scoped to a bar that is actually on screen
        // (Dropbox's pollingAllowed): nothing fetches while the bar is
        // hidden. Panel open and middle click still refresh directly.
        running: rootItem.bar !== null && rootItem.bar.visible === true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            if (now - rootItem.lastAutoRefreshMs < interval * 0.9)
                return;
            rootItem.lastAutoRefreshMs = now;
            rootItem.refresh();
        }
    }

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: rootItem.label
        color: rootItem.contentColor
        pixelSize: 13
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        // Their weather bar widget is glyph-only; ours adds the temperature,
        // which is the part that has no room on a vertical bar.
        visible: !rootItem.vertical && rootItem.reportTempNum !== ""
        text: rootItem.reportTempNum + "°"
        color: rootItem.contentColor
        font.family: rootItem.theme.fontMono
        font.pixelSize: rootItem.theme.fontPx(0.917)
        renderType: Text.NativeRendering
    }

    LazyLoader {
        id: panelLoader
        active: false
        component: WeatherPanel {
            theme: rootItem.theme
            weather: rootItem
        }
    }
}

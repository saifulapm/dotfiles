import QtQuick
import Quickshell
import Quickshell.Io
import "TimezonesModel.js" as Model
import "WeatherModel.js" as WeatherModel

// Timezones service — the world clock's zone list and their current offsets.
// ONE instance however many screens carry the widget (S2); created at the bar
// root, with its settings bound to the widget's inline shell.json entry.
//
// TWO CADENCES, and neither is a poll.
//
// The minute hand is Quickshell's own SystemClock at Minutes precision — the
// same object the clock widget ticks on, so a second widget showing times
// adds no second timer to the shell.
//
// The offsets are re-read only when they actually change. bin/timezone-offsets
// reports each zone's next DST transition, and the service arms a single
// one-shot timer for the soonest of them; when it fires, the offsets are
// re-read and the next one is armed. For a fleet watching Dhaka, London and
// New York that is about four process launches a YEAR. The alternative — the
// obvious one — is asking the system for offsets every minute forever, and it
// is exactly what the no-polling rule exists to refuse.
QtObject {
    id: root

    // The widget's inline shell.json entry, e.g.
    //   {"id": "timezones", "zones": ["Europe/London", "America/New_York"]}
    property var settings: ({})
    // Injected by the bar root: the shell (for updateEntryInline), and the
    // weather service when that widget is configured, whose unit choice the
    // weather column follows until units are flipped here.
    property var shellRoot: null
    property var weatherService: null

    // Panel display choices, persisted in the same inline entry as the zones
    // (Elsewhen's hour24/units keys). 24-hour stays the default: it is what
    // the panel always showed.
    readonly property bool hour24: !settings || settings.hour24 !== false
    readonly property bool imperial: {
        const units = String(settings && settings.units || "").toUpperCase();
        if (units === "F" || units === "C")
            return units === "F";
        return weatherService ? weatherService.useImperial : WeatherModel.localeUsesImperial(Qt.locale().name);
    }

    function toggleHour24() {
        persistSettings({
            hour24: !hour24
        });
    }

    function toggleUnits() {
        persistSettings({
            units: imperial ? "C" : "F"
        });
    }

    // WeatherService.persistSettings, for this entry.
    function persistSettings(values) {
        const entry = {
            id: "timezones"
        };
        for (const key in settings) {
            if (key !== "id")
                entry[key] = settings[key];
        }
        for (const key in values)
            entry[key] = values[key];
        if (shellRoot && typeof shellRoot.updateEntryInline === "function")
            shellRoot.updateEntryInline("timezones", entry);
    }

    property bool probed: false
    // At least one configured zone resolved. A widget configured with no
    // zones, or only unknown ones, takes no width.
    property bool available: false

    property var zones: []
    // The system's own zone, so the model knows which row is "here".
    property string systemZone: ""

    // Ticks once a minute, Quickshell-native. Everything time-dependent in
    // the widget and the panel reads THIS rather than Date.now(), so every
    // surface updates on the same edge instead of drifting apart.
    readonly property var clock: SystemClock {
        precision: SystemClock.Minutes
    }
    readonly property double nowMs: clock.date ? clock.date.getTime() : 0

    readonly property var home: Model.homeZone(zones, systemZone)
    readonly property int zoneCount: zones.length
    readonly property string tooltip: Model.tooltipText(zones, home, nowMs)

    // Inside a peak window right now. Recomputed on the same minute tick as
    // the clocks, so the mark flips within a minute of the boundary and no
    // separate timer exists to keep it honest. One answer for the whole shell:
    // peak is stated in UTC, not per zone.
    readonly property bool peak: Model.isPeakInstant(nowMs)

    property bool refreshing: false
    property string lastError: ""

    property string _output: ""
    property string _error: ""

    // The zones asked for, defaulted to something useful rather than empty:
    // a widget added to the bar with no configuration should show something
    // on its first open, not an empty card with instructions.
    readonly property var configuredZones: {
        const raw = settings && settings.zones;
        if (Array.isArray(raw) && raw.length > 0)
            return raw.map(zone => String(zone)).filter(zone => zone !== "");
        return ["UTC", "Europe/London", "America/New_York"];
    }

    onConfiguredZonesChanged: refresh()

    function refresh() {
        if (offsetsProcess.running)
            return;
        _output = "";
        _error = "";
        refreshing = true;
        offsetsProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "timezone-offsets"].concat(configuredZones);
        offsetsProcess.running = true;
    }

    function applyOffsets(raw) {
        const parsed = Model.parseRows(raw);
        probed = true;
        available = parsed.length > 0;
        zones = parsed;
        lastError = "";
        armTransition();
    }

    // Arm the one-shot re-read for the soonest DST boundary across all zones.
    //
    // Qt timers take a 32-bit millisecond interval, so anything past ~24.8
    // days has to be clamped; the timer then re-arms on each expiry until the
    // real boundary arrives. That makes the worst case about fifteen wakeups
    // a year rather than one, which is still not a cadence — and it is the
    // only honest way to express "in four months" to a QTimer.
    function armTransition() {
        transitionTimer.stop();
        const at = Model.earliestTransition(zones);
        if (at <= 0)
            return;
        const deltaMs = at * 1000 - Date.now();
        if (deltaMs <= 0) {
            // Already past: the offsets we just read are the new ones, and
            // the next boundary comes with the next read.
            return;
        }
        const maxInterval = 20 * 24 * 60 * 60 * 1000; // comfortably inside 2^31 ms
        transitionTimer.interval = Math.min(deltaMs + 1000, maxInterval);
        transitionTimer.reArm = deltaMs > maxInterval;
        transitionTimer.start();
    }

    // ------------------------------------------------------------ weather
    // Current conditions per city, for the panel's weather column. Fetched
    // only when the panel opens (no cadence of its own), for the cities whose
    // reading is older than Model.WEATHER_TTL_MS, all in one request. Kept
    // here rather than in the panel so the cache outlives panel eviction.
    // A failed fetch changes nothing: rows without a reading show no weather.
    property var weather: ({}) // zone -> { c, code, day, at }

    function refreshWeather() {
        if (weatherProc.running)
            return;
        // zone1970.tab is read on the first open, not at shell start.
        if (zoneTab.path === "") {
            zoneTab.path = "/usr/share/zoneinfo/zone1970.tab";
            return; // onLoaded comes back here
        }
        const tab = zoneTab.text();
        const now = Date.now();
        const keys = [];
        const points = [];
        for (const zone of zones) {
            const at = Model.zoneTabCoords(tab, zone.zone);
            if (at && Model.weatherStale(weather[zone.zone], now)) {
                keys.push(zone.zone);
                points.push(at);
            }
        }
        if (keys.length === 0)
            return;
        weatherProc.keys = keys;
        weatherProc.command = ["curl", "-fsS", "--max-time", "8", Model.forecastUrl(points)];
        weatherProc.running = true;
    }

    readonly property FileView zoneTab: FileView {
        path: ""
        printErrors: false
        onLoaded: root.refreshWeather()
    }

    readonly property Process weatherProc: Process {
        property var keys: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.weather = Object.assign({}, root.weather, Model.parseForecast(text, root.weatherProc.keys, Date.now()))
        }
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // ----------------------------------------------------------- the clocks
    // Not a cadence: one shot, aimed at a known instant. `reArm` distinguishes
    // "the boundary is here, re-read" from "the wait was clamped, keep
    // waiting" — without it a transition four months out would re-read the
    // offsets every twenty days and find nothing changed.
    readonly property Timer transitionTimer: Timer {
        property bool reArm: false
        repeat: false
        onTriggered: {
            if (reArm)
                root.armTransition();
            else
                root.refresh();
        }
    }

    // --------------------------------------------------------- the processes
    readonly property Process offsetsProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            id: offsetsStdout
            waitForEnd: true
            onStreamFinished: root._output = text
        }
        stderr: StdioCollector {
            id: offsetsStderr
            waitForEnd: true
            onStreamFinished: root._error = text
        }
        onExited: exitCode => {
            root.refreshing = false;
            const out = String(offsetsStdout.text || root._output || "");
            const err = String(offsetsStderr.text || root._error || "");
            if (exitCode === 0 && out !== "") {
                root.applyOffsets(out);
                // stderr carries per-zone "unknown zone" lines while stdout
                // still holds the zones that did resolve — surface them
                // without throwing away the good rows.
                if (err !== "")
                    root.lastError = root.elideStatus(err);
            } else {
                root.probed = true;
                root.available = false;
                root.lastError = root.elideStatus(err || "Could not read timezone offsets");
            }
        }
    }

    // The machine's own zone, read once. It changes only when someone runs
    // bin/timezone-set, which restarts the shell's dependents anyway.
    readonly property Process systemZoneProcess: Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.systemZone = String(text || "").trim()
        }
    }

    Component.onCompleted: refresh()
}

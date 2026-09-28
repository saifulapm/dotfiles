// World-clock model — the arithmetic behind the timezones widget, as pure
// functions so it can be checked under node (TimezonesModel.test.js).
//
// Input is bin/timezone-offsets' TSV, one zone per line:
//
//   zone<TAB>offsetSeconds<TAB>abbrev<TAB>nextTransitionEpoch
//
// THE WHOLE FILE IS OFFSET ARITHMETIC, and it is written that way because
// Quickshell's QML engine has no Intl: `Intl is not defined`, measured inside
// the real engine 2026-08-21. Without ECMA-402 there is no
// `toLocaleString(…, {timeZone})`, so a zone's wall clock has to be computed
// rather than formatted.
//
// The technique is the standard one: a Date holds an absolute instant, so
// adding the zone's UTC offset to it and then reading the *UTC* getters
// yields that zone's wall clock. getUTCHours() on (instant + offset) is what
// a clock in that zone reads. Never getHours() — that would apply the local
// machine's offset a second time.

var HOUR_MS = 3600000;
var DAY_MS = 86400000;

// The window the grid covers, centred on the current hour. Twelve each way is
// a day's span without the columns becoming unreadably thin at this card
// width, and it puts "now" in the middle where the eye starts.
var GRID_BEFORE = 6;
var GRID_AFTER = 11;
var GRID_COLUMNS = GRID_BEFORE + GRID_AFTER + 1;

// Local hours that count as someone's working day, for the grid's shading.
// Inclusive start, exclusive end.
var BUSINESS_START = 9;
var BUSINESS_END = 18;

// Peak hours: 01:00–04:00 and 06:00–10:00 UTC, Monday through Friday.
// Inclusive start, exclusive end — the same convention as BUSINESS_START/END,
// so 04:00 and 10:00 are already off-peak.
//
// These are stated in UTC and MUST stay that way. Peak is a property of the
// instant, not of where anyone is standing, which is why a grid column — one
// absolute moment read in every row — is either peak or it isn't for the whole
// column at once.
var PEAK_WINDOWS = [[1, 4], [6, 10]];

function parseRows(raw) {
    var zones = [];
    var lines = String(raw || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        if (!lines[i])
            continue;
        var columns = lines[i].split("\t");
        var name = String(columns[0] || "").trim();
        if (!name)
            continue;
        zones.push({
            zone: name,
            label: labelFor(name),
            offset: Number(columns[1]) || 0,
            abbrev: String(columns[2] || "").trim(),
            nextTransition: Number(columns[3]) || 0,
            order: zones.length
        });
    }
    return zones;
}

// "America/New_York" -> "New York", "Asia/Dhaka" -> "Dhaka", "UTC" -> "UTC".
// The area prefix is dropped: it is a tzdata filing detail, and nobody calls
// it "America/New York".
function labelFor(zone) {
    var name = String(zone || "");
    var tail = name.indexOf("/") === -1 ? name : name.split("/").pop();
    return tail.replace(/_/g, " ");
}

// The instant `nowMs`, shifted into the zone's wall clock. The returned Date
// must only ever be read through its UTC getters — see the header.
function wallClock(zone, nowMs) {
    var offset = zone && isFinite(Number(zone.offset)) ? Number(zone.offset) : 0;
    return new Date(Number(nowMs) + offset * 1000);
}

function padTwo(value) {
    return (value < 10 ? "0" : "") + value;
}

// 24-hour unless hour24 is exactly false, so every existing caller keeps the
// "08:05" it always had. 12-hour reads "8:05 AM", as the bar clock does.
function clockText(zone, nowMs, hour24) {
    var wall = wallClock(zone, nowMs);
    var hour = wall.getUTCHours();
    if (hour24 !== false)
        return padTwo(hour) + ":" + padTwo(wall.getUTCMinutes());
    return (hour % 12 || 12) + ":" + padTwo(wall.getUTCMinutes()) + (hour < 12 ? " AM" : " PM");
}

// A grid cell's number: "08" on the 24-hour clock, "8" on the 12-hour one,
// where the cell is too narrow for a meridiem and the shading says day or night.
function hourText(hour, hour24) {
    return hour24 === false ? String(hour % 12 || 12) : padTwo(hour);
}

function hourOf(zone, nowMs) {
    return wallClock(zone, nowMs).getUTCHours();
}

// Which calendar day this zone is on relative to the home zone: -1, 0 or +1.
// Computed by comparing the two wall clocks' day numbers rather than their
// offsets, so a zone 30 or 45 minutes off the hour (Kathmandu, Adelaide) is
// handled by the same arithmetic as everything else.
function dayDelta(zone, home, nowMs) {
    if (!zone || !home)
        return 0;
    var zoneDay = Math.floor(wallClock(zone, nowMs).getTime() / DAY_MS);
    var homeDay = Math.floor(wallClock(home, nowMs).getTime() / DAY_MS);
    return zoneDay - homeDay;
}

// "Tomorrow" / "Yesterday" / "" — spelled out rather than "+1", which reads
// like an offset and is the thing most likely to be misread in a table full
// of offsets.
function dayDeltaText(zone, home, nowMs) {
    var delta = dayDelta(zone, home, nowMs);
    if (delta > 0)
        return "Tomorrow";
    if (delta < 0)
        return "Yesterday";
    return "";
}

// The difference from home, as a person would say it: "+5h", "-3h30",
// "same time".
function relativeText(zone, home) {
    if (!zone || !home)
        return "";
    var minutes = Math.round((Number(zone.offset) - Number(home.offset)) / 60);
    if (minutes === 0)
        return "same time";
    var sign = minutes > 0 ? "+" : "−"; // U+2212, so it lines up under a digit
    var abs = Math.abs(minutes);
    var hours = Math.floor(abs / 60);
    var rest = abs % 60;
    return sign + hours + "h" + (rest ? padTwo(rest) : "");
}

function isBusinessHour(hour) {
    return hour >= BUSINESS_START && hour < BUSINESS_END;
}

// Whether an absolute instant falls inside a peak window. Read through the UTC
// getters only — same as the rest of this file — so the answer is identical on
// every machine no matter what the local zone is.
function isPeakInstant(ms) {
    var at = new Date(Number(ms) || 0);
    var day = at.getUTCDay(); // 0 Sunday … 6 Saturday
    if (day < 1 || day > 5)
        return false;
    var hour = at.getUTCHours();
    for (var i = 0; i < PEAK_WINDOWS.length; i++) {
        if (hour >= PEAK_WINDOWS[i][0] && hour < PEAK_WINDOWS[i][1])
            return true;
    }
    return false;
}

// The absolute instants the grid's columns stand for: the current hour,
// truncated, with GRID_BEFORE hours behind it and GRID_AFTER ahead. Truncated
// to the hour in the HOME zone rather than in UTC, so the column boundaries
// line up with the home row's hour marks — a zone offset by 30 minutes would
// otherwise put every column half an hour out.
function gridInstants(home, nowMs) {
    var homeWall = wallClock(home, nowMs).getTime();
    var truncated = Math.floor(homeWall / HOUR_MS) * HOUR_MS;
    var homeOffsetMs = (home && isFinite(Number(home.offset)) ? Number(home.offset) : 0) * 1000;
    var origin = truncated - homeOffsetMs;
    var instants = [];
    for (var i = -GRID_BEFORE; i <= GRID_AFTER; i++)
        instants.push(origin + i * HOUR_MS);
    return instants;
}

// One row of cells per zone, every row aligned on the same absolute instants
// — which is the entire point of the grid: a column is one moment, read in
// every place at once.
function gridRow(zone, instants, home) {
    var cells = [];
    for (var i = 0; i < instants.length; i++) {
        var wall = wallClock(zone, instants[i]);
        var hour = wall.getUTCHours();
        cells.push({
            hour: hour,
            text: padTwo(hour),
            business: isBusinessHour(hour),
            // Midnight gets a marker: it is where the date changes, and a
            // strip of hour numbers alone does not show that.
            dayStart: hour === 0,
            isNow: i === GRID_BEFORE,
            // Carried per cell so the strip can draw it, but it is the same
            // value down the whole column — the instant decides, not the zone.
            peak: isPeakInstant(instants[i]),
            day: dayDelta(zone, home, instants[i])
        });
    }
    return cells;
}

function grid(zones, home, nowMs) {
    var instants = gridInstants(home, nowMs);
    return (Array.isArray(zones) ? zones : []).map(function (zone) {
        return {
            zone: zone,
            cells: gridRow(zone, instants, home)
        };
    });
}

// The home zone is whichever row matches the system zone, else the first.
// Everything relative — the day deltas, the "+5h", the grid alignment — is
// measured from it.
function homeZone(zones, systemZone) {
    var rows = Array.isArray(zones) ? zones : [];
    if (rows.length === 0)
        return null;
    var name = String(systemZone || "");
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].zone === name)
            return rows[i];
    }
    return rows[0];
}

// When the cached offsets stop being true: the soonest transition across
// every zone, or 0 if none of them has one. This is what lets the service
// schedule a single one-shot re-read instead of polling — see
// bin/timezone-offsets for why the column exists.
function earliestTransition(zones) {
    var rows = Array.isArray(zones) ? zones : [];
    var soonest = 0;
    for (var i = 0; i < rows.length; i++) {
        var at = Number(rows[i].nextTransition) || 0;
        if (at > 0 && (soonest === 0 || at < soonest))
            soonest = at;
    }
    return soonest;
}

// The bar tooltip: every zone on one line each, home first, then what the
// mark's colour means. Without that last line a warm globe is a colour change
// with no explanation attached to it.
function tooltipText(zones, home, nowMs) {
    var rows = Array.isArray(zones) ? zones : [];
    if (rows.length === 0)
        return "World clock — no zones configured";
    var lines = rows.map(function (zone) {
        var line = zone.label + "  " + clockText(zone, nowMs);
        var delta = dayDeltaText(zone, home, nowMs);
        return delta ? line + " (" + delta.toLowerCase() + ")" : line;
    });
    lines.push("");
    lines.push(isPeakInstant(nowMs) ? "Peak hours" : "Off-peak");
    return lines.join("\n");
}

// ---------------------------------------------------------------- weather
// Per-city current conditions for the panel's weather column, after
// omarchy's Elsewhen (its Model.js weather block): coordinates from
// zone1970.tab, one batched Open-Meteo request, a 20-minute freshness window.

var WEATHER_TTL_MS = 20 * 60 * 1000;

// The zone's representative city from zone1970.tab (ISO 6709) — Elsewhen's
// offline fallback, and here the whole lookup: a row's label IS that city
// ("Asia/Dhaka" -> Dhaka), so a geocoder could only agree with it or be wrong.
// Zones with no city (UTC) have no line, and get no weather.
function zoneTabCoords(tabText, zone) {
    var lines = String(tabText || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var parts = lines[i].split("\t");
        if (lines[i].charAt(0) === "#" || parts.length < 3 || parts[2] !== zone)
            continue;
        var m = /^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/.exec(parts[1]);
        if (!m)
            return null;
        return {
            lat: Math.round(isoDegrees(m[1], m[2], m[3], m[4]) * 1e4) / 1e4,
            lon: Math.round(isoDegrees(m[5], m[6], m[7], m[8]) * 1e4) / 1e4
        };
    }
    return null;
}

function isoDegrees(sign, d, mm, ss) {
    return (sign === "-" ? -1 : 1) * (Number(d) + Number(mm) / 60 + Number(ss || 0) / 3600);
}

// Every point in ONE request: Open-Meteo takes comma-separated coordinate
// lists and answers with an array in request order.
function forecastUrl(points) {
    return "https://api.open-meteo.com/v1/forecast?current=temperature_2m,weather_code,is_day&temperature_unit=celsius" + "&latitude=" + points.map(function (p) {
        return p.lat;
    }).join(",") + "&longitude=" + points.map(function (p) {
        return p.lon;
    }).join(",");
}

// { key: { c, code, day, at } }. One point comes back as an object, several
// as an array; anything unparseable is simply no weather.
function parseForecast(text, keys, nowMs) {
    var payload;
    try {
        payload = JSON.parse(text);
    } catch (e) {
        return {};
    }
    if (!Array.isArray(payload))
        payload = [payload];
    var out = {};
    for (var i = 0; i < keys.length && i < payload.length; i++) {
        var current = (payload[i] && payload[i].current) || {};
        if (current.temperature_2m === undefined || current.temperature_2m === null)
            continue;
        out[keys[i]] = {
            c: current.temperature_2m,
            code: current.weather_code,
            day: current.is_day !== 0,
            at: nowMs
        };
    }
    return out;
}

function weatherStale(entry, nowMs) {
    return !entry || nowMs - entry.at >= WEATHER_TTL_MS;
}

function tempText(celsius, imperial) {
    if (celsius === undefined || celsius === null || !isFinite(Number(celsius)))
        return "";
    if (imperial)
        return Math.round(Number(celsius) * 9 / 5 + 32) + "°F";
    return Math.round(Number(celsius)) + "°C";
}

if (typeof module !== "undefined") {
    module.exports = {
        BUSINESS_END: BUSINESS_END,
        BUSINESS_START: BUSINESS_START,
        DAY_MS: DAY_MS,
        GRID_AFTER: GRID_AFTER,
        GRID_BEFORE: GRID_BEFORE,
        GRID_COLUMNS: GRID_COLUMNS,
        WEATHER_TTL_MS: WEATHER_TTL_MS,
        HOUR_MS: HOUR_MS,
        PEAK_WINDOWS: PEAK_WINDOWS,
        clockText: clockText,
        dayDelta: dayDelta,
        dayDeltaText: dayDeltaText,
        earliestTransition: earliestTransition,
        forecastUrl: forecastUrl,
        grid: grid,
        gridInstants: gridInstants,
        gridRow: gridRow,
        homeZone: homeZone,
        hourOf: hourOf,
        hourText: hourText,
        isBusinessHour: isBusinessHour,
        isPeakInstant: isPeakInstant,
        labelFor: labelFor,
        parseForecast: parseForecast,
        parseRows: parseRows,
        relativeText: relativeText,
        tempText: tempText,
        tooltipText: tooltipText,
        wallClock: wallClock,
        weatherStale: weatherStale,
        zoneTabCoords: zoneTabCoords
    };
}

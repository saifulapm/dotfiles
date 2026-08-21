// Night-light model — everything the nightlight widget and panel know about
// sunsetr's state, as pure functions so they can be checked under node
// (NightLightModel.test.js) without a Quickshell runtime.
//
// The input is sunsetr's `status --json --follow` stream. Two shapes arrive
// on it, both as ONE COMPACT OBJECT PER LINE (verified against 0.12.5 —
// note that the one-shot `status --json` is pretty-printed instead, which is
// why nothing here may assume a whole document per read):
//
//   {"event_type":"state_applied","active_preset":"default","period":"night",
//    "state":"stable","current_temp":3300,"current_gamma":90.0,
//    "next_period":"2026-08-22T05:28:48.000594403+06:00"}
//   {"event_type":"config_changed","target_period":"night",
//    "target_temp":3000,"target_gamma":90.0}
//
// A forced preset drops next_period entirely and reports period/state as
// "static" — there is no next transition when the schedule is suspended.
//
// The one-shot form carries no event_type at all, so parseEvent treats a
// missing one as state_applied: the panel's probe-on-open and the follower
// then land in the same place.

// sunsetr's spelling of "no override is pinned".
var NO_PRESET = "default";

// Upstream's own default day point, and the fallback when `sunsetr get
// day_temp` has not answered yet. Everything warmer than this counts as
// filtered; 6500 K is the neutral daylight point, not a preference.
var DEFAULT_DAY_TEMP = 6500;

function parseJson(raw) {
    var text = String(raw || "").trim();
    if (!text)
        return null;
    try {
        var value = JSON.parse(text);
        return value && typeof value === "object" ? value : null;
    } catch (error) {
        return null;
    }
}

// One follower line -> a normalized event, or null for anything unrecognized
// (sunsetr prints its box-drawing banner to stderr, not here, but a future
// event type must not be mistaken for a state).
function parseEvent(raw) {
    var value = parseJson(raw);
    if (!value)
        return null;

    // The one-shot `status --json` has no event_type; the follower always
    // does. Treating the absence as a state means one code path for both.
    var kind = String(value.event_type || "state_applied");
    if (kind === "state_applied") {
        return {
            kind: "state",
            preset: String(value.active_preset || NO_PRESET),
            period: String(value.period || ""),
            phase: String(value.state || ""),
            temp: Number(value.current_temp) || 0,
            gamma: Number(value.current_gamma) || 0,
            nextPeriod: String(value.next_period || "")
        };
    }
    if (kind === "config_changed") {
        return {
            kind: "config",
            period: String(value.target_period || ""),
            temp: Number(value.target_temp) || 0,
            gamma: Number(value.target_gamma) || 0
        };
    }
    return null;
}

// Which override is pinned: "" when the schedule is in charge.
function forcedPreset(state) {
    var preset = String((state && state.preset) || NO_PRESET);
    return preset === NO_PRESET ? "" : preset;
}

function isForced(state) {
    return forcedPreset(state) !== "";
}

// Whether the glass is actually warmed right now, whatever the reason.
//
// This asks the TEMPERATURE, never the period, and that is the whole point:
// during a transition sunsetr flips `period` to "night" while the display is
// still most of the way to neutral, so a period-driven icon would light up
// forty minutes before the screen looked any different. The temperature is
// what the eye sees.
function isWarm(state, dayTemp) {
    var temp = Number((state && state.temp) || 0);
    var neutral = Number(dayTemp) || DEFAULT_DAY_TEMP;
    return temp > 0 && temp < neutral;
}

// Mid-fade. sunsetr reports "stable" or "static" when it has settled.
function isTransitioning(state) {
    var phase = String((state && state.phase) || "");
    return phase !== "" && phase !== "stable" && phase !== "static";
}

// What one press of the toggle would do, so the tooltip and the panel hint
// can say it before it happens. Mirrors bin/nightlight's `toggle` exactly —
// if this and that script ever disagree, the script is right.
function toggleTarget(state, dayTemp) {
    if (isForced(state))
        return "auto";
    return isWarm(state, dayTemp) ? "day" : "night";
}

function toggleLabel(state, dayTemp) {
    switch (toggleTarget(state, dayTemp)) {
    case "auto":
        return "Back to the schedule";
    case "day":
        return "Hold neutral";
    default:
        return "Hold warm";
    }
}

// JS Date.parse chokes on nothing here except the precision: sunsetr emits
// nanoseconds ("…:48.000594403+06:00") and the spec only defines
// milliseconds. Truncate rather than round — the value is a wall-clock
// boundary rendered to the minute, so sub-millisecond accuracy is noise.
function parseTimestamp(value) {
    var text = String(value || "");
    if (!text)
        return null;
    var trimmed = text.replace(/(\.\d{3})\d+/, "$1");
    var stamp = new Date(trimmed);
    return isFinite(stamp.getTime()) ? stamp : null;
}

function padTwo(value) {
    return (value < 10 ? "0" : "") + value;
}

function clockText(stamp) {
    if (!stamp)
        return "";
    return padTwo(stamp.getHours()) + ":" + padTwo(stamp.getMinutes());
}

// "Warms at 18:28" / "Neutral at 05:28" / "" — the sentence under the hero.
// A forced preset has no next transition at all, which is the honest answer:
// the schedule is suspended until it is released.
function nextTransitionText(state, dayTemp) {
    if (isForced(state))
        return "";
    var stamp = parseTimestamp(state && state.nextPeriod);
    if (!stamp)
        return "";
    // The next boundary undoes whatever is happening now.
    return (isWarm(state, dayTemp) ? "Neutral at " : "Warms at ") + clockText(stamp);
}

// A playful name for a colour temperature, in the shape of the monitor
// panel's brightness mood ladder. Bands are ~500-800 K so a preset change
// always renames it while a small `set` nudge inside one does not.
function moodName(temp) {
    var value = Number(temp) || 0;
    if (value <= 0)
        return "Off";
    if (value < 2200)
        return "Embers";
    if (value < 2800)
        return "Candlelight";
    if (value < 3400)
        return "Lamplight";
    if (value < 4200)
        return "Late evening";
    if (value < 5000)
        return "Long afternoon";
    if (value < 5800)
        return "Overcast";
    if (value < 6400)
        return "Almost neutral";
    return "Daylight";
}

function kelvinText(temp) {
    var value = Number(temp) || 0;
    return value > 0 ? value + "K" : "—";
}

// The bar tooltip: state first, then why.
function tooltipText(state, dayTemp, running) {
    if (!running)
        return "Night light — off";
    var preset = forcedPreset(state);
    var temp = kelvinText(state && state.temp);
    if (preset === "day")
        return "Night light — held neutral (" + temp + ")";
    if (preset === "night")
        return "Night light — held warm (" + temp + ")";
    var next = nextTransitionText(state, dayTemp);
    var head = isWarm(state, dayTemp) ? "Night light — on (" + temp + ")" : "Night light — off until sunset (" + temp + ")";
    return next ? head + ", " + next.charAt(0).toLowerCase() + next.slice(1) : head;
}

// The panel hero's second line.
function heroMeta(state, dayTemp, running) {
    if (!running)
        return "sunsetr is not running";
    var parts = [moodName(state && state.temp), kelvinText(state && state.temp)];
    var gamma = Number((state && state.gamma) || 0);
    if (gamma > 0 && gamma !== 100)
        parts.push(gamma + "% gamma");
    return parts.join(" · ");
}

// The three rows the panel draws, and what `nightlight <verb>` each runs.
// `key` doubles as the preset name, except for auto, which sunsetr spells
// "default" — apply() in the service does that translation once.
var MODES = [{
    key: "auto",
    label: "Auto",
    glyph: "󰑐", // md-autorenew
    detail: "Follow sunrise and sunset"
}, {
    key: "day",
    label: "Day",
    glyph: "󰖙", // md-white_balance_sunny
    detail: "Hold the display neutral"
}, {
    key: "night",
    label: "Night",
    glyph: "󰖔", // md-weather_night
    detail: "Hold the filter on"
}];

function activeModeKey(state) {
    var preset = forcedPreset(state);
    return preset === "" ? "auto" : preset;
}

if (typeof module !== "undefined") {
    module.exports = {
        DEFAULT_DAY_TEMP: DEFAULT_DAY_TEMP,
        MODES: MODES,
        NO_PRESET: NO_PRESET,
        activeModeKey: activeModeKey,
        clockText: clockText,
        forcedPreset: forcedPreset,
        heroMeta: heroMeta,
        isForced: isForced,
        isTransitioning: isTransitioning,
        isWarm: isWarm,
        kelvinText: kelvinText,
        moodName: moodName,
        nextTransitionText: nextTransitionText,
        parseEvent: parseEvent,
        parseJson: parseJson,
        parseTimestamp: parseTimestamp,
        toggleLabel: toggleLabel,
        toggleTarget: toggleTarget,
        tooltipText: tooltipText
    };
}

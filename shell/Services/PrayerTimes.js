.pragma library

// The one answer to "what time is Fajr HERE", shared by the bar and the hub.
//
// A calculated time and a masjid's jamaat time are different things, and the
// second is the one you actually pray. aladhan gives the first; this applies
// whatever the config says on top of it — a fixed time per prayer, or an offset
// in minutes — so the bar's countdown, its notifications and the hub's home
// page all say the same thing.
//
// It lives in Services and not in either module because two implementations of
// this would drift, and the failure would be silent: a widget saying Asr is at
// 16:27 while the page behind it says 16:45, with no way to tell which one the
// notification used.
//
// Config (shell.json, root `prayer` block):
//
//   "prayer": {
//     "latitude": 23.8103, "longitude": 90.4125, "method": 1, "school": 1,
//     "jamaat":  { "Fajr": "05:15", "Isha": "20:00" },
//     "offsets": { "Dhuhr": 5 }
//   }
//
// `jamaat` is a clock time and wins outright. `offsets` are minutes added to
// the calculated time, for a masjid that prays a fixed few minutes after the
// adhan. A prayer named in neither is calculated, as before.

var PRAYERS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"];
// Sunrise is not a prayer. It is when Fajr ends, so anything drawing the shape
// of the day needs it, and nothing scheduling a prayer does.
var DAY = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"];

/// "16:27 (+06)" → 987. The zone suffix is aladhan's and says nothing the
/// clock does not.
function minutesOf(text) {
    var m = String(text || "").match(/^\s*(\d{1,2}):(\d{2})/);
    return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
}

/// "16:27 (+06)" → "16:27".
function clock(text) {
    var m = String(text || "").match(/^\s*(\d{1,2}:\d{2})/);
    return m ? m[1] : "";
}

function pad(mins) {
    var m = ((mins % 1440) + 1440) % 1440; // a −20 offset on Fajr is 23:xx
    var h = Math.floor(m / 60);
    var r = m % 60;
    return (h < 10 ? "0" : "") + h + ":" + (r < 10 ? "0" : "") + r;
}

function jamaatOf(config) {
    return (config && config.jamaat && typeof config.jamaat === "object") ? config.jamaat : {};
}

function offsetsOf(config) {
    return (config && config.offsets && typeof config.offsets === "object") ? config.offsets : {};
}

/// Whether this prayer's time came from the config rather than the calculation.
/// The UI says so where it can: a time you did not calculate should not look
/// like one you did.
function overridden(name, config) {
    var fixed = jamaatOf(config)[name];
    if (typeof fixed === "string" && clock(fixed) !== "")
        return true;
    return Number(offsetsOf(config)[name] || 0) !== 0;
}

function anyOverride(config) {
    for (var i = 0; i < DAY.length; i++) {
        if (overridden(DAY[i], config))
            return true;
    }
    return false;
}

/// One day's raw aladhan timings, with the masjid config applied.
/// Answers "HH:MM" per name, or "" where there was nothing to work from.
function effective(timings, config) {
    var jamaat = jamaatOf(config);
    var offsets = offsetsOf(config);
    var out = {};
    for (var i = 0; i < DAY.length; i++) {
        var name = DAY[i];
        var fixed = jamaat[name];
        if (typeof fixed === "string" && clock(fixed) !== "") {
            out[name] = clock(fixed);
            continue;
        }
        var base = minutesOf(timings ? timings[name] : "");
        if (base < 0) {
            out[name] = "";
            continue;
        }
        var shift = Number(offsets[name]);
        out[name] = pad(base + (isFinite(shift) ? shift : 0));
    }
    return out;
}

// Dictation model — the parsing, searching, bucketing and prose behind the
// dictation panel, as pure functions so they can be checked under node
// (DictationModel.test.js) without a Quickshell runtime.
//
// Two inputs, both written by bin/voxtype-capture:
//
//   dictation.jsonl       one JSON object per finished dictation, oldest first
//   dictation-days.json   { "YYYY-MM-DD": { takes, secs, words } }
//
// and one more from voxtype itself: `info accel --json`, which is the only
// honest answer to "is this actually accelerated" — the config says what was
// asked for, that says what happened.

// Days drawn in the chart. Fourteen is two weeks of habit, which is the
// shortest window where "I dictate on weekdays" is visible at all.
var CHART_DAYS = 14;

// ------------------------------------------------------------------ history

function parseHistory(raw) {
    // Newest first, because the panel is read top-down and the thing you want
    // is almost always the dictation that just went to the wrong window.
    var rows = [];
    var lines = String(raw || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line === "")
            continue;
        try {
            var row = JSON.parse(line);
        } catch (e) {
            // A torn line is one lost transcript, not a broken panel. The
            // writer replaces the file atomically so this should not happen;
            // skipping is the cheap insurance that it cannot matter.
            continue;
        }
        if (row && typeof row.id === "number")
            rows.push(row);
    }
    return rows.reverse();
}

function matches(row, query) {
    var q = String(query || "").trim().toLowerCase();
    if (q === "")
        return true;
    if (!row)
        return false;
    // Text and destination only. Searching the timestamp would make "2026"
    // match everything, which is worse than not matching it at all.
    return String(row.text || "").toLowerCase().indexOf(q) !== -1
        || String(row.app || "").toLowerCase().indexOf(q) !== -1;
}

function pinnedFirst(rows, pins) {
    // A stable partition, not a sort: within each half the newest-first order
    // from parseHistory is the order that matters.
    var keep = pins || [];
    var isPinned = function (row) {
        return keep.indexOf(row.id) !== -1;
    };
    return rows.filter(isPinned).concat(rows.filter(function (row) {
        return !isPinned(row);
    }));
}

// ----------------------------------------------------------------- duration

function durationText(secs) {
    // null is "not known" (a dictation started outside bin/voxtype-toggle, so
    // nothing stamped it) and must not render as 0.0s.
    if (secs === null || secs === undefined || isNaN(secs))
        return "";
    var n = Number(secs);
    if (n < 60)
        return n.toFixed(1) + "s";
    var mins = Math.floor(n / 60);
    var rest = Math.round(n - mins * 60);
    // 59.6s rounding to 60 would print "1m 60s".
    if (rest === 60) {
        mins += 1;
        rest = 0;
    }
    return mins + "m " + (rest < 10 ? "0" : "") + rest + "s";
}

function talkTimeText(secs) {
    // The headline number, so it rounds to whole units: nobody cares that
    // yesterday was 12.4 minutes.
    var n = Number(secs || 0);
    if (n < 60)
        return Math.round(n) + "s";
    if (n < 3600)
        return Math.round(n / 60) + " min";
    var hours = n / 3600;
    return (hours < 10 ? hours.toFixed(1) : String(Math.round(hours))) + " hr";
}

// -------------------------------------------------------------------- dates

function isoDay(date) {
    var m = date.getMonth() + 1;
    var d = date.getDate();
    return date.getFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (d < 10 ? "0" : "") + d;
}

function relativeAt(iso, now) {
    var then = new Date(iso);
    if (isNaN(then.getTime()))
        return "";
    var ref = now || new Date();
    var mins = Math.floor((ref.getTime() - then.getTime()) / 60000);
    if (mins < 1)
        return "just now";
    if (mins < 60)
        return mins + "m ago";
    var clock = ("0" + then.getHours()).slice(-2) + ":" + ("0" + then.getMinutes()).slice(-2);
    if (isoDay(then) === isoDay(ref))
        return clock;
    var yesterday = new Date(ref.getTime());
    yesterday.setDate(yesterday.getDate() - 1);
    if (isoDay(then) === isoDay(yesterday))
        return "yesterday " + clock;
    // Past that a date is more use than a count of days.
    return isoDay(then).slice(5) + " " + clock;
}

// -------------------------------------------------------------------- chart

function dayBars(days, now, count) {
    // Every day in the window, including the ones with nothing — a chart that
    // skipped empty days would compress a fortnight of not dictating into
    // yesterday, which is the opposite of what it is for.
    var span = count || CHART_DAYS;
    var table = days || {};
    var ref = now || new Date();
    var bars = [];
    var max = 0;

    for (var i = span - 1; i >= 0; i--) {
        var day = new Date(ref.getTime());
        day.setDate(day.getDate() - i);
        var key = isoDay(day);
        var entry = table[key] || {};
        var secs = Number(entry.secs || 0);
        if (secs > max)
            max = secs;
        bars.push({
            date: key,
            // Single letter, because fourteen three-letter labels do not fit
            // a bar panel and the shape is what is being read anyway.
            label: "SMTWTFS".charAt(day.getDay()),
            secs: secs,
            words: Number(entry.words || 0),
            takes: Number(entry.takes || 0),
            today: i === 0,
            ratio: 0
        });
    }

    for (var j = 0; j < bars.length; j++)
        bars[j].ratio = max > 0 ? bars[j].secs / max : 0;

    return bars;
}

function chartTotals(bars) {
    var secs = 0;
    var words = 0;
    var takes = 0;
    var active = 0;
    for (var i = 0; i < bars.length; i++) {
        secs += bars[i].secs;
        words += bars[i].words;
        takes += bars[i].takes;
        if (bars[i].takes > 0)
            active += 1;
    }
    return {
        secs: secs,
        words: words,
        takes: takes,
        active: active,
        // Words per minute of speech, over the whole window rather than per
        // day: a single 4-second take would otherwise set a wild rate.
        wpm: secs > 0 ? Math.round(words / (secs / 60)) : 0
    };
}

function plural(n, one, many) {
    return n + " " + (n === 1 ? one : many);
}

function summaryText(totals) {
    if (!totals || totals.takes === 0)
        return "Nothing dictated in the last two weeks.";
    return plural(totals.takes, "dictation", "dictations")
        + " across " + plural(totals.active, "day", "days")
        + ", " + plural(totals.words, "word", "words")
        + " at " + totals.wpm + " wpm";
}

function destinationTotals(rows) {
    var counts = {};
    for (var i = 0; i < rows.length; i++) {
        // A dropped silence hallucination went nowhere, so it belongs in no
        // destination. Counting it would put a phantom tally against whatever
        // window happened to be focused when the key was bumped.
        if (rows[i].dropped)
            continue;
        var name = rows[i].dest || "Other";
        counts[name] = (counts[name] || 0) + 1;
    }
    var out = [];
    for (var key in counts)
        out.push({ name: key, count: counts[key] });
    // Biggest first, name as the tiebreak so the order is stable between
    // refreshes rather than following object key order.
    out.sort(function (a, b) {
        return b.count - a.count || (a.name < b.name ? -1 : 1);
    });
    return out;
}

// -------------------------------------------------------------------- state

function heroMeta(state, unitActive) {
    switch (state) {
    case "recording":
        return "Listening";
    case "transcribing":
        return "Transcribing";
    case "idle":
        return "Ready";
    default:
        // "stopped" and anything unrecognised. The daemon being down is the
        // normal resting state here, not a fault, so it reads as a fact.
        return unitActive ? "Starting" : "Daemon stopped";
    }
}

function accelBadge(accel, gpuPresent) {
    // From `voxtype info accel --json`. The state that matters is
    // cpu-fallback: acceleration was asked for and did not happen. "unknown"
    // and "not-running" draw nothing rather than guessing.
    //
    // ...except that upstream reports cpu-fallback on a machine with no GPU at
    // all, which is where every aarch64 install lands (upstream ships CPU-only
    // arm64 binaries and says so). There is nothing to fall back FROM there, so
    // `gpuPresent: false` demotes the warning to a plain statement of fact.
    // Passing gpuPresent as undefined leaves the warning intact, because "we
    // could not tell" must not silence a real fallback.
    if (!accel || !accel.state)
        return null;
    switch (accel.state) {
    case "gpu":
        return { text: accel.backend ? "GPU · " + accel.backend : "GPU", urgent: false };
    case "cpu-fallback":
        return gpuPresent === false
            ? { text: "CPU", urgent: false }
            : { text: "CPU fallback", urgent: true };
    case "cpu":
        return { text: "CPU", urgent: false };
    default:
        return null;
    }
}

function factsLine(facts) {
    // Every item measured; a reading we could not take is left out rather than
    // guessed, so a missing item means "not known" and never "zero".
    var parts = [];
    if (facts.engine)
        parts.push(facts.engine);
    if (facts.model)
        parts.push(facts.model);
    if (facts.language)
        parts.push(facts.language);
    if (facts.unitState)
        parts.push("unit " + facts.unitState);
    if (facts.rssMb > 0)
        parts.push(facts.rssMb + " MB");
    return parts.join(" · ");
}

if (typeof module !== "undefined") {
    module.exports = {
        CHART_DAYS: CHART_DAYS,
        accelBadge: accelBadge,
        chartTotals: chartTotals,
        dayBars: dayBars,
        destinationTotals: destinationTotals,
        durationText: durationText,
        factsLine: factsLine,
        heroMeta: heroMeta,
        isoDay: isoDay,
        matches: matches,
        parseHistory: parseHistory,
        pinnedFirst: pinnedFirst,
        relativeAt: relativeAt,
        summaryText: summaryText,
        talkTimeText: talkTimeText
    };
}

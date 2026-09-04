// Unit tests for DictationModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/DictationModel.test.js
//
// The fixture is real bin/voxtype-capture output shape, with one deliberately
// torn line and one take with `secs: null` — the record a dictation started
// outside bin/voxtype-toggle produces, where "not known" must not render as
// zero anywhere.

const assert = require("node:assert/strict");
const Model = require("./DictationModel.js");

let failures = 0;
function test(name, fn) {
    try {
        fn();
        console.log(`  ok  ${name}`);
    } catch (error) {
        failures += 1;
        console.log(`FAIL  ${name}\n      ${error.message}`);
    }
}

const row = (id, at, secs, words, app, dest, text) =>
    JSON.stringify({ id, at, secs, words, chars: text.length, app, dest, text });

const JSONL = [
    row(1000, "2026-09-02T09:00:00+06:00", 4.2, 12, "chromium", "Browser", "the first thing I said"),
    row(1001, "2026-09-03T10:30:00+06:00", 61.5, 180, "foot", "Terminal", "a long one about PostgreSQL"),
    "{ this line is torn",
    "",
    row(1002, "2026-09-04T11:00:00+06:00", null, 5, "", "Other", "no stamp for this take"),
    row(1003, "2026-09-04T11:05:00+06:00", 8.0, 20, "emacs", "Editor", "notes about the shell")
].join("\n");

// ------------------------------------------------------------ parseHistory

test("parseHistory returns newest first and skips torn lines", () => {
    const rows = Model.parseHistory(JSONL);
    assert.equal(rows.length, 4);
    assert.deepEqual(rows.map(r => r.id), [1003, 1002, 1001, 1000]);
});

test("parseHistory tolerates empty and absent input", () => {
    assert.deepEqual(Model.parseHistory(""), []);
    assert.deepEqual(Model.parseHistory(null), []);
    assert.deepEqual(Model.parseHistory("not json at all"), []);
});

test("parseHistory drops objects with no id", () => {
    assert.deepEqual(Model.parseHistory('{"text":"orphan"}'), []);
});

// ------------------------------------------------------------------ matches

test("matches searches text and destination app, case-insensitively", () => {
    const rows = Model.parseHistory(JSONL);
    const find = q => rows.filter(r => Model.matches(r, q)).map(r => r.id);
    assert.deepEqual(find("postgresql"), [1001]);
    assert.deepEqual(find("EMACS"), [1003]);
    assert.deepEqual(find(""), [1003, 1002, 1001, 1000]);
    assert.deepEqual(find("   "), [1003, 1002, 1001, 1000]);
    assert.deepEqual(find("nothing here"), []);
});

test("matches does not search the timestamp", () => {
    const rows = Model.parseHistory(JSONL);
    assert.deepEqual(rows.filter(r => Model.matches(r, "2026")).map(r => r.id), []);
});

// -------------------------------------------------------------- pinnedFirst

test("pinnedFirst floats pins without disturbing newest-first inside each half", () => {
    const rows = Model.parseHistory(JSONL);
    assert.deepEqual(Model.pinnedFirst(rows, [1000, 1002]).map(r => r.id), [1002, 1000, 1003, 1001]);
    assert.deepEqual(Model.pinnedFirst(rows, []).map(r => r.id), [1003, 1002, 1001, 1000]);
});

// ------------------------------------------------------------- durationText

test("durationText renders seconds under a minute and m/s above", () => {
    assert.equal(Model.durationText(4.2), "4.2s");
    assert.equal(Model.durationText(0), "0.0s");
    assert.equal(Model.durationText(61.5), "1m 02s");
    assert.equal(Model.durationText(125), "2m 05s");
});

test("durationText never prints sixty seconds", () => {
    // 59.6 rounds to 60 in the naive form, which would read "0m 60s".
    assert.equal(Model.durationText(119.6), "2m 00s");
});

test("durationText renders an unknown duration as nothing, never as zero", () => {
    assert.equal(Model.durationText(null), "");
    assert.equal(Model.durationText(undefined), "");
    assert.equal(Model.durationText(NaN), "");
});

// ------------------------------------------------------------ talkTimeText

test("talkTimeText rounds to whole units", () => {
    assert.equal(Model.talkTimeText(42.4), "42s");
    assert.equal(Model.talkTimeText(745), "12 min");
    assert.equal(Model.talkTimeText(5400), "1.5 hr");
    assert.equal(Model.talkTimeText(0), "0s");
    assert.equal(Model.talkTimeText(undefined), "0s");
});

// ------------------------------------------------------------------ dayBars

const NOW = new Date("2026-09-04T12:00:00+06:00");
const DAYS = {
    "2026-09-02": { takes: 1, secs: 4.2, words: 12 },
    "2026-09-03": { takes: 1, secs: 61.5, words: 180 },
    "2026-09-04": { takes: 2, secs: 8.0, words: 25 },
    // Outside the 14-day window: present in the store, absent from the chart.
    "2026-07-01": { takes: 9, secs: 900, words: 2000 }
};

test("dayBars spans exactly the window and ends on today", () => {
    const bars = Model.dayBars(DAYS, NOW);
    assert.equal(bars.length, Model.CHART_DAYS);
    assert.equal(bars[bars.length - 1].date, "2026-09-04");
    assert.equal(bars[bars.length - 1].today, true);
    assert.equal(bars[0].date, "2026-08-22");
});

test("dayBars keeps empty days as empty rather than dropping them", () => {
    const bars = Model.dayBars(DAYS, NOW);
    const quiet = bars.filter(b => b.takes === 0);
    assert.equal(quiet.length, Model.CHART_DAYS - 3);
    assert.equal(quiet.every(b => b.secs === 0 && b.ratio === 0), true);
});

test("dayBars ignores days outside the window", () => {
    const bars = Model.dayBars(DAYS, NOW);
    assert.equal(bars.some(b => b.date === "2026-07-01"), false);
    // The out-of-window 900s day must not become the scale for the chart.
    assert.equal(Math.max(...bars.map(b => b.ratio)), 1);
});

test("dayBars scales ratios against the tallest day in the window", () => {
    const bars = Model.dayBars(DAYS, NOW);
    const byDate = Object.fromEntries(bars.map(b => [b.date, b]));
    assert.equal(byDate["2026-09-03"].ratio, 1);
    assert.equal(Math.round(byDate["2026-09-02"].ratio * 1000) / 1000, 0.068);
});

test("dayBars over an empty store is flat, not divided by zero", () => {
    const bars = Model.dayBars({}, NOW);
    assert.equal(bars.length, Model.CHART_DAYS);
    assert.equal(bars.every(b => b.ratio === 0), true);
});

test("dayBars labels each day with its weekday initial", () => {
    // 2026-09-04 is a Friday.
    const bars = Model.dayBars(DAYS, NOW);
    assert.equal(bars[bars.length - 1].label, "F");
});

// -------------------------------------------------------------- chartTotals

test("chartTotals sums the window and derives words per minute of speech", () => {
    const totals = Model.chartTotals(Model.dayBars(DAYS, NOW));
    assert.equal(totals.takes, 4);
    assert.equal(Math.round(totals.secs * 10) / 10, 73.7);
    assert.equal(totals.words, 217);
    assert.equal(totals.active, 3);
    assert.equal(totals.wpm, Math.round(217 / (73.7 / 60)));
});

test("chartTotals over an empty window reports zero, not NaN", () => {
    const totals = Model.chartTotals(Model.dayBars({}, NOW));
    assert.deepEqual(totals, { secs: 0, words: 0, takes: 0, active: 0, wpm: 0 });
});

// --------------------------------------------------------------- summaryText

test("summaryText says nothing happened when nothing happened", () => {
    assert.equal(Model.summaryText(Model.chartTotals(Model.dayBars({}, NOW))),
        "Nothing dictated in the last two weeks.");
    assert.equal(Model.summaryText(null), "Nothing dictated in the last two weeks.");
});

test("summaryText counts in the singular when there is one of a thing", () => {
    // The first dictation of a fresh install reads "1 dictations across 1 day"
    // without this, which is the sentence a panel gets judged on.
    assert.equal(
        Model.summaryText({ takes: 1, active: 1, words: 1, wpm: 4 }),
        "1 dictation across 1 day, 1 word at 4 wpm");
    assert.equal(
        Model.summaryText({ takes: 12, active: 3, words: 400, wpm: 121 }),
        "12 dictations across 3 days, 400 words at 121 wpm");
});

// --------------------------------------------------------- destinationTotals

test("destinationTotals ranks by count with a stable name tiebreak", () => {
    const rows = Model.parseHistory(JSONL).concat(Model.parseHistory(JSONL));
    const totals = Model.destinationTotals(rows);
    assert.deepEqual(totals, [
        { name: "Browser", count: 2 },
        { name: "Editor", count: 2 },
        { name: "Other", count: 2 },
        { name: "Terminal", count: 2 }
    ]);
});

test("destinationTotals treats a missing bucket as Other", () => {
    assert.deepEqual(Model.destinationTotals([{ id: 1 }]), [{ name: "Other", count: 1 }]);
});

test("destinationTotals ignores dropped hallucinations", () => {
    // A dropped transcript went nowhere, so it belongs to no destination.
    assert.deepEqual(Model.destinationTotals([
        { id: 1, dest: "Editor" },
        { id: 2, dest: "Editor", dropped: true }
    ]), [{ name: "Editor", count: 1 }]);
    assert.deepEqual(Model.destinationTotals([{ id: 1, dest: "Editor", dropped: true }]), []);
});

// ----------------------------------------------------------------- relative

test("relativeAt reads as minutes, then a clock, then a date", () => {
    assert.equal(Model.relativeAt("2026-09-04T11:59:30+06:00", NOW), "just now");
    assert.equal(Model.relativeAt("2026-09-04T11:30:00+06:00", NOW), "30m ago");
    assert.equal(Model.relativeAt("2026-09-04T06:05:00+06:00", NOW), "06:05");
    assert.equal(Model.relativeAt("2026-09-03T14:03:00+06:00", NOW), "yesterday 14:03");
    assert.equal(Model.relativeAt("2026-08-30T09:00:00+06:00", NOW), "08-30 09:00");
});

test("relativeAt says nothing about an unparseable timestamp", () => {
    assert.equal(Model.relativeAt("not a date", NOW), "");
});

// --------------------------------------------------------------- state prose

test("heroMeta names each daemon state", () => {
    assert.equal(Model.heroMeta("recording"), "Listening");
    assert.equal(Model.heroMeta("transcribing"), "Transcribing");
    assert.equal(Model.heroMeta("idle"), "Ready");
    assert.equal(Model.heroMeta("stopped", false), "Daemon stopped");
});

test("heroMeta distinguishes a starting daemon from a stopped one", () => {
    // The unit is active but no state file has appeared yet: the model is
    // still loading, which is not the same as nothing running.
    assert.equal(Model.heroMeta("stopped", true), "Starting");
});

test("accelBadge shouts only about a fallback", () => {
    assert.deepEqual(Model.accelBadge({ state: "cpu-fallback" }, true), { text: "CPU fallback", urgent: true });
    assert.deepEqual(Model.accelBadge({ state: "cpu" }), { text: "CPU", urgent: false });
    assert.deepEqual(Model.accelBadge({ state: "gpu", backend: "MIGraphX" }), { text: "GPU · MIGraphX", urgent: false });
});

test("accelBadge does not cry fallback on a machine with no GPU", () => {
    // What every aarch64 install reports: upstream ships CPU-only arm64
    // binaries, and `info accel` still calls that cpu-fallback.
    assert.deepEqual(Model.accelBadge({ state: "cpu-fallback" }, false), { text: "CPU", urgent: false });
    // But "we could not tell whether there is a GPU" must not silence it.
    assert.deepEqual(Model.accelBadge({ state: "cpu-fallback" }, null), { text: "CPU fallback", urgent: true });
    assert.deepEqual(Model.accelBadge({ state: "cpu-fallback" }), { text: "CPU fallback", urgent: true });
});

test("accelBadge draws nothing rather than guessing", () => {
    assert.equal(Model.accelBadge({ state: "not-running" }), null);
    assert.equal(Model.accelBadge({ state: "unknown" }), null);
    assert.equal(Model.accelBadge(null), null);
});

test("factsLine leaves out what could not be measured", () => {
    assert.equal(
        Model.factsLine({ engine: "whisper", model: "small.en", language: "en", unitState: "active", rssMb: 486 }),
        "whisper · small.en · en · unit active · 486 MB");
    // No RSS reading and no language: fewer items, never a zero or a blank slot.
    assert.equal(Model.factsLine({ engine: "whisper", model: "small.en", rssMb: 0 }), "whisper · small.en");
    assert.equal(Model.factsLine({}), "");
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

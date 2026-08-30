// Unit tests for TimezonesModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/TimezonesModel.test.js
//
// The fixture is real `bin/timezone-offsets` output from 2026-08-21,
// including the two facts that shaped the script: a DST zone reports the
// instant its offset next changes, and a zone with no DST reports 0 rather
// than zdump's end-of-time sentinel.
//
// Every assertion here is timezone-independent — the model does its own
// offset arithmetic and never reads a local getter, so these pass wherever
// they are run. That is worth stating because it is also the property the
// production code depends on.

const assert = require("node:assert/strict");
const Model = require("./TimezonesModel.js");

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

// ------------------------------------------------- real bin/timezone-offsets

const TSV = [
    "America/New_York\t-14400\tEDT\t1793512799",
    "Europe/London\t3600\tBST\t1792889999",
    "Asia/Dhaka\t21600\t+06\t0",
    "Asia/Kathmandu\t20700\t+0545\t0"
].join("\n");

const zones = Model.parseRows(TSV);
const byName = name => zones.find(z => z.zone === name);
const dhaka = byName("Asia/Dhaka");
const newYork = byName("America/New_York");
const london = byName("Europe/London");
const kathmandu = byName("Asia/Kathmandu");

// 2026-08-21T12:00:00Z — a fixed instant, so every expectation below is exact.
const NOON_UTC = Date.UTC(2026, 7, 21, 12, 0, 0);

// ------------------------------------------------------------------ parsing

test("rows parse into zones with their order kept", () => {
    assert.equal(zones.length, 4);
    assert.equal(zones[0].zone, "America/New_York");
    assert.equal(zones[0].offset, -14400);
    assert.equal(zones[0].abbrev, "EDT");
    assert.equal(zones[0].order, 0);
});

test("a zone with no DST carries no transition", () => {
    assert.equal(dhaka.nextTransition, 0);
    assert.equal(newYork.nextTransition, 1793512799);
});

test("labels drop the tzdata area and the underscores", () => {
    assert.equal(Model.labelFor("America/New_York"), "New York");
    assert.equal(Model.labelFor("Asia/Dhaka"), "Dhaka");
    assert.equal(Model.labelFor("UTC"), "UTC");
    assert.equal(Model.labelFor("America/Argentina/Buenos_Aires"), "Buenos Aires");
});

// --------------------------------------------------------------- wall clocks

test("a zone's clock is computed, not formatted", () => {
    // 12:00 UTC is 08:00 in New York (UTC-4) and 18:00 in Dhaka (UTC+6).
    assert.equal(Model.clockText(newYork, NOON_UTC), "08:00");
    assert.equal(Model.clockText(dhaka, NOON_UTC), "18:00");
    assert.equal(Model.clockText(london, NOON_UTC), "13:00");
});

test("a half-hour zone is not rounded away", () => {
    // Kathmandu is UTC+5:45.
    assert.equal(Model.clockText(kathmandu, NOON_UTC), "17:45");
});

test("hours and minutes are zero-padded", () => {
    const earlyUtc = Date.UTC(2026, 7, 21, 3, 5, 0);
    assert.equal(Model.clockText(london, earlyUtc), "04:05");
});

// ------------------------------------------------------------- day boundaries

test("a zone on the previous day says so", () => {
    // 02:00 UTC on the 21st is 22:00 on the 20th in New York.
    const instant = Date.UTC(2026, 7, 21, 2, 0, 0);
    assert.equal(Model.clockText(newYork, instant), "22:00");
    assert.equal(Model.dayDelta(newYork, dhaka, instant), -1);
    assert.equal(Model.dayDeltaText(newYork, dhaka, instant), "Yesterday");
});

test("a zone on the next day says so", () => {
    // 20:00 UTC is 02:00 the following day in Dhaka.
    const instant = Date.UTC(2026, 7, 21, 20, 0, 0);
    assert.equal(Model.clockText(dhaka, instant), "02:00");
    assert.equal(Model.dayDelta(dhaka, newYork, instant), 1);
    assert.equal(Model.dayDeltaText(dhaka, newYork, instant), "Tomorrow");
});

test("same day is silent", () => {
    assert.equal(Model.dayDeltaText(london, dhaka, NOON_UTC), "");
    assert.equal(Model.dayDelta(dhaka, dhaka, NOON_UTC), 0);
});

// ------------------------------------------------------------ relative offset

test("the offset from home reads the way it is said", () => {
    assert.equal(Model.relativeText(dhaka, newYork), "+10h");
    assert.equal(Model.relativeText(newYork, dhaka), "−10h");
    assert.equal(Model.relativeText(dhaka, dhaka), "same time");
});

test("a 45-minute offset keeps its minutes", () => {
    // Kathmandu (+5:45) against Dhaka (+6:00) is fifteen minutes behind.
    assert.equal(Model.relativeText(kathmandu, dhaka), "−0h15");
    assert.equal(Model.relativeText(kathmandu, london), "+4h45");
});

// ------------------------------------------------------------------ the grid

test("every row is aligned on the same instants", () => {
    const rows = Model.grid(zones, dhaka, NOON_UTC);
    assert.equal(rows.length, 4);
    rows.forEach(row => assert.equal(row.cells.length, Model.GRID_COLUMNS));
    // The "now" column is the same index in every row, and each row reads
    // that one instant in its own zone.
    const nowIndex = Model.GRID_BEFORE;
    assert.equal(rows[0].cells[nowIndex].hour, 8, "New York");
    assert.equal(rows[1].cells[nowIndex].hour, 13, "London");
    assert.equal(rows[2].cells[nowIndex].hour, 18, "Dhaka");
    rows.forEach(row => assert.equal(row.cells[nowIndex].isNow, true));
});

test("columns advance by exactly one hour", () => {
    const instants = Model.gridInstants(dhaka, NOON_UTC);
    for (let i = 1; i < instants.length; i++)
        assert.equal(instants[i] - instants[i - 1], Model.HOUR_MS);
});

test("columns are truncated to the home zone's hour", () => {
    // A non-round instant must still produce whole hours in the home row.
    const messy = Date.UTC(2026, 7, 21, 12, 37, 42);
    const rows = Model.grid(zones, dhaka, messy);
    const dhakaRow = rows.find(r => r.zone.zone === "Asia/Dhaka");
    dhakaRow.cells.forEach(cell => assert.ok(Number.isInteger(cell.hour)));
    // 12:37 UTC is 18:37 in Dhaka, so the current column is the 18:00 one.
    assert.equal(dhakaRow.cells[Model.GRID_BEFORE].hour, 18);
});

test("a 45-minute zone still lands on whole hours in the grid", () => {
    // Kathmandu is offset from the column boundaries by 15 minutes; the hour
    // NUMBER it shows must still be an integer rather than a rounded mess.
    const rows = Model.grid(zones, dhaka, NOON_UTC);
    const row = rows.find(r => r.zone.zone === "Asia/Kathmandu");
    row.cells.forEach(cell => assert.ok(Number.isInteger(cell.hour)));
    assert.equal(row.cells[Model.GRID_BEFORE].hour, 17, "17:45 local reads as the 17 column");
});

test("business hours and midnight are flagged", () => {
    assert.equal(Model.isBusinessHour(9), true);
    assert.equal(Model.isBusinessHour(17), true);
    assert.equal(Model.isBusinessHour(18), false, "end is exclusive");
    assert.equal(Model.isBusinessHour(8), false);
    assert.equal(Model.isBusinessHour(0), false);

    const rows = Model.grid(zones, dhaka, NOON_UTC);
    const cells = rows[2].cells; // Dhaka, now 18:00
    assert.equal(cells.filter(c => c.dayStart).length <= 1, true, "at most one midnight in an 18-hour window");
    cells.forEach(cell => assert.equal(cell.dayStart, cell.hour === 0));
});

// ------------------------------------------------------------- peak windows

// Peak is 01:00–04:00 and 06:00–10:00 UTC, Monday through Friday. These dates
// are picked by weekday on purpose: 2026-08-21 is a Friday, the 22nd/23rd are
// the weekend, and the 24th is a Monday.
const peakAt = (day, hour, minute) => Model.isPeakInstant(Date.UTC(2026, 7, day, hour, minute || 0, 0));

test("the peak windows are inclusive at the start and exclusive at the end", () => {
    assert.equal(peakAt(21, 0, 59), false, "before the first window");
    assert.equal(peakAt(21, 1), true, "01:00 is peak");
    assert.equal(peakAt(21, 3, 59), true, "03:59 is still peak");
    assert.equal(peakAt(21, 4), false, "04:00 is already off-peak");
    assert.equal(peakAt(21, 5), false, "the gap between the windows");
    assert.equal(peakAt(21, 6), true, "06:00 is peak");
    assert.equal(peakAt(21, 9, 59), true, "09:59 is still peak");
    assert.equal(peakAt(21, 10), false, "10:00 is already off-peak");
    assert.equal(peakAt(21, 23), false, "the evening is off-peak");
});

test("the weekend is off-peak at every hour", () => {
    for (let hour = 0; hour < 24; hour++) {
        assert.equal(peakAt(22, hour), false, `Saturday ${hour}:00`);
        assert.equal(peakAt(23, hour), false, `Sunday ${hour}:00`);
    }
    assert.equal(peakAt(24, 2), true, "Monday 02:00 is back in the window");
});

test("peak is read in UTC, never in the local zone", () => {
    // 02:00 UTC on a Friday is peak whatever the machine's own offset is; the
    // guard is that the model never touches a local getter.
    const instant = Date.UTC(2026, 7, 21, 2, 0, 0);
    assert.equal(Model.isPeakInstant(instant), true);
    // 21:00 UTC Friday is 03:00 Saturday in Dhaka — still off-peak, because
    // peak is a property of the instant in UTC and not of any row's clock.
    assert.equal(Model.clockText(dhaka, Date.UTC(2026, 7, 21, 21, 0, 0)), "03:00");
    assert.equal(Model.isPeakInstant(Date.UTC(2026, 7, 21, 21, 0, 0)), false);
});

test("a grid column is peak or not for every row at once", () => {
    // 2026-08-21 (Friday) 02:00 UTC, with Dhaka home: the "now" column sits
    // inside the first peak window.
    const rows = Model.grid(zones, dhaka, Date.UTC(2026, 7, 21, 2, 0, 0));
    const nowIndex = Model.GRID_BEFORE;
    rows.forEach(row => assert.equal(row.cells[nowIndex].peak, true, row.zone.zone));
    // And every column carries the same flag down the grid, whatever each
    // row's own local hour reads.
    for (let i = 0; i < Model.GRID_COLUMNS; i++) {
        const expected = rows[0].cells[i].peak;
        rows.forEach(row => assert.equal(row.cells[i].peak, expected, `column ${i} in ${row.zone.zone}`));
    }
});

// --------------------------------------------------------------- home & DST

test("home is the system zone when it is in the list", () => {
    assert.equal(Model.homeZone(zones, "Asia/Dhaka").zone, "Asia/Dhaka");
});

test("home falls back to the first row when the system zone is absent", () => {
    assert.equal(Model.homeZone(zones, "Pacific/Auckland").zone, "America/New_York");
    assert.equal(Model.homeZone([], "Asia/Dhaka"), null);
});

test("the soonest transition is what the re-read is scheduled for", () => {
    // London (1792889999) is sooner than New York (1793512799); the two
    // zero-valued zones must not win by being smallest.
    assert.equal(Model.earliestTransition(zones), 1792889999);
    assert.equal(Model.earliestTransition([dhaka, kathmandu]), 0, "no DST anywhere");
    assert.equal(Model.earliestTransition([]), 0);
});

// -------------------------------------------------------------------- prose

test("the tooltip lists every zone, and names a date change", () => {
    const text = Model.tooltipText(zones, dhaka, NOON_UTC);
    const lines = text.split("\n");
    assert.equal(lines.length, 6, "four zones, a blank, then the peak state");
    assert.ok(lines[0].startsWith("New York  08:00"));
    assert.ok(lines[2].startsWith("Dhaka  18:00"));

    const late = Date.UTC(2026, 7, 21, 20, 0, 0);
    assert.ok(Model.tooltipText([dhaka], newYork, late)[0] !== undefined);
    assert.ok(Model.tooltipText([dhaka], newYork, late).includes("(tomorrow)"));
});

test("the tooltip says which state the mark's colour is showing", () => {
    // 12:00 UTC Friday is off-peak; 02:00 UTC the same day is not.
    assert.ok(Model.tooltipText(zones, dhaka, NOON_UTC).endsWith("Off-peak"));
    assert.ok(Model.tooltipText(zones, dhaka, Date.UTC(2026, 7, 21, 2, 0, 0)).endsWith("Peak hours"));
});

test("no zones is a sentence, not a crash", () => {
    assert.equal(Model.tooltipText([], null, NOON_UTC), "World clock — no zones configured");
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

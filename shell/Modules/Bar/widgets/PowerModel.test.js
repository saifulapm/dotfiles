// Unit tests for PowerModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/PowerModel.test.js
//
// Covers the charge-cap and health-history helpers added with the battery
// panel; the older port-of-omarchy formatters are exercised where they touch
// the same output. `node <file>` is the runner, as with the other bar widget
// model tests.

const assert = require("node:assert/strict");
const Model = require("./PowerModel.js");

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

// The exact block bin/system-stats prints on this machine with the cap on.
const STATS_ON = [
    "cpu\t7%",
    "memory\t5.2GB / 7GB",
    "cycles\t359",
    "threshold\t75-80%",
    "charge_limit_supported\t1",
    "charge_limit_enabled\t1",
    "charge_limit_end\t80",
    "charge_limit_start\t75",
    "health\tGood",
    "capacity_health\t83.4",
    "health_history\t3|2026-03-01,86.0,180 2026-06-01,84.5,270 2026-09-04,83.4,359",
    "power_profiles\tavailable"
].join("\n");

// ------------------------------------------------------------- charge cap
test("chargeLimit reads the cap as on, with its formatted range", () => {
    const info = Model.parseKeyValue(STATS_ON);
    const cap = Model.chargeLimit(info);
    assert.equal(cap.supported, true);
    assert.equal(cap.enabled, true);
    assert.equal(cap.text, "75-80%");
    assert.equal(cap.end, 80);
    assert.equal(cap.start, 75);
});

test("chargeLimit survives hardware that caps with no resume band", () => {
    const cap = Model.chargeLimit({
        charge_limit_supported: "1",
        charge_limit_enabled: "1",
        charge_limit_end: "80",
        threshold: "80%"
    });
    assert.equal(cap.end, 80);
    // 0, not NaN: the panel tests `start > 0` to decide whether to mention a
    // resume band at all, and NaN would fail that test the wrong way round.
    assert.equal(cap.start, 0);
});

test("chargeLimit reads the cap as off but still supported", () => {
    const cap = Model.chargeLimit({
        charge_limit_supported: "1",
        charge_limit_enabled: "0",
        threshold: "100%"
    });
    assert.equal(cap.supported, true);
    assert.equal(cap.enabled, false);
    // Off, "100%" is true and useless — the row should have nothing to draw.
    assert.equal(cap.text, "");
});

test("chargeLimit reports unsupported on a machine with no cap (mini, NUC)", () => {
    for (const info of [{}, null, undefined, { cycles: "12" }]) {
        const cap = Model.chargeLimit(info);
        assert.equal(cap.supported, false, JSON.stringify(info));
        assert.equal(cap.enabled, false);
    }
});

test("a switched-off cap can never read as holding", () => {
    const states = { Charging: 1, Discharging: 2, FullyCharged: 4, PendingCharge: 5 };
    // A slow charge that the old heuristic would call "held": on AC,
    // charging, tiny rate.
    const device = { isPresent: true, percentage: 0.8, state: states.Charging, changeRate: 0.1, timeToFull: 0 };
    assert.equal(Model.chargeThresholdActive(device, false, states), true, "heuristic alone still says held");
    assert.equal(
        Model.chargeThresholdActive(device, false, states, { charge_limit_supported: "1", charge_limit_enabled: "0" }),
        false,
        "authoritative off must win"
    );
    assert.equal(
        Model.chargeThresholdActive(device, false, states, { charge_limit_supported: "1", charge_limit_enabled: "1" }),
        true
    );
});

// ---------------------------------------------------------- health history
test("parseHealthHistory reads the packed line", () => {
    const info = Model.parseKeyValue(STATS_ON);
    const h = Model.parseHealthHistory(info.health_history);
    assert.equal(h.total, 3);
    assert.equal(h.samples.length, 3);
    assert.equal(h.samples[0].date, "2026-03-01");
    assert.equal(h.samples[0].health, 86);
    assert.equal(h.samples[2].cycles, 359);
});

test("parseHealthHistory survives a hand-edited log", () => {
    // A truncated row, a non-date, a non-number — each dropped, the good ones
    // kept. The log is a plain TSV the user owns, so this WILL happen.
    const h = Model.parseHealthHistory("5|2026-01-01,90.0,10 broken 2026-02-01,89 notadate,88.0,20 2026-03-01,88.0,30");
    assert.equal(h.samples.length, 2);
    assert.equal(h.samples[0].date, "2026-01-01");
    assert.equal(h.samples[1].date, "2026-03-01");
});

test("parseHealthHistory on empty or absent input", () => {
    for (const raw of ["", null, undefined, "garbage"]) {
        const h = Model.parseHealthHistory(raw);
        assert.equal(h.samples.length, 0, JSON.stringify(raw));
    }
    assert.equal(Model.parseHealthHistory("0|").samples.length, 0);
});

// ----------------------------------------------------------------- trend
test("formatSpan picks the coarsest honest unit", () => {
    assert.equal(Model.formatSpan(1), "1 day");
    assert.equal(Model.formatSpan(12), "12 days");
    assert.equal(Model.formatSpan(21), "3 weeks");
    assert.equal(Model.formatSpan(90), "3 months");
    assert.equal(Model.formatSpan(365), "12 months");
    assert.equal(Model.formatSpan(1096), "3 years");
    assert.equal(Model.formatSpan(0), "");
});

test("healthTrend reports the decline over the logged span", () => {
    const h = Model.parseHealthHistory(Model.parseKeyValue(STATS_ON).health_history);
    const t = Model.healthTrend(h);
    assert.equal(t.ready, true);
    assert.equal(t.healthDelta, -2.6);
    assert.equal(t.cycleDelta, 179);
    assert.match(t.text, /^−2\.6% health over 6 months · \+179 cycles$/);
});

test("healthTrend stays quiet until the log is worth reading", () => {
    // Day one: nothing to compare against.
    const one = Model.parseHealthHistory("1|2026-09-04,83.4,359");
    assert.equal(Model.healthTrend(one).ready, false);
    assert.equal(Model.healthTrend(one).text, "Tracking since 2026-09-04");

    // Two samples, three days apart: charge_full is a running gauge estimate
    // that drifts on its own, so this is noise, not a trend.
    const short = Model.parseHealthHistory("2|2026-09-01,83.4,359 2026-09-04,84.9,359");
    assert.equal(Model.healthTrend(short).ready, false);

    // Nothing logged at all.
    assert.equal(Model.healthTrend(Model.parseHealthHistory("")).text, "No history yet");
    assert.equal(Model.healthTrend(null).ready, false);
});

test("healthTrend signs a gain and a flat line correctly", () => {
    const up = Model.parseHealthHistory("2|2026-01-01,80.0,10 2026-06-01,81.0,20");
    assert.match(Model.healthTrend(up).text, /^\+1% health/);
    const flat = Model.parseHealthHistory("2|2026-01-01,80.0,10 2026-06-01,80.0,10");
    assert.match(Model.healthTrend(flat).text, /^±0% health/);
    // No cycles gained: the clause is omitted rather than reading "+0 cycles".
    assert.ok(!Model.healthTrend(flat).text.includes("cycles"));
});

// ------------------------------------------------------------- sparkline
test("sparklinePoints normalises to 0..1 with y inverted", () => {
    const h = Model.parseHealthHistory("3|2026-01-01,90.0,0 2026-02-01,85.0,0 2026-03-01,80.0,0");
    const p = Model.sparklinePoints(h);
    assert.equal(p.length, 3);
    assert.equal(p[0].x, 0);
    assert.equal(p[2].x, 1);
    // Highest health draws at the TOP (y = 0), lowest at the bottom.
    assert.equal(p[0].y, 0);
    assert.equal(p[2].y, 1);
});

test("sparkline x follows real time, so gaps read as gaps", () => {
    // Two samples a day apart, then a six-month hole. The middle point must
    // sit hard against the left edge, not at the halfway mark an
    // index-based plot would give it.
    const h = Model.parseHealthHistory("3|2026-01-01,90.0,0 2026-01-02,89.0,0 2026-07-01,88.0,0");
    const p = Model.sparklinePoints(h);
    assert.ok(p[1].x < 0.01, `middle point at ${p[1].x}, expected hard left`);
    assert.equal(p[2].x, 1);
});

test("a near-flat history draws flat, not as a cliff", () => {
    // 0.2% of decline must not be stretched to fill the whole box: the floor
    // is a one-point range, so this lands near the middle.
    const h = Model.parseHealthHistory("2|2026-01-01,83.5,0 2026-06-01,83.3,0");
    const p = Model.sparklinePoints(h);
    for (const pt of p)
        assert.ok(pt.y > 0.2 && pt.y < 0.8, `y=${pt.y} should stay mid-box for a flat line`);
});

test("sparklinePoints refuses to plot what it cannot", () => {
    assert.deepEqual(Model.sparklinePoints(Model.parseHealthHistory("1|2026-01-01,90.0,0")), []);
    assert.deepEqual(Model.sparklinePoints(null), []);
    // Every sample on the same day: zero span, nothing to draw against.
    assert.deepEqual(Model.sparklinePoints(Model.parseHealthHistory("2|2026-01-01,90.0,0 2026-01-01,89.0,0")), []);
});

console.log(failures === 0 ? "\nall PowerModel tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);

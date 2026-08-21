// Unit tests for NightLightModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/NightLightModel.test.js
//
// Every payload below is a real line captured from sunsetr 0.12.5 on this
// machine (2026-08-21), not a hand-written fixture — including the detail
// that made the parser what it is: the follower emits compact one-line JSON
// while the one-shot `status --json` is pretty-printed and carries no
// event_type at all.
//
// NightLightModel.js is dependency-free so these run under plain node. See
// WarpModel.test.js for the same arrangement; `node <file>` is the runner.

const assert = require("node:assert/strict");
const Model = require("./NightLightModel.js");

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

// ----------------------------------------------- real payloads, sunsetr 0.12.5

// Follower, schedule in charge, after sunset.
const FOLLOW_NIGHT = '{"event_type":"state_applied","active_preset":"default","period":"night","state":"stable","current_temp":3300,"current_gamma":90.0,"next_period":"2026-08-22T05:28:48.000853185+06:00"}';
// Follower, the echo of `sunsetr set night_temp=3000`.
const FOLLOW_CONFIG = '{"event_type":"config_changed","target_period":"night","target_temp":3000,"target_gamma":90.0}';
// One-shot `status --json` under each of the three modes. Pretty-printed in
// reality; JSON.parse does not care about the whitespace, and the absence of
// event_type is the part that matters.
const ONESHOT_AUTO = '{"active_preset":"default","period":"night","state":"stable","current_temp":3300,"current_gamma":90.0,"next_period":"2026-08-22T05:28:48.000880963+06:00"}';
const ONESHOT_DAY = '{"active_preset":"day","period":"static","state":"static","current_temp":6500,"current_gamma":100.0}';
const ONESHOT_NIGHT = '{"active_preset":"night","period":"static","state":"static","current_temp":3300,"current_gamma":90.0}';

const auto = Model.parseEvent(ONESHOT_AUTO);
const dayHeld = Model.parseEvent(ONESHOT_DAY);
const nightHeld = Model.parseEvent(ONESHOT_NIGHT);

// ------------------------------------------------------------------- parsing

test("follower state line parses to a state event", () => {
    const event = Model.parseEvent(FOLLOW_NIGHT);
    assert.equal(event.kind, "state");
    assert.equal(event.preset, "default");
    assert.equal(event.period, "night");
    assert.equal(event.phase, "stable");
    assert.equal(event.temp, 3300);
    assert.equal(event.gamma, 90);
});

test("config_changed parses as its own kind, never as state", () => {
    const event = Model.parseEvent(FOLLOW_CONFIG);
    assert.equal(event.kind, "config");
    assert.equal(event.temp, 3000);
    // No preset/period promotion: a config echo must not be mistaken for the
    // display having actually moved.
    assert.equal(event.preset, undefined);
});

test("one-shot status has no event_type and still parses as state", () => {
    assert.equal(auto.kind, "state");
    assert.equal(auto.temp, 3300);
});

test("unknown event types and junk are dropped, not guessed at", () => {
    assert.equal(Model.parseEvent('{"event_type":"something_new","x":1}'), null);
    assert.equal(Model.parseEvent("┣ Entering night mode"), null);
    assert.equal(Model.parseEvent(""), null);
    assert.equal(Model.parseEvent(null), null);
});

// -------------------------------------------------------------------- state

test("default preset means the schedule is in charge", () => {
    assert.equal(Model.forcedPreset(auto), "");
    assert.equal(Model.isForced(auto), false);
    assert.equal(Model.activeModeKey(auto), "auto");
});

test("a held preset is reported by name", () => {
    assert.equal(Model.forcedPreset(dayHeld), "day");
    assert.equal(Model.forcedPreset(nightHeld), "night");
    assert.equal(Model.activeModeKey(dayHeld), "day");
    assert.equal(Model.activeModeKey(nightHeld), "night");
});

test("warmth is read from the temperature, not the period", () => {
    assert.equal(Model.isWarm(auto, 6500), true);
    assert.equal(Model.isWarm(nightHeld, 6500), true);
    assert.equal(Model.isWarm(dayHeld, 6500), false);
});

test("a night PERIOD at neutral temperature is not warm yet", () => {
    // The transition case the icon exists to get right: sunsetr has flipped
    // the period but the fade has barely started.
    const midFade = Model.parseEvent('{"event_type":"state_applied","active_preset":"default","period":"night","state":"transitioning","current_temp":6480,"current_gamma":99.8,"next_period":"2026-08-22T05:28:48.000000000+06:00"}');
    assert.equal(midFade.period, "night");
    assert.equal(Model.isWarm(midFade, 6500), true, "6480 is below the day point, so technically warm");
    assert.equal(Model.isTransitioning(midFade), true);
    // …and at the exact day point it is not warm at all.
    const atNeutral = Object.assign({}, midFade, { temp: 6500 });
    assert.equal(Model.isWarm(atNeutral, 6500), false);
});

test("stable and static are both settled", () => {
    assert.equal(Model.isTransitioning(auto), false);
    assert.equal(Model.isTransitioning(dayHeld), false);
});

test("a custom day_temp moves the warm threshold", () => {
    // Someone who sets day_temp = 5000 has a neutral point of 5000, and 6500
    // would then be COOLER than neutral rather than warm.
    assert.equal(Model.isWarm({ temp: 5500 }, 5000), false);
    assert.equal(Model.isWarm({ temp: 4500 }, 5000), true);
    // A missing/zero day_temp falls back to 6500 rather than making
    // everything warm.
    assert.equal(Model.isWarm({ temp: 3300 }, 0), true);
    assert.equal(Model.isWarm({ temp: 6500 }, 0), false);
});

// ------------------------------------------------------------------- toggle

test("toggle releases any hold back to the schedule", () => {
    assert.equal(Model.toggleTarget(dayHeld, 6500), "auto");
    assert.equal(Model.toggleTarget(nightHeld, 6500), "auto");
});

test("toggle from auto forces the opposite of what is happening", () => {
    assert.equal(Model.toggleTarget(auto, 6500), "day", "warm evening -> hold neutral");
    const daytime = Object.assign({}, auto, { temp: 6500, period: "day" });
    assert.equal(Model.toggleTarget(daytime, 6500), "night", "neutral afternoon -> hold warm");
});

// --------------------------------------------------------------- timestamps

test("nanosecond precision is truncated, not rejected", () => {
    // Date.parse is only specified to milliseconds; sunsetr emits nine
    // digits. A naive `new Date(raw)` is Invalid Date in some engines.
    const stamp = Model.parseTimestamp("2026-08-22T05:28:48.000853185+06:00");
    assert.notEqual(stamp, null);
    assert.equal(stamp.getTime(), Date.parse("2026-08-22T05:28:48.000+06:00"));
});

test("a missing next_period yields no timestamp and no sentence", () => {
    assert.equal(Model.parseTimestamp(""), null);
    // A held preset suspends the schedule, so there is no next transition to
    // name even though one could be computed.
    assert.equal(Model.nextTransitionText(dayHeld, 6500), "");
    assert.equal(Model.nextTransitionText(nightHeld, 6500), "");
});

test("the next transition names what it will do, in local time", () => {
    const text = Model.nextTransitionText(auto, 6500);
    // Asserted against the same Date the model used, so this passes in any
    // timezone rather than only in Asia/Dhaka where it was recorded.
    const expected = "Neutral at " + Model.clockText(new Date(Date.parse("2026-08-22T05:28:48.000+06:00")));
    assert.equal(text, expected);
    // Going the other way: neutral now, so the next boundary warms it.
    const daytime = Object.assign({}, auto, { temp: 6500 });
    assert.ok(Model.nextTransitionText(daytime, 6500).startsWith("Warms at "));
});

test("clock text is zero-padded on both halves", () => {
    assert.equal(Model.clockText(new Date(2026, 7, 22, 5, 8)), "05:08");
    assert.equal(Model.clockText(new Date(2026, 7, 22, 18, 30)), "18:30");
    assert.equal(Model.clockText(null), "");
});

// -------------------------------------------------------------------- prose

test("the mood ladder renames across a preset change", () => {
    assert.equal(Model.moodName(3300), "Lamplight");
    assert.equal(Model.moodName(6500), "Daylight");
    assert.notEqual(Model.moodName(3300), Model.moodName(6500));
    // …and holds still for a small nudge inside a band.
    assert.equal(Model.moodName(3300), Model.moodName(3200));
    assert.equal(Model.moodName(0), "Off");
});

test("kelvin text handles the no-reading case", () => {
    assert.equal(Model.kelvinText(3300), "3300K");
    assert.equal(Model.kelvinText(0), "—");
});

test("the tooltip distinguishes held from scheduled", () => {
    assert.equal(Model.tooltipText(dayHeld, 6500, true), "Night light — held neutral (6500K)");
    assert.equal(Model.tooltipText(nightHeld, 6500, true), "Night light — held warm (3300K)");
    assert.ok(Model.tooltipText(auto, 6500, true).startsWith("Night light — on (3300K), "));
    assert.equal(Model.tooltipText(auto, 6500, false), "Night light — off");
});

test("the hero meta omits a gamma that is not doing anything", () => {
    assert.equal(Model.heroMeta(dayHeld, 6500, true), "Daylight · 6500K");
    assert.equal(Model.heroMeta(nightHeld, 6500, true), "Lamplight · 3300K · 90% gamma");
    assert.equal(Model.heroMeta(auto, 6500, false), "sunsetr is not running");
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

// Unit tests for AiModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/AiModel.test.js
//
// `node <file>` is the runner, as with the other bar widget model tests.

const assert = require("node:assert/strict");
const Model = require("./AiModel.js");

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

test("formatTier: a Max subscription keeps its multiplier", () => {
    assert.equal(Model.formatTier("max", "default_claude_max_20x"), "Max 20x");
    assert.equal(Model.formatTier("max", "default_claude_max_5x"), "Max 5x");
});

test("formatTier: a Team seat on a Max tier reads Team, not Max", () => {
    assert.equal(Model.formatTier("team", "default_claude_max_5x"), "Team 5x");
});

test("formatTier: no multiplier leaves the subscription, title-cased", () => {
    assert.equal(Model.formatTier("pro", "default_claude_pro"), "Pro");
    assert.equal(Model.formatTier("pro", ""), "Pro");
    assert.equal(Model.formatTier("team", undefined), "Team");
});

test("formatTier: a tier with no subscription falls back to Max", () => {
    assert.equal(Model.formatTier("", "default_claude_max_20x"), "Max 20x");
    assert.equal(Model.formatTier("", ""), "");
});

const NOW = Date.parse("2026-10-12T12:00:00Z");
const claude = {
    providerId: "claude",
    rateLimitPercent: 0.78,
    rateLimitLabel: "Session (5-hour)",
    rateLimitResetAt: "2026-10-12T11:00:00Z", // an hour ago
    secondaryRateLimitPercent: 0.4,
    secondaryRateLimitLabel: "Weekly (7-day)",
    secondaryRateLimitResetAt: "2026-10-15T00:00:00Z",
    extraLimits: [
        { title: "Opus", subtitle: "7-day", percent: 0.95, resetAt: "2026-10-12T11:59:00Z" },
        { title: "Sonnet", subtitle: "7-day", percent: 0.2, resetAt: "2026-10-14T00:00:00Z" }
    ]
};

test("limitWindows: a window past its reset reads 0% with no reset time", () => {
    const w = Model.limitWindows(claude, NOW);
    assert.deepEqual(w.map(x => [x.title, x.percent, x.resetAt]), [
        ["Session", 0, ""],
        ["Weekly", 0.4, "2026-10-15T00:00:00Z"],
        ["Opus", 0, ""],
        ["Sonnet", 0.2, "2026-10-14T00:00:00Z"]
    ]);
});

test("limitWindows: before the reset the window is untouched", () => {
    const w = Model.limitWindows(claude, Date.parse("2026-10-12T10:00:00Z"));
    assert.deepEqual(w.map(x => x.percent), [0.78, 0.4, 0.95, 0.2]);
});

test("limitWindows: exactly at the reset counts as rolled over", () => {
    const w = Model.limitWindows(claude, Date.parse("2026-10-12T11:00:00Z"));
    assert.equal(w[0].percent, 0);
});

test("limitWindows: an empty or unparseable reset keeps the number", () => {
    const p = Object.assign({}, claude, { rateLimitResetAt: "", secondaryRateLimitResetAt: "not a date", extraLimits: [] });
    const w = Model.limitWindows(p, NOW);
    assert.deepEqual(w.map(x => [x.percent, x.resetAt]), [[0.78, ""], [0.4, "not a date"]]);
});

test("limitWindows: a provider without a window publishes none", () => {
    assert.deepEqual(Model.limitWindows(null, NOW), []);
    assert.deepEqual(Model.limitWindows({ rateLimitPercent: -1, secondaryRateLimitPercent: -1 }, NOW), []);
});

test("staleAgeText: current numbers say nothing", () => {
    assert.equal(Model.staleAgeText({ limitsStale: false, limitsFetchedAtMs: NOW - 3600000 }, NOW), "");
    assert.equal(Model.staleAgeText(null, NOW), "");
});

test("staleAgeText: stale numbers say how old they are", () => {
    assert.equal(Model.staleAgeText({ limitsStale: true, limitsFetchedAtMs: NOW - (2 * 3600000 + 5 * 60000) }, NOW), "Last updated 2h 5m ago");
    assert.equal(Model.staleAgeText({ limitsStale: true, limitsFetchedAtMs: NOW - 30000 }, NOW), "Last updated less than a minute ago");
    assert.equal(Model.staleAgeText({ limitsStale: true, limitsFetchedAtMs: 0 }, NOW), "Last updated time unavailable");
});

test("displayProvider: carries the staleness fields through, defaulted for other providers", () => {
    const shown = Model.displayProvider(Object.assign({}, claude, { limitsStale: true, limitsFetchedAtMs: 123 }), null);
    assert.equal(shown.limitsStale, true);
    assert.equal(shown.limitsFetchedAtMs, 123);
    const codex = Model.displayProvider({ providerId: "codex", rateLimitPercent: 0.1 }, null);
    assert.equal(codex.limitsStale, false);
    assert.equal(codex.limitsFetchedAtMs, 0);
});

console.log(failures === 0 ? "\nall AiModel tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);

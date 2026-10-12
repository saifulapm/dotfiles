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

console.log(failures === 0 ? "\nall AiModel tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);

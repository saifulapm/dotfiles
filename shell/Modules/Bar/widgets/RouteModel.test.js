// Unit tests for RouteModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/RouteModel.test.js
//
// RouteModel.js is a `.pragma library` file, which node cannot parse, so it is
// evaluated in a fresh context with that one line stripped; its top-level
// functions land on the context. Covers the map from the workflow agent's
// route file to what the bar glyph and its panel draw.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "RouteModel.js"), "utf8").replace(/^\.pragma library$/m, "");
const Model = vm.createContext({});
vm.runInContext(source, Model);

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

// The vm context has its own Object prototype, so compare through JSON.
function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

const PHONE = "󰄜"; // md-cellphone
const DESKTOP = "󰍹"; // md-monitor

test("device held by this machine draws the desktop glyph with a count", () => {
    const state = Model.parseState('{"route":"device","machine":"mac-mini-m2","waiting":2,"hub":"http://hub:7700"}');
    assert.equal(Model.visible(state), true);
    assert.equal(Model.glyph(state), DESKTOP);
    assert.equal(Model.badge(state), "2");
    assert.equal(Model.currentChoice(state, "mac-mini-m2"), "device");
    assert.equal(Model.deviceLabel(state, "mac-mini-m2"), "Device (mac-mini-m2)");
    assert.equal(Model.waitingLine(state), "2 waiting");
    assert.equal(Model.hubUrl(state), "http://hub:7700");
});

test("the agent's own name for this machine wins over qshell's", () => {
    const state = Model.parseState('{"route":"device","machine":"mini","waiting":0,"hub":"http://hub:7700","self":"mini"}');
    assert.equal(Model.currentChoice(state, "mac-mini-m2"), "device");
    assert.equal(Model.deviceLabel(state, "mac-mini-m2"), "Device (mini)");
    assert.equal(Model.elsewhereLabel(state, "mac-mini-m2"), "");
    const nuc = Model.parseState('{"route":"device","machine":"nuc","waiting":0,"self":"mini"}');
    assert.equal(Model.currentChoice(nuc, "mac-mini-m2"), "elsewhere");
    assert.equal(Model.elsewhereLabel(nuc, "mac-mini-m2"), "Device (nuc)");
});

test("phone route draws the phone glyph with no badge", () => {
    const state = Model.parseState('{"route":"phone","machine":null,"waiting":0}');
    assert.equal(Model.visible(state), true);
    assert.equal(Model.glyph(state), PHONE);
    assert.equal(Model.badge(state), "");
    assert.equal(Model.currentChoice(state, "mac-mini-m2"), "phone");
    assert.equal(Model.deviceLabel(state, "mac-mini-m2"), "Device (mac-mini-m2)");
    assert.equal(Model.waitingLine(state), "0 waiting");
});

test("device held by another machine names that machine, and Device here is still a choice", () => {
    const state = Model.parseState('{"route":"device","machine":"nuc","waiting":1}');
    assert.equal(Model.glyph(state), DESKTOP);
    assert.equal(Model.currentChoice(state, "mac-mini-m2"), "elsewhere");
    assert.equal(Model.elsewhereLabel(state, "mac-mini-m2"), "Device (nuc)");
    assert.equal(Model.deviceLabel(state, "mac-mini-m2"), "Device (mac-mini-m2)");
    assert.deepEqual(plain(Model.commandFor("device")), ["workflow", "route", "device"]);
});

test("a missing or garbage file hides the glyph", () => {
    assert.equal(Model.visible(Model.parseState("")), false);
    assert.equal(Model.visible(Model.parseState("{not json")), false);
    assert.equal(Model.visible(Model.parseState("[]")), false);
    assert.equal(Model.visible(Model.parseState('{"route":"pager","waiting":1}')), false);
    assert.equal(Model.visible(null), false);
});

test("each choice runs the workflow route command by argv", () => {
    assert.deepEqual(plain(Model.commandFor("phone")), ["workflow", "route", "phone"]);
    assert.deepEqual(plain(Model.commandFor("device")), ["workflow", "route", "device"]);
});

if (failures > 0) {
    console.log(`\n${failures} failing`);
    process.exit(1);
}
console.log("\nall passing");

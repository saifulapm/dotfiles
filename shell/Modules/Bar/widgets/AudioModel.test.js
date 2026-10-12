// Unit tests for AudioModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/AudioModel.test.js
//
// AudioModel.js is a `.pragma library` file, which node cannot parse, so it is
// evaluated in a fresh context with that one line stripped; its top-level
// functions land on the context. Covers the row projection the audio panel's
// Repeaters read (omarchy c9faea7c, 92e1a276).

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "AudioModel.js"), "utf8").replace(/^\.pragma library$/m, "");
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

// A destroyed PwNode stays truthy but reads back no id, which is the shape the
// third entry stands in for: it must not reach a Repeater row. The first carries
// an object like a live node's audio, so a row that is the node itself fails here.
test("projects nodes to primitive rows and drops nodes without an id", () => {
    assert.deepEqual(plain(Model.rowSnapshot([{ id: 0, name: "alsa_output", audio: { volume: 1 } }, { id: 42 }, {}, null])), [
        { id: 0, name: "alsa_output" },
        { id: 42, name: "" }
    ]);
});

test("projects a missing list to no rows", () => {
    assert.deepEqual(plain(Model.rowSnapshot(undefined)), []);
});

test("rows carry the node name that identifies them", () => {
    assert.equal(Model.nodeRow({ id: 7, name: "bluez_output" }).name, "bluez_output");
});

if (failures > 0) {
    console.log(`\n${failures} failing`);
    process.exit(1);
}
console.log("\nall passing");

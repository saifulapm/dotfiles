// Unit tests for NetworkModel.js's connectivity helpers. Run with:
//
//     node shell/Modules/Bar/widgets/NetworkModel.test.js
//
// The captive-portal rows are driven entirely by these two functions, and the
// panel cannot be exercised against a real portal on demand, so the decision
// table lives here.

const assert = require("node:assert/strict");
const Model = require("./NetworkModel.js");

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

// PROBED against our quickshell 0.3.1 in an isolated `qs -p` config, not
// assumed — an undefined enum member would compare unequal to everything and
// degrade silently to "unknown" rather than erroring.
const NM = { None: 1, Portal: 2, Limited: 3, Full: 4 };

test("each NetworkManager verdict maps to its word", () => {
    assert.equal(Model.connectivityState("wifi", NM.Portal, NM, true), "portal");
    assert.equal(Model.connectivityState("wifi", NM.Limited, NM, true), "limited");
    assert.equal(Model.connectivityState("wifi", NM.Full, NM, true), "full");
    assert.equal(Model.connectivityState("wifi", NM.None, NM, true), "none");
});

test("an unknown value is unknown, not a verdict", () => {
    // NM's enum could grow; anything unrecognised must not read as "full".
    assert.equal(Model.connectivityState("wifi", 99, NM, true), "unknown");
    assert.equal(Model.connectivityState("wifi", 0, NM, true), "unknown");
    assert.equal(Model.connectivityState("wifi", undefined, NM, true), "unknown");
});

test("with checks disabled nothing is a verdict — this machine's case", () => {
    // Fedora sets no ConnectivityCheckUri, so NM answers an optimistic Full it
    // never measured. Without this gate the panel would claim working internet
    // it has not verified, and could never show a portal.
    assert.equal(Model.connectivityState("wifi", NM.Full, NM, false), "unknown");
    assert.equal(Model.connectivityState("wifi", NM.Portal, NM, false), "unknown");
});

test("disconnected wins over any cached verdict", () => {
    assert.equal(Model.connectivityState("disconnected", NM.Full, NM, true), "none");
    assert.equal(Model.connectivityState("disconnected", NM.Portal, NM, false), "none");
});

test("a restricted link draws differently from a working one", () => {
    const wifiOk = Model.connectionIcon("wifi", 80, "full");
    const wifiBad = Model.connectionIcon("wifi", 80, "portal");
    const ethOk = Model.connectionIcon("ethernet", 0, "full");
    const ethBad = Model.connectionIcon("ethernet", 0, "portal");
    assert.notEqual(wifiOk, wifiBad);
    assert.notEqual(ethOk, ethBad);
    // "limited" is restricted too — connected, but no internet through it.
    assert.equal(Model.connectionIcon("wifi", 80, "limited"), wifiBad);
});

test("an unverified link draws as a normal one, not as broken", () => {
    // "unknown" is the default state on this machine. Drawing it as restricted
    // would put a permanent warning glyph on a perfectly good connection.
    assert.equal(Model.connectionIcon("wifi", 80, "unknown"), Model.connectionIcon("wifi", 80, "full"));
    assert.equal(Model.connectionIcon("ethernet", 0, "unknown"), Model.connectionIcon("ethernet", 0, "full"));
});

test("wifi strength still drives the bars when the link is healthy", () => {
    const weak = Model.connectionIcon("wifi", 5, "full");
    const strong = Model.connectionIcon("wifi", 95, "full");
    assert.notEqual(weak, strong);
});

test("the portal URL is plain http, and fixed", () => {
    // HTTP on purpose: the network can only redirect a browser it can see, and
    // https would be an interception the browser correctly refuses. Fixed on
    // purpose: we never open a URL the portal handed us.
    assert.match(Model.CAPTIVE_PORTAL_URL, /^http:\/\//);
    assert.ok(!/^https/.test(Model.CAPTIVE_PORTAL_URL));
});

console.log(failures === 0 ? "\nall NetworkModel tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);

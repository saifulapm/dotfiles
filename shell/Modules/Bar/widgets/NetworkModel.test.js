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

// OWE transition mode (omarchy 18328559): between scans NetworkManager files
// the in-use access point under the hidden "_owetm_" SSID and drops the active
// profile from the device's AvailableConnections, so Quickshell lists no
// connected network. The bar and panel trust the device's own state and read
// the in-use AP's strength instead of flickering to disconnected.
const fs = require("node:fs");
const path = require("node:path");
const panelSource = fs.readFileSync(path.join(__dirname, "NetworkPanel.qml"), "utf8");
const widgetSource = fs.readFileSync(path.join(__dirname, "NetworkWidget.qml"), "utf8");

test("the panel keeps Wi-Fi while the device is connected but no network is listed", () => {
    const kind = panelSource.match(/readonly property string kind: \{[\s\S]*?\n {4}\}/);
    assert.ok(kind, "panel has a kind binding");
    const listed = kind[0].indexOf("panel.connectedWifiNetwork)");
    const device = kind[0].indexOf("panel.wifiDevice.connected)");
    assert.ok(device > 0, "kind falls back to the device state");
    assert.ok(listed > 0 && listed < device, "the listed network is preferred first");
});

test("the bar icon counts a connected device as online", () => {
    assert.match(widgetSource, /wifiUp: wifiNetwork !== null \|\| \(wifiDevice !== null && wifiDevice\.connected\)/);
    assert.match(widgetSource, /!wifiUp\)\s*\n\s*return "󰤮"/);
});

test("the connectivity key follows the device, not the SSID", () => {
    const key = panelSource.match(/readonly property string connectionKey: .*/);
    assert.ok(key && !/connectedWifiNetwork/.test(key[0]));
});

test("the connected network's own strength wins", () => {
    assert.equal(Model.connectedSignalStrength(0.8, 40), 80);
});

test("with no strength of its own, the in-use access point's is used", () => {
    assert.equal(Model.connectedSignalStrength(0, 67), 67);
    assert.equal(Model.connectedSignalStrength(undefined, 67), 67);
});

test("no strength when the in-use access point is unknown", () => {
    assert.equal(Model.connectedSignalStrength(0, -1), 0);
});

test("nmcli's in-use row is parsed, and only that row", () => {
    assert.equal(Model.parseActiveApSignal(" :82\n*:67\n :50\n"), 67);
    assert.equal(Model.parseActiveApSignal(" :82\n"), -1);
    assert.equal(Model.parseActiveApSignal(""), -1);
    assert.equal(Model.parseActiveApSignal(undefined), -1);
});

test("the in-use read never triggers a scan, and only runs while needed", () => {
    assert.match(widgetSource, /"--rescan", "no"/);
    assert.match(widgetSource, /running: rootItem\.needsActiveApSignal/);
});

console.log(failures === 0 ? "\nall NetworkModel tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);

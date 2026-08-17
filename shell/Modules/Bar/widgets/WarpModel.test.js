// Unit tests for WarpModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/WarpModel.test.js
//
// Ported from tobi/omarchy-warp's tests/model.test.js (CREDITS.md) and extended
// with the payloads warp-cli 2026.6.880.0 actually returned on this machine, so
// the three traps the parser is shaped around stay covered: errors at exit 0,
// a single-key `reason` object, and split-tunnel entries that are objects.
//
// WarpModel.js is deliberately dependency-free so the parsing rules can be
// checked without a Quickshell runtime. This is the only .test.js in the repo;
// there is no runner, because `node <file>` is the runner.

const assert = require("node:assert/strict");
const Model = require("./WarpModel.js");

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

// ------------------------------------------------------- real payloads, 2026.6

const STATUS_UNREGISTERED = '{"status":"Unable","reason":{"RegistrationMissing":"DaemonStartup"}}';
const REGISTRATION_MISSING = '{"code":"MissingRegistration","error":"Missing registration. Try running: \\"warp-cli registration new\\""}';
const STATS_DISCONNECTED = '{"code":"WarpNotConnected","error":"WARP is not connected."}';
const SETTINGS = JSON.stringify({
    settings: {
        always_on: false,
        switch_locked: false,
        operation_mode: "warp",
        split_tunnel_mode: "exclude",
        split_tunnel_hosts: [],
        split_tunnel_ips: [
            { value: "10.0.0.0/8", description: "" },
            { value: "100.64.0.0/10", description: "" }
        ],
        fallback_domains: [{ domain: "corp", description: "", dns_servers: [] }]
    }
});

// -------------------------------------------------------------------- the tests

test("humanize turns CLI identifiers into prose", () => {
    assert.equal(Model.humanize("RegistrationMissing"), "Registration missing");
    assert.equal(Model.humanize("always_on"), "Always on");
    assert.equal(Model.humanize(""), "");
});

test("a single-key reason object reads as prose, not [object Object]", () => {
    assert.equal(Model.reasonText({ RegistrationMissing: "DaemonStartup" }), "Registration missing (Daemon startup)");
    assert.equal(Model.reasonText({ ManualDisconnect: null }), "Manual disconnect");
    assert.equal(Model.reasonText("AlreadyConnected"), "Already connected");
    assert.equal(Model.reasonText(null), "");
});

test("status spots an unregistered device behind a nested reason", () => {
    const status = Model.parseStatus(STATUS_UNREGISTERED, 0, "");
    assert.equal(status.ok, true);
    assert.equal(status.available, true);
    assert.equal(status.connected, false);
    assert.equal(status.needsRegistration, true);
    assert.equal(status.statusText, "Device is not registered");
    assert.equal(status.reasonText, "Registration missing (Daemon startup)");
});

test("status reads Connected", () => {
    const status = Model.parseStatus('{"status":"Connected"}', 0, "");
    assert.equal(status.connected, true);
    assert.equal(status.needsRegistration, false);
    assert.equal(status.statusText, "Connected");
});

test("a daemon that is not listening is its own state, not an error", () => {
    const status = Model.parseStatus("", 1, "Unable to connect to the CloudflareWARP daemon");
    assert.equal(status.daemonDown, true);
    assert.equal(status.available, false);
    assert.equal(status.statusText, "WARP daemon is not running");
});

test("an error payload at exit 0 is still an error", () => {
    // This is the trap: warp-cli exits 0 and puts the failure in the body.
    const registration = Model.parseRegistration(REGISTRATION_MISSING);
    assert.equal(registration.registered, false);
    assert.match(registration.error, /Missing registration/);

    const stats = Model.parseTunnelStats(STATS_DISCONNECTED);
    assert.equal(stats.ok, false);
});

test("settings reads the operating mode and counts the rules", () => {
    const settings = Model.parseSettings(SETTINGS);
    assert.equal(settings.ok, true);
    assert.equal(settings.mode, "warp");
    assert.equal(settings.switchLocked, false);
    assert.equal(settings.splitTunnelMode, "exclude");
    assert.equal(settings.splitTunnelCount, 2);
    assert.equal(settings.fallbackDomainCount, 1);
    // Not present on this build; must read as absent rather than as a mode.
    assert.equal(settings.familiesMode, "");
});

test("settings survives junk", () => {
    const settings = Model.parseSettings("not json at all");
    assert.equal(settings.ok, false);
    assert.equal(settings.mode, "");
    assert.equal(settings.splitTunnelCount, 0);
});

test("split tunnel lists object entries and bare strings alike", () => {
    const split = Model.parseSplitTunnel(SETTINGS);
    assert.equal(split.ok, true);
    assert.equal(split.mode, "exclude");
    assert.equal(split.entries.length, 2);
    assert.equal(split.entries[0].value, "10.0.0.0/8");
    assert.equal(split.entries[0].description, "IP range");
    assert.equal(split.summary, "Exclude · 2 rules");

    const bare = Model.listEntries(["example.com"], "host");
    assert.equal(bare[0].value, "example.com");
    assert.equal(bare[0].description, "Host");
});

test("mode ids match `warp-cli mode --help`, all seven", () => {
    const ids = Model.MODES.map(m => m.id).sort();
    assert.deepEqual(ids, ["doh", "dot", "proxy", "tunnel_only", "warp", "warp+doh", "warp+dot"]);
    assert.equal(Model.isTunnelMode("warp+doh"), true);
    assert.equal(Model.isTunnelMode("doh"), false);
    assert.equal(Model.normalizeMode("Tunnel Only"), "tunnel_only");
    assert.equal(Model.modeLabel("warp+dot"), "WARP + DoT");
    const current = Model.modeRows("warp").filter(r => r.current);
    assert.equal(current.length, 1);
    assert.equal(current[0].id, "warp");
});

test("formatBytes and formatLatency stay compact", () => {
    assert.equal(Model.formatBytes(0), "0 B");
    assert.equal(Model.formatBytes(900), "900 B");
    assert.equal(Model.formatBytes(2048), "2.0 KB");
    assert.equal(Model.formatBytes(15 * 1024 * 1024), "15 MB");
    assert.equal(Model.formatLatency(4.25), "4.3 ms");
    assert.equal(Model.formatLatency(42.6), "43 ms");
    assert.equal(Model.formatLatency(0), "");
});

test("tunnel stats reads whichever shape the release emits", () => {
    const flat = Model.parseTunnelStats('{"endpoint":"162.159.193.1:2408","latency_ms":12.5,"bytes_sent":2048,"bytes_received":4096}');
    assert.equal(flat.ok, true);
    assert.equal(flat.endpoint, "162.159.193.1:2408");
    assert.equal(flat.latency, "13 ms");
    assert.equal(flat.sent, "2.0 KB");

    const nested = Model.parseTunnelStats('{"stats":{"peer_endpoint":"colo","tx_bytes":1024,"rx_bytes":1024}}');
    assert.equal(nested.endpoint, "colo");
    assert.equal(nested.sent, "1.0 KB");

    const metrics = Model.parseTunnelStats('[{"name":"latency","value":8},{"name":"endpoint","value":"edge"}]');
    assert.equal(metrics.latency, "8.0 ms");
    assert.equal(metrics.endpoint, "edge");
});

test("the tailnet verdict tells you which situation you are in", () => {
    const settings = Model.parseSettings(SETTINGS);
    const split = Model.parseSplitTunnel(SETTINGS);
    // Cloudflare's default exclude list carries Tailscale's CGNAT range.
    assert.equal(Model.tailnetVerdict(settings, split), `Tailscale excluded (${Model.TAILSCALE_CGNAT})`);

    // Excluding, but somebody removed the range.
    const trimmedSplit = { ok: true, mode: "exclude", entries: [{ value: "10.0.0.0/8" }] };
    assert.match(Model.tailnetVerdict(settings, trimmedSplit), /is not excluded/);

    // Include mode inverts the question.
    const including = { ok: true, mode: "include", entries: [] };
    assert.match(Model.tailnetVerdict(settings, including), /unless/);

    // A DNS-only mode takes no route, so there is nothing to say.
    const dnsOnly = Object.assign({}, settings, { mode: "doh" });
    assert.equal(Model.tailnetVerdict(dnsOnly, split), "");
});

console.log(failures === 0 ? "\nall tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);

// Near-verbatim port of tobi/omarchy-warp's Model.js (CREDITS.md): the
// `warp-cli --json` envelopes and everything read out of them — the status
// reason object, the settings block, the registration record, the tunnel stats
// and the split-tunnel rule list — plus the mode table and the humanizer.
//
// Side-effect free, like theirs, so `node WarpModel.test.js` can check the
// parsing rules with no QML runtime anywhere near them.
//
// Checked against the real thing on this machine (warp-cli 2026.6.880.0,
// 2026-08-17). Three of their defensive choices turn out to be load-bearing on
// this build and are kept for that reason rather than out of politeness:
//
//   * errors arrive as {"code","error"} WITH EXIT STATUS 0 — `registration show`
//     on an unregistered device and `tunnel stats` while disconnected both do
//     it — so every parse has to look at the payload, never just the status;
//   * `reason` is a single-key object, e.g. {"RegistrationMissing":
//     "DaemonStartup"}, not a string;
//   * `split_tunnel_ips` entries are {value, description} objects while
//     `split_tunnel_hosts` may be bare strings, so listEntries reads both.
//
// The mode table is verified against `warp-cli mode --help`: all seven ids
// match, and the descriptions here are the CLI's own wording rather than a
// paraphrase of it.
//
// Two things theirs carries are gone rather than ported:
//
//   * families_mode. It is not in the settings block on this build and no
//     `get` exists for it — `warp-cli dns families <MODE>` is set-only, and
//     Consumer-only at that. A switch that can be thrown but never read is a
//     switch that lies about where it is, so there is neither a parse nor a
//     setter for it here (theirs parses a key that is never present and ships
//     a setFamiliesMode() its own panel never calls).
//   * an unconditional trust in `registration show`. A read that came back
//     empty — killed by the watchdog, or the daemon dropping the socket
//     mid-answer — used to read as "this device is not registered" and put the
//     "!" badge on the bar. parseRegistration now says `known: false` for that
//     case and the service leaves the last real answer standing.
//
// Added here with no upstream in any of the three: parseTrace, over
// Cloudflare's own cdn-cgi/trace endpoint. `warp-cli status` reports what the
// daemon believes; the trace reports what Cloudflare actually received, which
// is the only way to catch a tunnel that is up but not carrying the traffic
// (ussego/owarp is where the idea comes from).

var MODES = [
    {
        id: "warp",
        label: "WARP",
        description: "Tunnel, with plain UDP DNS",
        tunnel: true
    },
    {
        id: "warp+doh",
        label: "WARP + DoH",
        description: "Tunnel, with DNS over HTTPS",
        tunnel: true
    },
    {
        id: "warp+dot",
        label: "WARP + DoT",
        description: "Tunnel, with DNS over TLS",
        tunnel: true
    },
    {
        id: "tunnel_only",
        label: "Tunnel only",
        description: "Tunnel, and do not proxy DNS",
        tunnel: true
    },
    {
        id: "proxy",
        label: "SOCKS5 proxy",
        description: "Tunnel for use by a local SOCKS5 proxy",
        tunnel: true
    },
    {
        id: "doh",
        label: "DoH only",
        description: "No tunnel; proxy DNS over HTTPS",
        tunnel: false
    },
    {
        id: "dot",
        label: "DoT only",
        description: "No tunnel; proxy DNS over TLS",
        tunnel: false
    }
];

function trimmed(value) {
    return String(value === undefined || value === null ? "" : value).trim();
}

function parseJson(raw) {
    var text = trimmed(raw);
    if (text === "")
        return null;
    try {
        return JSON.parse(text);
    } catch (e) {
        return null;
    }
}

// warp-cli errors come back as {"code": "...", "error": "..."} under --json and
// as free text without it. Normalize both into one message.
function errorMessage(raw) {
    var parsed = parseJson(raw);
    if (parsed && typeof parsed === "object") {
        if (parsed.error)
            return trimmed(parsed.error);
        if (parsed.code)
            return humanize(parsed.code);
    }
    return elide(trimmed(raw));
}

function errorCode(raw) {
    var parsed = parseJson(raw);
    if (parsed && typeof parsed === "object" && parsed.code)
        return trimmed(parsed.code);
    return "";
}

function elide(text, limit) {
    var max = limit === undefined ? 140 : limit;
    var value = trimmed(text).replace(/\s+/g, " ");
    return value.length > max ? value.substring(0, max - 1) + "…" : value;
}

// "RegistrationMissing" -> "Registration missing", "always_on" -> "Always on".
function humanize(value) {
    var text = trimmed(value);
    if (text === "")
        return "";
    var spaced = text.replace(/[_\-]+/g, " ").replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/\s+/g, " ").trim();
    return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase();
}

function isDaemonDown(text) {
    var value = trimmed(text).toLowerCase();
    if (value === "")
        return false;
    return value.indexOf("unable to connect to the cloudflarewarp daemon") !== -1 || value.indexOf("daemon is not running") !== -1 || value.indexOf("connection refused") !== -1;
}

function needsTos(text) {
    return /accept the warp terms of service/i.test(trimmed(text));
}

// The `reason` field is either a string or a single-key object such as
// {"RegistrationMissing": "DaemonStartup"} — which is what this machine
// actually returns before the device is registered.
function reasonText(reason) {
    if (!reason)
        return "";
    if (typeof reason === "string")
        return humanize(reason);
    if (typeof reason !== "object")
        return "";
    for (var key in reason) {
        var detail = reason[key];
        var head = humanize(key);
        if (typeof detail === "string" && trimmed(detail) !== "")
            return head + " (" + humanize(detail) + ")";
        return head;
    }
    return "";
}

function normalizeMode(mode) {
    var value = trimmed(mode).toLowerCase().replace(/\s+/g, "");
    if (value === "")
        return "";
    if (value === "warpwithdnsoverhttps" || value === "warpdoh")
        return "warp+doh";
    if (value === "warpwithdnsovertls" || value === "warpdot")
        return "warp+dot";
    if (value === "tunnelonly" || value === "tunnel-only")
        return "tunnel_only";
    return value;
}

function findMode(mode) {
    var id = normalizeMode(mode);
    for (var i = 0; i < MODES.length; i++) {
        if (MODES[i].id === id)
            return MODES[i];
    }
    return null;
}

function modeLabel(mode) {
    var found = findMode(mode);
    if (found)
        return found.label;
    var value = trimmed(mode);
    return value === "" ? "Unknown" : humanize(value);
}

function modeDescription(mode) {
    var found = findMode(mode);
    return found ? found.description : "";
}

function isTunnelMode(mode) {
    var found = findMode(mode);
    return found ? found.tunnel === true : false;
}

function modeRows(currentMode) {
    var current = normalizeMode(currentMode);
    var rows = [];
    for (var i = 0; i < MODES.length; i++) {
        var mode = MODES[i];
        rows.push({
            id: mode.id,
            label: mode.label,
            description: mode.description,
            tunnel: mode.tunnel === true,
            current: mode.id === current
        });
    }
    return rows;
}

// `warp-cli --json status` ->
//   {"status": "Connected"}
//   {"status": "Disconnected", "reason": {"ManualDisconnect": null}}
//   {"status": "Unable", "reason": {"RegistrationMissing": "DaemonStartup"}}
function parseStatus(raw, exitCode, stderr) {
    var combined = trimmed(raw) !== "" ? raw : stderr;
    if (isDaemonDown(raw) || isDaemonDown(stderr)) {
        return {
            ok: true,
            available: false,
            daemonDown: true,
            needsRegistration: false,
            needsTos: false,
            connected: false,
            status: "DaemonDown",
            statusText: "WARP daemon is not running",
            reasonText: ""
        };
    }
    if (needsTos(raw) || needsTos(stderr)) {
        return {
            ok: true,
            available: false,
            daemonDown: false,
            needsRegistration: false,
            needsTos: true,
            connected: false,
            status: "NeedsTos",
            statusText: "Accept the WARP terms of service",
            reasonText: ""
        };
    }

    var data = parseJson(raw);
    if (!data || typeof data !== "object") {
        return {
            ok: false,
            available: false,
            daemonDown: false,
            needsRegistration: false,
            needsTos: false,
            connected: false,
            status: "Unknown",
            statusText: exitCode === 0 ? "Unknown status" : "Status unavailable",
            reasonText: "",
            error: errorMessage(combined) || "Could not read warp-cli status"
        };
    }

    if (data.code || (data.error && !data.status)) {
        var code = trimmed(data.code);
        var missing = /registration/i.test(code) || /registration/i.test(trimmed(data.error));
        return {
            ok: true,
            available: false,
            daemonDown: false,
            needsRegistration: missing,
            needsTos: false,
            connected: false,
            status: code || "Error",
            statusText: missing ? "Device is not registered" : elide(trimmed(data.error) || humanize(code)),
            reasonText: ""
        };
    }

    var status = trimmed(data.status) || "Unknown";
    var reason = reasonText(data.reason);
    var registrationMissing = /registrationmissing/i.test(JSON.stringify(data.reason || ""));

    return {
        ok: true,
        available: true,
        daemonDown: false,
        needsRegistration: registrationMissing,
        needsTos: false,
        connected: /^connected$/i.test(status),
        connecting: /^connecting$/i.test(status),
        status: status,
        statusText: registrationMissing ? "Device is not registered" : humanize(status),
        reasonText: reason
    };
}

// `warp-cli --json settings` -> {"settings": {...}}. Every key below was read
// off this machine; families_mode is NOT among them on 2026.6.880.0 (Families
// lives under `warp-cli dns families`, Consumer only), so it stays probed-for
// rather than assumed.
function parseSettings(raw) {
    var data = parseJson(raw);
    var settings = data && typeof data === "object" ? (data.settings || data) : null;
    if (!settings || typeof settings !== "object") {
        return {
            ok: false,
            mode: "",
            alwaysOn: false,
            switchLocked: false,
            splitTunnelMode: "",
            splitTunnelCount: 0,
            disableForWifi: false,
            disableForEthernet: false,
            fallbackDomainCount: 0
        };
    }

    var splitIps = settings.split_tunnel_ips;
    var splitHosts = settings.split_tunnel_hosts;
    var fallback = settings.fallback_domains;

    return {
        ok: true,
        mode: normalizeMode(settings.operation_mode || settings.mode),
        alwaysOn: settings.always_on === true,
        switchLocked: settings.switch_locked === true,
        splitTunnelMode: trimmed(settings.split_tunnel_mode),
        splitTunnelCount: (splitIps && splitIps.length ? splitIps.length : 0) + (splitHosts && splitHosts.length ? splitHosts.length : 0),
        disableForWifi: settings.disable_for_wifi === true,
        disableForEthernet: settings.disable_for_ethernet === true,
        fallbackDomainCount: fallback && fallback.length ? fallback.length : 0
    };
}

function firstString(source, keys) {
    if (!source || typeof source !== "object")
        return "";
    for (var i = 0; i < keys.length; i++) {
        var value = source[keys[i]];
        if (typeof value === "string" && trimmed(value) !== "")
            return trimmed(value);
        if (typeof value === "number")
            return String(value);
    }
    return "";
}

function accountLabel(accountType, organization) {
    var type = trimmed(accountType);
    var org = trimmed(organization);
    if (org !== "" && type !== "")
        return org + " · " + humanize(type);
    if (org !== "")
        return org;
    if (type !== "")
        return humanize(type);
    return "";
}

// `warp-cli --json registration show`. Field names have moved between releases,
// so probe the plausible spellings instead of trusting one shape. Note the
// unregistered answer is {"code":"MissingRegistration","error":"…"} at exit 0,
// which is why the code/error test comes first.
//
// `known` separates "the client answered, and the answer is no registration"
// from "nothing came back" — an empty read is what a watchdog kill leaves
// behind, and it must not be allowed to badge the bar as unregistered.
function parseRegistration(raw) {
    var data = parseJson(raw);
    if (!data || typeof data !== "object") {
        return {
            known: false,
            registered: false,
            missing: false,
            accountType: "",
            accountLabel: "",
            organization: "",
            deviceId: "",
            deviceName: "",
            publicKey: "",
            error: ""
        };
    }
    if (data.code || data.error) {
        var failure = trimmed(data.code) + " " + trimmed(data.error);
        return {
            known: true,
            registered: false,
            missing: /registration/i.test(failure),
            accountType: "",
            accountLabel: "",
            organization: "",
            deviceId: "",
            deviceName: "",
            publicKey: "",
            error: errorMessage(raw)
        };
    }

    var registration = data.registration || data;
    var account = registration.account || data.account || {};
    var accountType = firstString(account, ["account_type", "accountType", "type", "plan"]) || firstString(registration, ["account_type", "accountType", "type"]);
    var organization = firstString(account, ["organization", "org", "team", "name"]) || firstString(registration, ["organization", "org", "team"]);

    return {
        known: true,
        registered: true,
        missing: false,
        accountType: accountType,
        accountLabel: accountLabel(accountType, organization),
        organization: organization,
        deviceId: firstString(registration, ["device_id", "deviceId", "id"]),
        deviceName: firstString(registration, ["device_name", "deviceName", "name"]),
        publicKey: firstString(registration, ["public_key", "publicKey", "key"]),
        error: ""
    };
}

function formatBytes(bytes) {
    var value = Number(bytes);
    if (!isFinite(value) || value <= 0)
        return "0 B";
    var units = ["B", "KB", "MB", "GB", "TB"];
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
        value = value / 1024;
        index += 1;
    }
    var decimals = value < 10 && index > 0 ? 1 : 0;
    return value.toFixed(decimals) + " " + units[index];
}

function formatLatency(value) {
    var ms = Number(value);
    if (!isFinite(ms) || ms <= 0)
        return "";
    return (ms < 10 ? ms.toFixed(1) : Math.round(ms)) + " ms";
}

// `estimated_loss` is a fraction, not a percentage: 0.00018 is 0.018 %. Worth a
// row of its own — on a tunnel, loss is what explains a connection that is up
// and miserable, and it is the number the latency alone will not show you.
function formatLoss(value) {
    var fraction = Number(value);
    if (!isFinite(fraction) || fraction < 0)
        return "";
    var percent = fraction * 100;
    if (percent === 0)
        return "0%";
    if (percent < 0.01)
        return "<0.01%";
    return percent.toFixed(2) + "%";
}

// `secs_since_last_handshake` counts up from the last one, so it is an age and
// reads as one. A tunnel whose handshake is minutes old is a tunnel to look at.
function formatHandshake(value) {
    var secs = Number(value);
    if (!isFinite(secs) || secs < 0)
        return "";
    if (secs < 60)
        return Math.round(secs) + " s ago";
    if (secs < 3600)
        return Math.round(secs / 60) + " min ago";
    return Math.round(secs / 3600) + " h ago";
}

function metricsToObject(metrics) {
    var result = {};
    for (var i = 0; i < metrics.length; i++) {
        var metric = metrics[i] || {};
        var name = trimmed(metric.name);
        if (name === "")
            continue;
        result[name] = metric.value;
    }
    return result;
}

// The endpoint is split by family on this build, and an unused family is
// present-but-blank rather than absent: "::" for v6, "0.0.0.0" for v4. Take
// whichever one is actually carrying the tunnel.
function tunnelEndpoint(stats) {
    var v4 = firstString(stats, ["v4_endpoint", "endpoint", "peer_endpoint", "server"]);
    if (v4 !== "" && v4 !== "0.0.0.0" && v4 !== "0.0.0.0:0")
        return v4;
    var v6 = firstString(stats, ["v6_endpoint"]);
    if (v6 !== "" && v6 !== "::" && v6 !== "[::]:0")
        return v6;
    return "";
}

// `warp-cli --json tunnel stats` shapes differ per release: sometimes a flat
// object, sometimes {"stats": {...}}, sometimes a metric array. Disconnected it
// answers {"code":"WarpNotConnected"} at exit 0, which lands in `empty`.
//
// The key names below were read off a live tunnel here on 2026-08-17, and three
// of them are why: this build says `v4_endpoint`, `estimated_latency_ms` and
// `secs_since_last_handshake`, none of which the ported spellings probed — so
// Endpoint, Latency and the handshake were silently blank on every connection
// while Protocol and Transfer worked. Nothing but a real tunnel shows that; the
// disconnected answer is an error payload, so the parse looked fine.
function parseTunnelStats(raw) {
    var data = parseJson(raw);
    var empty = {
        ok: false,
        endpoint: "",
        protocol: "",
        latency: "",
        loss: "",
        sent: "",
        received: "",
        handshake: "",
        colo: "",
        postQuantum: false
    };
    if (!data || typeof data !== "object" || data.code || data.error)
        return empty;

    var stats = data.stats && typeof data.stats === "object" ? data.stats : data;
    if (typeof stats.length === "number")
        stats = metricsToObject(stats);

    var latency = stats.estimated_latency_ms;
    if (latency === undefined)
        latency = stats.latency_ms;
    if (latency === undefined)
        latency = stats.latency;
    if (latency === undefined)
        latency = stats.estimated_rtt_ms;

    var sent = stats.bytes_sent !== undefined ? stats.bytes_sent : stats.tx_bytes;
    var received = stats.bytes_received !== undefined ? stats.bytes_received : stats.rx_bytes;

    var handshake = stats.secs_since_last_handshake;
    var edge = stats.edge && typeof stats.edge === "object" ? stats.edge : {};
    var tls = stats.tls && typeof stats.tls === "object" ? stats.tls : {};

    return {
        ok: true,
        endpoint: tunnelEndpoint(stats),
        protocol: firstString(stats, ["protocol", "tunnel_protocol"]),
        latency: formatLatency(latency),
        loss: stats.estimated_loss === undefined ? "" : formatLoss(stats.estimated_loss),
        sent: sent === undefined ? "" : formatBytes(sent),
        received: received === undefined ? "" : formatBytes(received),
        handshake: handshake === undefined ? firstString(stats, ["last_handshake", "latest_handshake", "handshake"]) : formatHandshake(handshake),
        colo: firstString(edge, ["colo"]),
        postQuantum: tls.post_quantum_enabled === true
    };
}

// ------------------------------------------------------------- egress check
// `curl https://www.cloudflare.com/cdn-cgi/trace` answers plain `key=value`
// lines, one per line, and `warp=` is Cloudflare's own verdict on the
// connection the request arrived over: "off", "on", or "plus" for WARP+.
// `gateway=` says whether a Zero Trust gateway saw it. This is the one fact
// warp-cli cannot supply — the daemon reports what it believes, not what
// Cloudflare received — so it is what catches a tunnel that is up and idle.
//
// Read off this machine 2026-08-17 with WARP off: ip, colo=DAC, loc=BD,
// warp=off, gateway=off. Verified keys only; the rest of the answer (uag, tls,
// sni, kex, …) is deliberately ignored.
function traceWarpLabel(value) {
    var warp = trimmed(value).toLowerCase();
    if (warp === "on")
        return "Through WARP";
    if (warp === "plus")
        return "Through WARP+";
    if (warp === "off")
        return "Not through WARP";
    return warp === "" ? "" : humanize(warp);
}

// "DAC" + "BD" -> "DAC · BD". Cloudflare's colo is the IATA code of the
// datacenter that answered, loc the country it placed the client in.
function traceLocation(colo, loc) {
    var edge = trimmed(colo).toUpperCase();
    var country = trimmed(loc).toUpperCase();
    if (edge !== "" && country !== "")
        return edge + " · " + country;
    return edge !== "" ? edge : country;
}

function parseTrace(raw) {
    var empty = {
        ok: false,
        warp: "",
        warpLabel: "",
        gateway: "",
        ip: "",
        colo: "",
        loc: "",
        location: ""
    };
    var text = trimmed(raw);
    if (text === "")
        return empty;

    var lines = text.split(/\r?\n/);
    var values = {};
    for (var i = 0; i < lines.length; i++) {
        var line = trimmed(lines[i]);
        var at = line.indexOf("=");
        if (at <= 0)
            continue;
        values[line.substring(0, at)] = line.substring(at + 1);
    }

    var warp = trimmed(values.warp).toLowerCase();
    var ip = trimmed(values.ip);
    // A body that carried neither is not a trace — a captive portal's login
    // page, or an error page, rather than Cloudflare answering.
    if (warp === "" && ip === "")
        return empty;

    var colo = trimmed(values.colo);
    var loc = trimmed(values.loc);
    return {
        ok: true,
        warp: warp,
        warpLabel: traceWarpLabel(warp),
        gateway: trimmed(values.gateway).toLowerCase(),
        ip: ip,
        colo: colo,
        loc: loc,
        location: traceLocation(colo, loc)
    };
}

// The tunnel is up as far as the daemon is concerned and Cloudflare still saw
// the request arrive outside it. Only ever said about a real `connected`, never
// about the optimistic one, so a click cannot make the panel cry leak.
function traceLeaking(connected, trace) {
    return connected === true && !!trace && trace.ok === true && trace.warp === "off";
}

function splitTunnelSummary(mode, total) {
    var head = mode === "" ? "Split tunnel" : humanize(mode);
    return head + " · " + total + (total === 1 ? " rule" : " rules");
}

// The accordion's two halves, ours: the summary above is one string, and the
// disclosure row wants a label it can set in the reading weight and a meta it
// can mute. Split so the row reads left-to-right like every other row on the
// card — the mode, then what the mode means.
function splitTunnelModeLabel(mode) {
    var value = trimmed(mode);
    return value === "" ? "Split tunnel" : humanize(value);
}

// "Exclude · 27 rules" names the setting; it does not say that those 27 are
// the ones that DO NOT go through the tunnel, which is the only thing anyone
// opens this list to find out.
function splitTunnelMeaning(mode, total) {
    var count = Number(total);
    if (!isFinite(count) || count <= 0)
        return "No rules";
    var subject = count + (count === 1 ? " rule " : " rules ");
    var value = trimmed(mode).toLowerCase();
    if (value === "exclude")
        return subject + (count === 1 ? "skips" : "skip") + " the tunnel";
    if (value === "include")
        return subject + (count === 1 ? "takes" : "take") + " the tunnel";
    return count + (count === 1 ? " rule" : " rules");
}

function splitTunnelText(settings) {
    if (!settings || settings.ok !== true)
        return "";
    var mode = trimmed(settings.splitTunnelMode);
    if (mode === "")
        return "";
    return humanize(mode) + " · " + settings.splitTunnelCount + (settings.splitTunnelCount === 1 ? " rule" : " rules");
}

function listEntries(list, kind) {
    var entries = [];
    if (!list || typeof list.length !== "number")
        return entries;
    for (var i = 0; i < list.length; i++) {
        var raw = list[i];
        var value = "";
        var description = "";
        if (raw && typeof raw === "object") {
            value = trimmed(raw.value !== undefined ? raw.value : (raw.address !== undefined ? raw.address : raw.host));
            description = trimmed(raw.description);
        } else {
            value = trimmed(raw);
        }
        if (value === "")
            continue;
        entries.push({
            id: kind + ":" + i + ":" + value,
            kind: kind,
            value: value,
            description: description !== "" ? description : (kind === "host" ? "Host" : "IP range")
        });
    }
    return entries;
}

// A readout, not an inspector: warp-cli owns the rules, this only lists them.
function parseSplitTunnel(raw) {
    var data = parseJson(raw);
    var settings = data && typeof data === "object" ? (data.settings || data) : null;
    if (!settings || typeof settings !== "object") {
        return {
            ok: false,
            mode: "",
            entries: [],
            summary: ""
        };
    }
    var mode = trimmed(settings.split_tunnel_mode);
    var entries = listEntries(settings.split_tunnel_ips, "ip").concat(listEntries(settings.split_tunnel_hosts, "host"));
    return {
        ok: true,
        mode: mode,
        entries: entries,
        summary: splitTunnelSummary(mode, entries.length)
    };
}

// Ours, with no upstream. WARP in a tunnel mode takes the default route, which
// is also where the tailnet lives — but Cloudflare's own default exclude list
// carries 100.64.0.0/10, Tailscale's CGNAT range, so in `exclude` mode the two
// coexist. Say which of the two situations the machine is actually in rather
// than warning unconditionally.
var TAILSCALE_CGNAT = "100.64.0.0/10";

function tailnetVerdict(settings, split) {
    if (!settings || settings.ok !== true || !isTunnelMode(settings.mode))
        return "";
    if (!split || split.ok !== true)
        return "";
    var excluding = trimmed(split.mode).toLowerCase() === "exclude";
    var listed = false;
    for (var i = 0; i < split.entries.length; i++) {
        if (split.entries[i].value === TAILSCALE_CGNAT) {
            listed = true;
            break;
        }
    }
    if (excluding && listed)
        return "Tailscale excluded (" + TAILSCALE_CGNAT + ")";
    if (excluding)
        return "Tailnet routed through WARP — " + TAILSCALE_CGNAT + " is not excluded";
    return "Tailnet routed through WARP unless " + TAILSCALE_CGNAT + " is included";
}

if (typeof module !== "undefined") {
    module.exports = {
        MODES: MODES,
        TAILSCALE_CGNAT: TAILSCALE_CGNAT,
        accountLabel: accountLabel,
        elide: elide,
        errorCode: errorCode,
        errorMessage: errorMessage,
        findMode: findMode,
        formatBytes: formatBytes,
        formatHandshake: formatHandshake,
        formatLatency: formatLatency,
        formatLoss: formatLoss,
        humanize: humanize,
        isDaemonDown: isDaemonDown,
        isTunnelMode: isTunnelMode,
        listEntries: listEntries,
        modeDescription: modeDescription,
        modeLabel: modeLabel,
        modeRows: modeRows,
        needsTos: needsTos,
        normalizeMode: normalizeMode,
        parseJson: parseJson,
        parseRegistration: parseRegistration,
        parseSettings: parseSettings,
        parseSplitTunnel: parseSplitTunnel,
        parseStatus: parseStatus,
        parseTrace: parseTrace,
        parseTunnelStats: parseTunnelStats,
        reasonText: reasonText,
        splitTunnelMeaning: splitTunnelMeaning,
        splitTunnelModeLabel: splitTunnelModeLabel,
        splitTunnelSummary: splitTunnelSummary,
        splitTunnelText: splitTunnelText,
        tailnetVerdict: tailnetVerdict,
        traceLeaking: traceLeaking,
        traceLocation: traceLocation,
        traceWarpLabel: traceWarpLabel
    };
}

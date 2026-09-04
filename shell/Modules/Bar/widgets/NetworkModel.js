// Near-verbatim port of omarchy's shell/plugins/panels/network/Model.js
// (MIT): the whole parsing and formatting layer behind the
// network panel — the key/tab/value reader for bin/network-status, the
// throughput and ping-window math, byte/rate/latency formatting, the band
// labels, the Wi-Fi row shaping and section titles, and the QR matrix parser.
//
// Changes from the source: their bar-pill helpers (parseNetworkStatus,
// connectionIcon) live in NetworkWidget.qml instead, the icon ladder returns
// Material Design glyphs (the FontAwesome range does not render under our
// Symbols Nerd Font fallback), signalStrength is normalised here because
// quickshell reports it as 0..1, and whitespace follows house 4-space
// qmlformat.

// ------------------------------------------------------------------- icons
function wifiIconFor(strength) {
    const icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"];
    const index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1));
    return icons[index];
}

// ---------------------------------------------------------- connectivity
// A known plain-HTTP endpoint, so the network is free to redirect a browser
// pointed at it to its own login page. NEVER executed, and never opened
// automatically — only on an explicit click, and we hand the browser this
// fixed URL rather than anything the portal told us.
var CAPTIVE_PORTAL_URL = "http://ping.archlinux.org/nm-check.txt";

// NetworkManager's own connectivity verdict, mapped to a word. NM does the
// HTTP probe itself and recognises an unexpected page body, not just a
// redirect, so consuming its answer beats running a second curl loop here and
// beats mistaking an ordinary timeout for a portal.
//
// `checksEnabled` is not decoration: NM keeps reporting its LAST value after
// probing is turned off (and reports an optimistic Full when it has never
// probed at all — this machine, where Fedora ships no ConnectivityCheckUri),
// so without the gate a stale or invented Full reads as a verdict.
//
// Enum values PROBED against our quickshell 0.3.1 rather than assumed:
// None=1, Portal=2, Limited=3, Full=4.
function connectivityState(kind, connectivity, states, checksEnabled) {
    if (kind === "disconnected")
        return "none";
    if (!checksEnabled)
        return "unknown";
    const s = states || {};
    if (connectivity === s.Portal)
        return "portal";
    if (connectivity === s.Limited)
        return "limited";
    if (connectivity === s.Full)
        return "full";
    if (connectivity === s.None)
        return "none";
    return "unknown";
}

// The connection mark, with a restricted variant: a link that carries packets
// but not the internet should not draw the same as a working one.
function connectionIcon(kind, strengthPercent, connectivity) {
    const restricted = connectivity === "portal" || connectivity === "limited";
    if (kind === "wifi")
        return restricted ? "󰤩" : wifiIconFor(strengthPercent); // md-wifi-alert
    if (kind === "ethernet")
        return restricted ? "󰈂" : "󰈀"; // md-ethernet-off : md-ethernet
    return "󰤮"; // md-wifi-off
}

// quickshell's WifiNetwork.signalStrength is a 0..1 double (verified on this
// machine); every consumer here works in percent.
function signalPercent(network) {
    if (!network)
        return 0;
    return Math.round((network.signalStrength || 0) * 100);
}

// --------------------------------------------------------------- formatting
function formatHeaderSpeed(mbps) {
    const v = parseInt(mbps, 10);
    if (!v || v < 0)
        return "";
    if (v >= 1000)
        return (v / 1000).toFixed(v % 1000 === 0 ? 0 : 1) + "gbit";
    return v + "mbit";
}

function formatHeaderFreq(mhz) {
    const v = parseFloat(mhz);
    if (!v)
        return "";

    if (v >= 2400 && v < 2500)
        return "2.4ghz";
    if (v >= 4900 && v < 5925)
        return "5ghz";
    if (v >= 5925 && v < 7125)
        return "6ghz";
    if (v >= 57000 && v < 71000)
        return "60ghz";

    const ghz = v / 1000;
    return ghz.toFixed(ghz % 1 === 0 ? 0 : 1) + "ghz";
}

// Wi-Fi band state belongs in the selector section, not beside the hero name.
// Ethernet has no equivalent selector, so keep its negotiated link speed here.
function headerDetail(info) {
    const value = info || {};
    if (value.type === "ethernet")
        return formatHeaderSpeed(value.speed || "");
    return "";
}

function bandLabel(band) {
    if (band === "auto")
        return "Auto";
    if (!band)
        return "";
    return band + "ghz";
}

// Under Automatic the pills are hidden, so the header carries the live band
// instead -- "WI-FI BAND: 2.4GHZ". Once a band is pinned the pills are on
// screen and say it themselves, so the header drops back to a plain label.
function bandSectionTitle(selected, current) {
    if (selected !== "auto")
        return "WI-FI BAND";

    const label = bandLabel(current);
    if (label === "")
        return "WI-FI BAND";

    return "WI-FI BAND: " + label.toUpperCase();
}

function bandTooltip(band) {
    if (band === "auto")
        return "Let Wi-Fi pick the band";
    if (!band)
        return "";
    return "Stay on " + bandLabel(band);
}

function parseBandStatus(raw) {
    const next = parseKeyValue(raw);
    const tokens = String(next.available || "").split(" ");
    const available = [];

    for (let i = 0; i < tokens.length; i++) {
        if (tokens[i] !== "")
            available.push(tokens[i]);
    }

    return {
        band: next.band || "",
        selected: next.selected || "auto",
        available: available
    };
}

function parseKeyValue(raw) {
    const next = {};
    const lines = String(raw || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!line)
            continue;
        const idx = line.indexOf("\t");
        if (idx === -1)
            continue;
        next[line.substring(0, idx)] = line.substring(idx + 1).trim();
    }
    return next;
}

// -------------------------------------------------------------- throughput
// Rates are deltas between successive samples. "prev" is held alongside a
// timestamp so the first sample after open, or after an interface switch,
// cannot manufacture a spike.
function throughputState(previous, next, now) {
    const prev = previous || {};
    const sample = next || {};
    const iface = sample.iface || "";
    const rx = parseFloat(sample.rx_bytes || "0");
    const tx = parseFloat(sample.tx_bytes || "0");
    const previousTime = Number(prev.prevSampleTime || 0);

    if (iface !== (prev.prevIface || "") || previousTime === 0) {
        return {
            prevIface: iface,
            prevRxBytes: rx,
            prevTxBytes: tx,
            prevSampleTime: now,
            downloadRate: 0,
            uploadRate: 0
        };
    }

    let downloadRate = Number(prev.downloadRate || 0);
    let uploadRate = Number(prev.uploadRate || 0);
    const dt = now - previousTime;
    if (dt > 0) {
        downloadRate = Math.max(0, (rx - Number(prev.prevRxBytes || 0)) / dt);
        uploadRate = Math.max(0, (tx - Number(prev.prevTxBytes || 0)) / dt);
    }

    return {
        prevIface: iface,
        prevRxBytes: rx,
        prevTxBytes: tx,
        prevSampleTime: now,
        downloadRate: downloadRate,
        uploadRate: uploadRate
    };
}

// ------------------------------------------------------------------- ping
function pingSampleValue(raw) {
    const value = parseFloat(raw);
    if (!isFinite(value) || value < 0)
        return null;
    return value;
}

function appendPingSample(samples, raw, limit) {
    const values = Array.isArray(samples) ? samples.slice() : [];

    values.push(pingSampleValue(raw));
    while (values.length > limit)
        values.shift();

    return values;
}

function averagePingLatency(samples, limit) {
    const values = Array.isArray(samples) ? samples : [];
    const sampleLimit = Math.max(1, parseInt(limit, 10) || values.length || 1);
    let total = 0;
    let count = 0;

    for (let i = Math.max(0, values.length - sampleLimit); i < values.length; i++) {
        const value = values[i];
        if (typeof value !== "number" || !isFinite(value) || value < 0)
            continue;
        total += value;
        count++;
    }

    return count > 0 ? total / count : -1;
}

function pingPacketLossPercent(samples) {
    const values = Array.isArray(samples) ? samples : [];
    if (values.length === 0)
        return 0;

    let lost = 0;
    for (let i = 0; i < values.length; i++) {
        if (values[i] === null)
            lost++;
    }

    return Math.round((lost / values.length) * 100);
}

function pingLatencyState(previous, next, limit, averageLimit) {
    const prev = previous || {};
    const sample = next || {};
    const iface = sample.iface || "";
    const window = Math.max(1, parseInt(limit, 10) || 5);
    const averageWindow = Math.max(1, parseInt(averageLimit, 10) || window);
    const reset = iface === "" || iface !== (prev.pingIface || "");
    let routerSamples = reset ? [] : prev.routerPingSamples;
    let internetSamples = reset ? [] : prev.internetPingSamples;

    routerSamples = sample.router_ping_ms === undefined ? [] : appendPingSample(routerSamples, sample.router_ping_ms, window);
    internetSamples = sample.internet_ping_ms === undefined ? [] : appendPingSample(internetSamples, sample.internet_ping_ms, window);

    return {
        pingIface: iface,
        routerPingSamples: routerSamples,
        internetPingSamples: internetSamples,
        routerPingLatency: averagePingLatency(routerSamples, averageWindow),
        internetPingLatency: averagePingLatency(internetSamples, averageWindow),
        internetPingPacketLoss: pingPacketLossPercent(internetSamples)
    };
}

function formatPacketLoss(percent, hasSamples) {
    if (hasSamples === false)
        return "--";

    const value = parseInt(percent, 10);
    if (!value || value < 0)
        return "0%";
    return value + "%";
}

function formatBytes(bytes) {
    let n = Number(bytes);
    if (!isFinite(n) || n < 0)
        n = 0;
    if (n < 1024)
        return Math.round(n) + " B";
    if (n < 1024 * 1024)
        return (n / 1024).toFixed(1) + " KB";
    if (n < 1024 * 1024 * 1024)
        return (n / (1024 * 1024)).toFixed(1) + " MB";
    return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
}

function formatRate(bytesPerSec) {
    return formatBytes(bytesPerSec) + "/s";
}

// `hasSamples` false means no probe has come back yet, which is different from
// a probe that timed out. The rows stay mounted through that gap and read "--"
// so the grid doesn't reflow a second after the panel opens.
function formatPingLatency(ms, hasSamples) {
    if (hasSamples === false)
        return "--";

    const value = parseFloat(ms);
    if (!isFinite(value) || value < 0)
        return "Timeout";
    return value.toFixed(value > 0 && value < 10 ? 1 : 0) + " ms";
}

// -------------------------------------------------------------------- rows
// Primitives only: rows become list-model data, so a WifiNetwork here would
// put a live QObject wrapper in every delegate's var property. NetworkManager
// churn (scans, AP removals) can destroy the object while a delegate is still
// incubating, which segfaults quickshell in wrap_slowPath on the dangling
// wrapper. Callers that need the object resolve it via networkForSsid().
function wifiRow(network) {
    if (!network)
        return null;
    return {
        connected: !!network.connected,
        known: !!network.known,
        ssid: network.name || "",
        signal: signalPercent(network),
        security: network.security
    };
}

function sortWifiRows(rows) {
    const nets = Array.isArray(rows) ? rows.slice() : [];
    nets.sort(function (a, b) {
        if (a.connected !== b.connected)
            return a.connected ? -1 : 1;
        if (a.known !== b.known)
            return a.known ? -1 : 1;
        return b.signal - a.signal;
    });
    return nets;
}

function wifiSectionTitle(wifiNetworks, index) {
    const networks = Array.isArray(wifiNetworks) ? wifiNetworks : [];
    if (index < 0 || index >= networks.length)
        return "";

    const net = networks[index];
    if (!net)
        return "";

    if (net.known && index === 0)
        return "KNOWN NETWORKS";
    if (!net.known && (index === 0 || (networks[index - 1] && networks[index - 1].known)))
        return "OTHER NETWORKS";
    return "";
}

// OWE (Enhanced Open) encrypts the air without authenticating anyone, so it has
// no credentials to collect. The lock glyph and the passphrase prompt behind it
// are both credentials-required affordances, so an OWE network gets neither.
function requiresCredentials(security, openSecurity, oweSecurity) {
    // Only the explicitly passwordless types bypass the prompt. A security type
    // this does not recognise stays credentialed, as the conservative fallback.
    return security !== openSecurity && security !== oweSecurity;
}

// Any known network that is not the current one can be forgotten — whether it
// took a passphrase to join has nothing to do with it. Tying this to the lock
// meant a saved open network could never be removed from the panel at all.
function canForgetNetwork(network) {
    return !!(network && network.known && !network.connected);
}

// --------------------------------------------------------------------- qr
function parseQrMatrix(raw) {
    const lines = String(raw || "").trim().split(/\r?\n/).filter(function (line) {
        return line !== "";
    });
    if (lines.length === 0)
        return {
            rows: [],
            size: 0
        };

    const size = lines[0].length;
    if (size !== lines.length)
        return {
            rows: [],
            size: 0
        };

    for (let i = 0; i < lines.length; i++) {
        if (lines[i].length !== size || !/^[01]+$/.test(lines[i]))
            return {
                rows: [],
                size: 0
            };
    }

    return {
        rows: lines,
        size: size
    };
}

// The password arrives on stdin and reaches nmcli through the scriptable
// `connection edit` editor -- argv is world-readable in /proc, so the secret
// must never be an argument (printf is a bash builtin, so no process spawns
// with it either).
var enterpriseConnectScript = "u=$(uuidgen); IFS= read -r pw;" + " nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\"" + " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" + " 802-1x.identity \"$2\" 802-1x.auth-timeout 8 >/dev/null" + " && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" + " && nmcli connection up uuid \"$u\"" + " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }";

function networkFailureReason(reason, needsCredentials, reasons) {
    const r = reasons || {};
    // Both of these name a passphrase, so they only fit a network that has one.
    if (needsCredentials && reason === r.NoSecrets)
        return "Passphrase required";
    if (needsCredentials && reason === r.WifiAuthTimeout)
        return "Wrong password";
    if (reason === r.WifiNetworkLost)
        return "Network lost";
    if (reason === r.WifiClientDisconnected)
        return "Disconnected";
    if (reason === r.WifiClientFailed)
        return "Connection failed";
    return "Failed to connect";
}

// Whether a failed connect should reopen the passphrase prompt. NoSecrets means
// credentials are missing, but only for a network that uses them at all. An auth
// timeout on such a network means the saved passphrase is wrong (the same
// profile a first failed attempt leaves behind as "known"), so the user needs a
// chance to re-enter it — connectWithPsk overwrites the stored PSK on submit.
// A passwordless network has no prompt to reopen, so it never reprompts.
function shouldRepromptPassphrase(reason, needsCredentials, reasons) {
    const r = reasons || {};
    if (!needsCredentials)
        return false;
    return reason === r.NoSecrets || reason === r.WifiAuthTimeout;
}

// Node-visible for the model tests; `module` is undefined under QML, so this
// block is inert there. The file had no exports until the connectivity
// helpers arrived and wanted covering.
if (typeof module !== "undefined") {
    module.exports = {
        wifiIconFor: wifiIconFor,
        signalPercent: signalPercent,
        connectivityState: connectivityState,
        connectionIcon: connectionIcon,
        CAPTIVE_PORTAL_URL: CAPTIVE_PORTAL_URL,
        shouldRepromptPassphrase: shouldRepromptPassphrase,
        requiresCredentials: typeof requiresCredentials === "function" ? requiresCredentials : undefined
    };
}

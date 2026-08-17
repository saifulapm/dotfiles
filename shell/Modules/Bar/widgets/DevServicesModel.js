// Dev-services catalog and parsing for the devservices widget — ours, in the
// shape of omarchy's dropbox model: the pure data the service
// and the panel read.
//
// The catalog is this machine's Herd-like on-demand stack: podman quadlet
// containers behind systemd-socket-proxyd, one systemd USER unit per service.
// The socket listens at ~0 RAM; the first TCP connection starts the proxy,
// whose Requires= starts the container (health-gated); ten idle minutes later
// the proxy exits and StopWhenUnneeded stops the container again. "Running"
// means the container service is active; "Armed" means the socket is
// listening with the container stopped.
//
// A manual warm-up must start the proxy SERVICE alongside the container: a
// bare `systemctl --user start mysql84.service` is stopped again at the next
// StopWhenUnneeded evaluation, while the proxy holds it up (and idle-exits
// after 10 minutes as usual). Both mailpit proxies wake the same
// mailpit.service, so its stop list carries the pair.

// Row glyphs are the Devicons brand marks (nf-dev-mysql U+E704,
// nf-dev-postgresql U+E76E, nf-dev-redis U+E76D) — the installed Symbols
// Nerd Font maps the whole range (verified via fc-list :charset; the old
// "Devicons do not render" note in the Dropbox widget predates this font).
// Mailpit has no brand glyph anywhere in the font, so it wears md-email.
var SERVICES = [
    {
        key: "mysql84",
        label: "MySQL 8.4",
        container: "dev-mysql84",
        startUnits: ["mysql84.service", "mysql84-proxy.service"],
        stopUnits: ["mysql84-proxy.service", "mysql84.service"],
        portLabel: "port 3306",
        glyph: "",
        webUrl: ""
    },
    {
        key: "postgres18",
        label: "PostgreSQL 18",
        container: "dev-postgres18",
        startUnits: ["postgres18.service", "postgres18-proxy.service"],
        stopUnits: ["postgres18-proxy.service", "postgres18.service"],
        portLabel: "port 5432",
        glyph: "",
        webUrl: ""
    },
    {
        key: "redis7",
        label: "Redis 7",
        container: "dev-redis7",
        startUnits: ["redis7.service", "redis7-proxy.service"],
        stopUnits: ["redis7-proxy.service", "redis7.service"],
        portLabel: "port 6379",
        glyph: "",
        webUrl: ""
    },
    {
        key: "mailpit",
        label: "Mailpit",
        container: "dev-mailpit",
        startUnits: ["mailpit.service", "mailpit-smtp-proxy.service"],
        stopUnits: ["mailpit-smtp-proxy.service", "mailpit-web-proxy.service", "mailpit.service"],
        portLabel: "smtp 1025 · web 8025",
        glyph: "󰇮",
        webUrl: "http://localhost:8025"
    }
];

// The one-shot probe's stdout: "OK" then one `podman ps` name per line.
// Anything else (including an empty answer) reads as "not this machine".
function parseProbe(raw) {
    var lines = String(raw || "").split("\n").map(function (l) {
        return l.trim();
    }).filter(function (l) {
        return l !== "";
    });
    if (lines.length === 0 || lines[0] !== "OK")
        return {
            available: false,
            running: {}
        };
    var running = {};
    for (var i = 1; i < lines.length; i++) {
        if (lines[i].indexOf("dev-") === 0)
            running[lines[i]] = true;
    }
    return {
        available: true,
        running: running
    };
}

// Every unit a transition can name — container units and their proxies, since
// a socket-activated wake runs jobs for both. The follower only has to
// recognize one of them to know something moved.
var WATCHED_UNITS = (function () {
    var seen = {};
    for (var i = 0; i < SERVICES.length; i++) {
        var def = SERVICES[i];
        var units = (def.startUnits || []).concat(def.stopUnits || []);
        for (var j = 0; j < units.length; j++)
            seen[units[j]] = true;
    }
    return seen;
})();

// One `busctl --user monitor --json=short` line → the unit name a systemd
// JobRemoved names, when it is one of ours; null otherwise.
//
// This replaced a `podman events` follower, which reported container
// transitions directly but cost 53 MB resident to do it — podman is Go, and
// this shell watches four containers that are asleep almost all the time. The
// same transitions are visible on the session bus for free, because every one
// of them IS a systemd job: the socket wakes the proxy, the proxy's Requires=
// raises the container, StopWhenUnneeded lowers it again. busctl is C and
// costs 5.6 MB.
//
// The trade is deliberate: a JobRemoved says WHICH unit moved but not what it
// moved to, so unlike a podman event this cannot be applied on its own — it
// is a nudge to re-probe. That also makes it robust to the payload changing
// shape, since the probe remains the only thing that decides state.
function parseUnitEvent(line) {
    var text = String(line || "").trim();
    if (text === "")
        return null;
    var msg;
    try {
        msg = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!msg || msg.member !== "JobRemoved")
        return null;
    var data = msg.payload && msg.payload.data;
    if (!Array.isArray(data))
        return null;
    // JobRemoved is (u id, o job, s unit, s result).
    var unit = String(data[2] || "");
    return WATCHED_UNITS[unit] === true ? unit : null;
}

function stateText(svc) {
    if (!svc)
        return "";
    if (svc.pending === "starting")
        return "Starting…";
    if (svc.pending === "stopping")
        return "Stopping…";
    if (svc.running)
        return "Running — " + svc.portLabel;
    return "Armed — wakes on " + svc.portLabel;
}

function summaryText(runningCount, total) {
    if (runningCount <= 0)
        return "armed";
    return runningCount + " of " + total + " running";
}

function heroMeta(runningCount, total) {
    if (runningCount <= 0)
        return "All armed — services wake on connect";
    return summaryText(runningCount, total);
}

if (typeof module !== "undefined") {
    module.exports = {
        SERVICES: SERVICES,
        WATCHED_UNITS: WATCHED_UNITS,
        parseProbe: parseProbe,
        parseUnitEvent: parseUnitEvent,
        stateText: stateText,
        summaryText: summaryText,
        heroMeta: heroMeta
    };
}

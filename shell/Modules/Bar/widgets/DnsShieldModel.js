// DNS Shield model — pure logic for the family-DNS-helper widget (the chain
// built 2026-09-02: router DHCP hands this laptop out as the network's DNS,
// dnsmasq on 127.0.0.2 + the LAN address forwards everything that is not
// *.test to the uBlockDNS client on 127.0.0.1:53, which filters ads and the
// YouTube block rules over DoH; AdGuard 94.140.14.14 is the DHCP fallback
// for when this machine is off).
.pragma library

// Whether this machine serves its LAN is per-machine state
// (~/.config/dns-helper/serve names the interface; the probe reads its
// CURRENT address, so a changed reservation shows up truthfully) — the
// mini serves the office, the NUC backs up home, the MacBook serves
// nobody and just filters itself.
const FALLBACK_IP = "94.140.14.14";
const DASHBOARD_URL = "https://ublockdns.com/";

// One probe, key=value lines. Exit 3 upstream means "not the helper machine";
// parseProbe only ever sees exit-0 output.
function parseProbe(raw) {
    const st = {
        client: "",
        dnsmasq: "",
        bindClient: false,
        bindFwd: false,
        lanIps: [],
        lanBound: [],
        laptopDns: "",
        blockTest: ""
    };
    for (const line of String(raw || "").split("\n")) {
        const eq = line.indexOf("=");
        if (eq < 1)
            continue;
        const key = line.slice(0, eq).trim();
        const value = line.slice(eq + 1).trim();
        switch (key) {
        case "client":
            st.client = value;
            break;
        case "dnsmasq":
            st.dnsmasq = value;
            break;
        case "bind_client":
            st.bindClient = value === "yes";
            break;
        case "bind_fwd":
            st.bindFwd = value === "yes";
            break;
        case "lan_ips":
            st.lanIps = value.split(/\s+/).filter(Boolean);
            break;
        case "lan_bound":
            st.lanBound = value.split(/\s+/).filter(Boolean);
            break;
        case "laptop_dns":
            st.laptopDns = value;
            break;
        case "block_test":
            st.blockTest = value;
            break;
        }
    }
    return st;
}

// Healthy = every link of the chain answers AND the live probe proves a
// blocked domain actually comes back blackholed. The block test is the one
// that matters: it caught resolved silently failing over to AdGuard on the
// very first day.
function chainHealthy(st) {
    return st.client === "active" && st.dnsmasq === "active" && st.bindClient && st.blockTest === "0.0.0.0";
}

// Where do THIS machine's own lookups go? (The LAN is served regardless.)
//   filtered — through the helper chain
//   fallback — AdGuard answered a renewal race; ads blocked, YouTube not
//   bypassed — something else entirely (a manual DNS switch)
function laptopVerdict(st) {
    if (st.laptopDns === "127.0.0.2" || st.laptopDns === "127.0.0.1" || st.lanIps.indexOf(st.laptopDns) !== -1)
        return "filtered";
    if (st.laptopDns === FALLBACK_IP)
        return "fallback";
    return st.laptopDns === "" ? "unknown" : "bypassed";
}

function heroMeta(st) {
    if (!st)
        return "Probing…";
    if (chainHealthy(st))
        return st.lanBound.length > 0 ? "Protecting the network" : "Filtering locally — not serving a LAN";
    if (st.client !== "active")
        return "Client down — network on AdGuard fallback";
    if (st.blockTest !== "" && st.blockTest !== "0.0.0.0")
        return "Chain up but NOT blocking — check rules";
    return "Degraded — check the chain";
}

// ---------------------------------------------------------------- categories
// The toggle half of the widget, fed by `dns-filter status --json` (see
// bin/dns-filter for the API this stands on). Kept apart from the chain probe
// above on purpose: the chain is local and answers in milliseconds, while this
// is a round trip to uBlockDNS, and folding the two would have made the panel
// open at the speed of the network.

// The script always emits parseable JSON, including for its own failures, so
// null here means something ate the output entirely — a missing binary, a
// machine with no profile — not a filter that is off.
function parseFilters(raw) {
    const text = String(raw || "").trim();
    if (text === "")
        return null;
    try {
        const value = JSON.parse(text);
        return value && typeof value === "object" ? value : null;
    } catch (e) {
        return null;
    }
}

// Local wall-clock HH:MM. Deliberately not Qt.formatDateTime: this file is a
// .pragma library and has no QML context to borrow one from.
function untilText(epoch) {
    const at = Number(epoch) || 0;
    if (at <= 0)
        return "";
    const d = new Date(at * 1000);
    return "until " + String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
}

function categoryRows(filters) {
    if (!filters || !filters.ok || !Array.isArray(filters.categories))
        return [];
    return filters.categories.map(function (c) {
        const until = Number(c.until) || 0;
        return {
            id: String(c.id),
            label: String(c.label),
            on: c.on === true,
            until: until,
            // Three states worth distinguishing, because "off" and "off until
            // half past" are very different things to see on a family filter.
            caption: c.on === true ? "Blocked" : (until > 0 ? "Open " + untilText(until) : "Not blocked")
        };
    });
}

// Domains punched through every blocklist with an `@@||domain^` rule. Listed
// in the panel, each with its own remove button, because a hole you cannot
// see is a hole you never close — t.co had to be opened for X's links to work
// at all (2026-09-06).
function allowedList(filters) {
    if (!filters || !filters.ok)
        return [];
    return Array.isArray(filters.allowed) ? filters.allowed : [];
}

function categoriesSummary(filters) {
    if (!filters)
        return "";
    if (!filters.ok)
        return filters.error ? String(filters.error) : "Could not read the filters";
    const rows = categoryRows(filters);
    const open = rows.filter(function (r) {
        return !r.on;
    });
    if (open.length === 0)
        return "ALL ON";
    return open.length + " OPEN";
}

// The header's right-hand verdict. This is the single fact the five CHAIN
// rows existed to deliver — everything else in them described the machine's
// role on the LAN, which never changed between one panel open and the next.
//
// `laptopVerdict` is the honest source: a machine can have a perfectly
// healthy chain and still be resolving through Google because somebody
// switched it in the network panel, and that is exactly the state worth
// showing at the top.
function deviceStatus(st) {
    if (!st)
        return {
            label: "…",
            ok: true
        };
    switch (laptopVerdict(st)) {
    case "filtered":
        return {
            label: "FILTERED",
            ok: true
        };
    case "fallback":
        return {
            label: "FALLBACK",
            ok: false
        };
    case "bypassed":
        return {
            label: "BYPASSED",
            ok: false
        };
    default:
        return {
            label: "UNKNOWN",
            ok: false
        };
    }
}

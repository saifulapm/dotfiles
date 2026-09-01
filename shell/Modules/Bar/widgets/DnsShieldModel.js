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
    return "Degraded — see rows";
}

function rows(st) {
    if (!st)
        return [];
    const laptop = laptopVerdict(st);
    return [{
            label: "Filtering client",
            detail: "ublockdns.service — 127.0.0.1:53",
            ok: st.client === "active" && st.bindClient,
            state: st.client === "active" ? (st.bindClient ? "Active" : "Active, port missing") : st.client || "unknown"
        }, {
            label: "Forwarder",
            detail: "dnsmasq — 127.0.0.2, *.test stays local",
            ok: st.dnsmasq === "active" && st.bindFwd,
            state: st.dnsmasq === "active" ? (st.bindFwd ? "Active" : "Active, port missing") : st.dnsmasq || "unknown"
        }, {
            label: "Serving the LAN",
            detail: st.lanBound.length > 0 ? st.lanBound.join(", ") + ":53 — point the router's DNS here" : st.lanIps.length > 0 ? st.lanIps.join(", ") + " has no listener" : "no ~/.config/dns-helper/serve",
            ok: st.lanBound.length > 0 || st.lanIps.length === 0,
            state: st.lanBound.length > 0 ? "Listening" : st.lanIps.length > 0 ? "Interface up, not bound" : "Self-filter only"
        }, {
            label: "Live block test",
            detail: "youtube.com through the client",
            ok: st.blockTest === "0.0.0.0",
            state: st.blockTest === "0.0.0.0" ? "Blocked" : (st.blockTest === "" ? "No answer" : "RESOLVING — " + st.blockTest)
        }, {
            label: "This laptop",
            detail: st.laptopDns === "" ? "no DNS server known" : "using " + st.laptopDns,
            ok: laptop === "filtered",
            state: laptop === "filtered" ? "Filtered" : laptop === "fallback" ? "AdGuard fallback" : laptop === "bypassed" ? "Bypassed" : "Unknown"
        }];
}

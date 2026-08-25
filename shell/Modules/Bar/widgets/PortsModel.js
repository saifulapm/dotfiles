// Ports model — the filtering, URL building and prose behind the ports
// widget, as pure functions so they can be checked under node
// (PortsModel.test.js) without a Quickshell runtime.
//
// Input is bin/ports' TSV, one listener per line:
//
//   port<TAB>bind<TAB>scope<TAB>pid<TAB>comm<TAB>cwd<TAB>start<TAB>owner<TAB>unit<TAB>label
//
// `scope` is where the socket can be reached from and `start` is the process
// start time that makes a kill safe against PID reuse — bin/ports' header
// explains both.

// Ports whose service speaks something other than HTTP, so the panel does not
// offer to open them in a browser. Not exhaustive and does not need to be:
// being wrong here costs one browser tab that says nothing, and the list
// covers everything this machine actually runs.
var NON_HTTP_PORTS = [22, 25, 53, 465, 587, 993, 995, 1025, 3306, 5432, 6379, 5355];

function parseRows(raw) {
    var rows = [];
    var lines = String(raw || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        if (!lines[i])
            continue;
        var c = lines[i].split("\t");
        var port = parseInt(c[0], 10);
        if (!isFinite(port) || port <= 0)
            continue;
        rows.push({
            port: port,
            bind: String(c[1] || ""),
            scope: String(c[2] || ""),
            pid: Number(c[3]) || 0,
            comm: String(c[4] || ""),
            cwd: String(c[5] || ""),
            start: String(c[6] || "0"),
            owner: String(c[7] || "system"),
            unit: String(c[8] || ""),
            label: String(c[9] || ""),
            order: rows.length
        });
    }
    return rows;
}

// A listener the machine DECLARES, as opposed to one you started.
//
// This is the distinction the panel is actually about. Every permanent thing
// on this machine — caddy on 80/443, the mailpit and database proxies, dnsmasq
// on 53, sshd, tailscale, dufs — is either socket-activated by a systemd unit
// or a system daemon we cannot attribute. What is left is what you launched:
// the `pnpm dev`, the `php artisan serve`, the throwaway http.server. Sixteen
// rows of permanent plumbing above the one row you opened the panel to see is
// not a listing, it is a haystack (user call 2026-08-21).
//
// bin/ports fills `unit` from `systemctl list-sockets` and from the process's
// own cgroup, and only when the process is that unit's MainPID — so a dev
// server started inside a terminal does not inherit the terminal's unit and
// get mistaken for infrastructure.
function isDeclared(row) {
    if (!row)
        return false;
    return row.unit !== "" || row.owner !== "self";
}

// Whether this row's process belongs to us, and can therefore be stopped
// from here. Everything else is listed but read-only — bin/ports refuses it
// anyway, and the panel should not offer what will be refused.
function isKillable(row) {
    return !!row && row.owner === "self" && row.pid > 0 && row.start !== "0";
}

function isHttp(row) {
    return !!row && NON_HTTP_PORTS.indexOf(row.port) === -1;
}

// Reachable from beyond this machine. The panel marks these, because a dev
// server bound to 0.0.0.0 on a café network is the one thing in this list
// worth noticing.
function isExposed(row) {
    return !!row && (row.scope === "any" || row.scope === "lan");
}

// Exposed AND yours — the only combination that deserves the bar's warning
// tint. A declared service bound wide (sshd, the clipboard socket) is in the
// manifest on purpose; an undeclared process on 0.0.0.0 is the accident the
// warning exists for.
function isExposedMine(row) {
    return isExposed(row) && !isDeclared(row);
}

function scopeLabel(row) {
    switch (row ? row.scope : "") {
    case "loopback":
        return "this machine only";
    case "tailnet":
        return "tailnet";
    case "lan":
        return "local network";
    case "any":
        return "every interface";
    default:
        return "";
    }
}

// The URL to open or copy. Loopback and wildcard binds are addressed as
// localhost — a browser pointed at 0.0.0.0 works by accident on Linux and
// not at all elsewhere, and "localhost" is what a person would have typed.
// A specific address (tailnet, LAN) is used as given, because that IS the
// interesting thing about it.
function urlFor(row) {
    if (!row || !isHttp(row))
        return "";
    var host;
    if (row.scope === "loopback" || row.scope === "any")
        host = "localhost";
    else
        host = row.bind;
    if (!host)
        return "";
    // 443 is the only port here that implies TLS; the dev proxy on this
    // machine terminates HTTPS there.
    var scheme = row.port === 443 ? "https" : "http";
    var authority = (scheme === "https" && row.port === 443) || (scheme === "http" && row.port === 80) ? host : host + ":" + row.port;
    return scheme + "://" + authority;
}

// Everything a query is allowed to hit.
//
// `unit` is in here for a specific reason: it is how you reach a hidden
// service by the name you think of it by. The database proxy is "mysql" in
// anyone's head and 3306 only on a good day, and a filter that hides a row
// has to leave a way to ask for it that does not require remembering a port
// number.
function haystack(row) {
    return [row.port, row.comm, row.label, row.cwd, row.scope, row.bind, row.unit].join(" ").toLowerCase();
}

function matches(row, query) {
    var needle = String(query || "").trim().toLowerCase();
    if (!needle)
        return true;
    var terms = needle.split(/\s+/);
    var hay = haystack(row);
    for (var i = 0; i < terms.length; i++) {
        if (hay.indexOf(terms[i]) === -1)
            return false;
    }
    return true;
}

// Scope, ordered by how far the socket reaches. Used to collapse a port that
// is listening on several addresses down to its widest one.
var SCOPE_RANK = { loopback: 0, tailnet: 1, lan: 2, any: 3 };

// One row per PORT, not per bind address.
//
// A service commonly listens on several addresses — sshd on 0.0.0.0 and
// [::], caddy on loopback plus both tailnet addresses — and bin/ports
// correctly reports each, because they are genuinely different sockets. A
// LIST does not want that: three rows saying 8787 is not three facts, it is
// one fact rendered badly.
//
// The group keeps the widest scope (that is the honest answer to "who can
// reach this"), and prefers a member that `ss` could attribute to a process,
// so the one loopback socket ss can name is not lost behind two tailnet rows
// it cannot.
function groupByPort(rows) {
    var byPort = {};
    var order = [];
    var all = Array.isArray(rows) ? rows : [];

    for (var i = 0; i < all.length; i++) {
        var row = all[i];
        var seen = byPort[row.port];
        if (!seen) {
            byPort[row.port] = Object.assign({}, row, { binds: 1 });
            order.push(row.port);
            continue;
        }
        seen.binds += 1;
        if ((SCOPE_RANK[row.scope] || 0) > (SCOPE_RANK[seen.scope] || 0)) {
            seen.scope = row.scope;
            seen.bind = row.bind;
        }
        // An attributable member wins the identity: it is the only one that
        // can be acted on or named.
        if (seen.pid === 0 && row.pid > 0) {
            seen.pid = row.pid;
            seen.comm = row.comm;
            seen.cwd = row.cwd;
            seen.start = row.start;
            seen.owner = row.owner;
            seen.label = row.label;
        }
        if (seen.unit === "" && row.unit !== "")
            seen.unit = row.unit;
    }
    return order.map(function (port) {
        return byPort[port];
    });
}

// Ours first, then by port number.
//
// The ordering is the opinion this panel has: a list of listeners sorted
// purely by number buries the `pnpm dev` you are looking for under sshd,
// dnsmasq and the mail proxies. What you started is what you came to find.
// The list the panel draws.
//
// With no query this is exactly what you started — nothing else. An earlier
// version also forced through any DECLARED service bound beyond loopback, to
// keep the exposure warning visible; that put sshd, llmnr and the clipboard
// socket on screen permanently in the warning colour, which is the noise this
// filter exists to remove. A declared wide bind is deliberate — it is in the
// manifest — and the warning it deserves belongs on the bar icon and its
// tooltip, which count every listener regardless of this filter. What the
// warning is FOR is an undeclared process on 0.0.0.0, and that is shown
// because it is undeclared.
//
// A query searches everything, grouped the same way. `showSystem` is the
// panel's toggle (default off): with it on, the declared rows join the
// no-query list instead of needing a search to reach.
function rank(rows, query, showSystem) {
    var needle = String(query || "").trim();
    return groupByPort(rows).filter(function (row) {
        if (!matches(row, needle))
            return false;
        return needle !== "" || showSystem === true || !isDeclared(row);
    }).sort(function (a, b) {
        var mine = (b.owner === "self" ? 1 : 0) - (a.owner === "self" ? 1 : 0);
        if (mine !== 0)
            return mine;
        return a.port - b.port;
    });
}

// "node · ~/Sites/laravel/shop" — the second line of a row. The home
// directory is abbreviated because the full path is usually wider than the
// card and the interesting part is the tail.
function detailText(row, home) {
    if (!row)
        return "";
    var parts = [];
    if (row.comm)
        parts.push(row.comm);
    if (row.cwd) {
        var path = row.cwd;
        var prefix = String(home || "");
        if (prefix && path.indexOf(prefix) === 0)
            path = "~" + path.slice(prefix.length);
        parts.push(path);
    } else if (row.owner !== "self") {
        parts.push("system service");
    }
    return parts.join(" · ");
}

function declaredCount(rows) {
    return groupByPort(rows).filter(isDeclared).length;
}

function plural(n, word) {
    return n + " " + word + (n === 1 ? "" : "s");
}

// The hero's second line. It never just says a number without saying what the
// number is OF — "16 listeners" over a list of one is the kind of quiet
// disagreement that makes someone stop trusting the panel.
function heroMeta(rows, shown, query, showSystem) {
    var all = groupByPort(rows);
    if (all.length === 0)
        return "Nothing listening";
    if (String(query || "").trim())
        return shown === all.length ? plural(all.length, "listener") : shown + " of " + plural(all.length, "listener");

    var hidden = showSystem === true ? 0 : declaredCount(all);
    var head = shown === 0 ? "Nothing you started" : plural(shown, "listener");
    return hidden > 0 ? head + " · " + plural(hidden, "service") + " hidden" : head;
}

// The tooltip counts everything, because the bar icon is the passive view and
// under-reporting there would hide the exposure warning it exists to carry.
function tooltipText(rows) {
    var all = groupByPort(rows);
    if (all.length === 0)
        return "Ports — nothing listening";
    var yours = all.filter(function (row) {
        return !isDeclared(row);
    }).length;
    var exposed = all.filter(isExposed).length;
    var text = "Ports — " + plural(all.length, "listener");
    text += yours > 0 ? ", " + yours + " yours" : ", none of them yours";
    if (exposed > 0)
        text += " · " + exposed + " reachable off this machine";
    return text;
}

// What a declared row is, for the one that gets shown because it is exposed.
function unitText(row) {
    if (!row || row.unit === "")
        return "";
    return row.unit.replace(/\.(socket|service)$/, "");
}

if (typeof module !== "undefined") {
    module.exports = {
        NON_HTTP_PORTS: NON_HTTP_PORTS,
        declaredCount: declaredCount,
        detailText: detailText,
        SCOPE_RANK: SCOPE_RANK,
        groupByPort: groupByPort,
        haystack: haystack,
        heroMeta: heroMeta,
        isDeclared: isDeclared,
        isExposed: isExposed,
        isExposedMine: isExposedMine,
        isHttp: isHttp,
        isKillable: isKillable,
        matches: matches,
        parseRows: parseRows,
        rank: rank,
        scopeLabel: scopeLabel,
        tooltipText: tooltipText,
        unitText: unitText,
        urlFor: urlFor
    };
}

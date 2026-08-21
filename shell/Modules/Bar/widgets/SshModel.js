// SSH host model — the ranking and filtering half of the ssh widget, as pure
// functions so they can be checked under node (SshModel.test.js) without a
// Quickshell runtime. bin/ssh-hosts is the gathering half; between them,
// nothing in the QML has to know what an ssh_config looks like.
//
// Input is that script's TSV, one host per line:
//
//   alias<TAB>hostname<TAB>user<TAB>port<TAB>proxyjump<TAB>lastUsed
//
// proxyjump is empty when there is none and lastUsed is 0 for a host never
// opened from here. Everything is already resolved by `ssh -G`, so this file
// never has to reason about Match blocks, wildcards or first-match-wins.

var DEFAULT_PORT = "22";

// Hosts that answer SSH but never give you a shell.
//
// A git forge alias is a TRANSPORT, not a machine: `Host github.com-work`
// exists so git picks a particular key for a particular account, and this
// config has three of them (github.com, -work, -project) all resolving to
// ssh.github.com:443 with different IdentityFiles. Opening a terminal on one
// gets you "successfully authenticated, but GitHub does not provide shell
// access" — so in a launcher whose entire verb is "open a terminal there",
// three of six rows were noise (user call 2026-08-21).
//
// They are FILTERED FROM THE DEFAULT LIST, NOT DELETED, and the distinction
// matters: typing "github" still finds them, because `ssh -T github.com-work`
// is exactly how you check which account a key belongs to. The rule is
// "not offered", not "not available".
//
// Matched on the RESOLVED hostname rather than the alias, so a `Host work`
// pointing at ssh.github.com is caught too and a machine you happened to call
// "github" is not.
var FORGE_HOSTS = ["github.com", "ssh.github.com", "gitlab.com", "altssh.gitlab.com", "bitbucket.org", "altssh.bitbucket.org", "codeberg.org", "git.sr.ht", "git.launchpad.net"];

function isForge(host) {
    if (!host)
        return false;
    var name = String(host.hostname || "").toLowerCase();
    if (!name)
        return false;
    for (var i = 0; i < FORGE_HOSTS.length; i++) {
        var forge = FORGE_HOSTS[i];
        if (name === forge || name.slice(-(forge.length + 1)) === "." + forge)
            return true;
    }
    return false;
}

function parseRows(raw) {
    var hosts = [];
    var lines = String(raw || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (!line)
            continue;
        var columns = line.split("\t");
        var alias = String(columns[0] || "").trim();
        if (!alias)
            continue;
        hosts.push({
            alias: alias,
            hostname: String(columns[1] || "").trim(),
            user: String(columns[2] || "").trim(),
            port: String(columns[3] || "").trim(),
            jump: String(columns[4] || "").trim(),
            lastUsed: Number(columns[5]) || 0,
            // Config order, kept so ties break the way the file reads
            // rather than alphabetically.
            order: hosts.length
        });
    }
    return hosts;
}

// "zoe@example.net · port 2222 · via mini", with the parts that say nothing
// left off.
//
// A user is always rendered WITH its host ("saiful@mini"), even where the
// hostname just repeats the alias the row is titled with: "saiful@mini" reads
// as the thing you would type, and a bare "saiful" reads as nothing at all.
// The repetition is only worth suppressing when there is no user to attach
// the host to — then the hostname alone would genuinely be an echo of the
// title, and the row is better off with a blank second line. A port of 22 is
// always left off; it is the default and every row would carry it.
function subtitle(host) {
    if (!host)
        return "";
    var target = String(host.hostname || "");
    var alias = String(host.alias || "");
    var parts = [];

    if (host.user)
        parts.push(host.user + "@" + (target || alias));
    else if (target && target !== alias)
        parts.push(target);

    if (host.port && host.port !== DEFAULT_PORT)
        parts.push("port " + host.port);
    if (host.jump)
        parts.push("via " + host.jump);
    return parts.join(" · ");
}

// Every field a query is allowed to hit, lowercased once per host per query.
function haystack(host) {
    return [host.alias, host.hostname, host.user, host.port, host.jump].join(" ").toLowerCase();
}

function matches(host, query) {
    var needle = String(query || "").trim().toLowerCase();
    if (!needle)
        return true;
    // Every whitespace-separated term must appear somewhere: "mini 22" and
    // "22 mini" find the same host, which is how every other filter surface
    // in this shell behaves.
    var terms = needle.split(/\s+/);
    var hay = haystack(host);
    for (var i = 0; i < terms.length; i++) {
        if (hay.indexOf(terms[i]) === -1)
            return false;
    }
    return true;
}

// How well a host answers the query, higher is better. The bands are wide
// apart so recency (added below as a fraction) can only ever break a tie
// WITHIN a band — a host you used yesterday must not outrank the one whose
// name you are actually typing.
function score(host, query) {
    var needle = String(query || "").trim().toLowerCase();
    if (!needle)
        return 0;
    var alias = String(host.alias || "").toLowerCase();
    var hostname = String(host.hostname || "").toLowerCase();

    if (alias === needle)
        return 500;
    if (alias.indexOf(needle) === 0)
        return 400;
    if (hostname.indexOf(needle) === 0)
        return 300;
    if (alias.indexOf(needle) !== -1)
        return 200;
    if (hostname.indexOf(needle) !== -1)
        return 100;
    // Matched only on user, port or jump host.
    return 50;
}

// The list the panel draws: filtered, then ordered.
//
// With no query this is recency-first — the point of the widget is that the
// three machines you actually use are the first three rows — and config order
// underneath for everything never opened. With a query, relevance leads and
// recency only separates equals.
function rank(hosts, query) {
    var needle = String(query || "").trim();
    var rows = (Array.isArray(hosts) ? hosts : []).filter(function (host) {
        if (!matches(host, needle))
            return false;
        // Forges are hidden until asked for by name. An empty query is the
        // list of places you can actually go.
        return needle !== "" || !isForge(host);
    });

    return rows.sort(function (a, b) {
        if (needle) {
            var byScore = score(b, needle) - score(a, needle);
            if (byScore !== 0)
                return byScore;
        }
        if (a.lastUsed !== b.lastUsed)
            return b.lastUsed - a.lastUsed;
        return a.order - b.order;
    });
}

function forgeCount(hosts) {
    return (Array.isArray(hosts) ? hosts : []).filter(isForge).length;
}

// Hosts you could actually get a shell on — the number both the hero and the
// tooltip lead with, because it is the number of things this widget can do.
function shellHostCount(hosts) {
    var rows = Array.isArray(hosts) ? hosts : [];
    return rows.length - forgeCount(rows);
}

function plural(n, word) {
    return n + " " + word + (n === 1 ? "" : "s");
}

// The hero's second line. With no query it counts what you can reach and then
// admits what it is not showing — a bare "3 hosts" over a config with six
// `Host` blocks is the kind of quiet disagreement that makes someone doubt
// the widget. The empty case is worded as a fact rather than an error: a
// machine with no ssh config is a perfectly ordinary machine.
function heroMeta(hosts, shown, query) {
    var rows = Array.isArray(hosts) ? hosts : [];
    if (rows.length === 0)
        return "No hosts in ~/.ssh/config";

    // A query searches everything, forges included, so it counts against the
    // whole config rather than against the filtered default.
    if (String(query || "").trim())
        return shown === rows.length ? plural(rows.length, "host") : shown + " of " + plural(rows.length, "host");

    var forges = forgeCount(rows);
    var reachable = plural(rows.length - forges, "host");
    return forges > 0 ? reachable + " · " + plural(forges, "git remote") + " hidden" : reachable;
}

function tooltipText(hosts) {
    var rows = Array.isArray(hosts) ? hosts : [];
    if (rows.length === 0)
        return "SSH — no hosts configured";
    var reachable = shellHostCount(rows);
    if (reachable === 0)
        return "SSH — only git remotes configured";
    return "SSH — " + plural(reachable, "host");
}

// Why a row that is on screen cannot be opened. Only ever non-empty for a
// forge, which only appears when it was searched for by name.
function noteText(host) {
    return isForge(host) ? "git remote — no shell" : "";
}

// The command the panel runs for a chosen row. `--` is what stops an alias
// that begins with a dash from being read as an option, and the array form
// means nothing is ever handed to a shell to re-split: an alias is a string
// from a config file, and this is the boundary where that stops mattering.
function connectCommand(host, terminal) {
    if (!host || !host.alias)
        return [];
    return [terminal || "foot-run", "--app-id=ssh-" + host.alias, "ssh", "--", host.alias];
}

if (typeof module !== "undefined") {
    module.exports = {
        DEFAULT_PORT: DEFAULT_PORT,
        FORGE_HOSTS: FORGE_HOSTS,
        connectCommand: connectCommand,
        forgeCount: forgeCount,
        haystack: haystack,
        heroMeta: heroMeta,
        isForge: isForge,
        matches: matches,
        noteText: noteText,
        parseRows: parseRows,
        rank: rank,
        score: score,
        shellHostCount: shellHostCount,
        subtitle: subtitle,
        tooltipText: tooltipText
    };
}

// Password-store model — the matching and ranking behind the pass widget, as
// pure functions so they can be checked under node (PassModel.test.js).
//
// Input is bin/pass-store's `list` output: one entry name per line, already
// ordered recently-used-first. Those names are the store's filenames with the
// .gpg stripped — plaintext on disk, because gpg encrypts contents and not
// names, which is exactly why the store is a separate private repo.
//
// NOTHING IN THIS FILE EVER SEES A SECRET. It sorts names. Every action on an
// entry is bin/pass-store's job and goes through `pass` itself.

function parseEntries(raw) {
    var entries = [];
    var lines = String(raw || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var name = String(lines[i] || "").trim();
        if (!name)
            continue;
        var cut = name.lastIndexOf("/");
        entries.push({
            name: name,
            folder: cut === -1 ? "" : name.slice(0, cut),
            leaf: cut === -1 ? name : name.slice(cut + 1),
            // bin/pass-store already emitted these recency-first; keeping the
            // index is how that survives a filter.
            order: entries.length
        });
    }
    return entries;
}

// Does every character of `needle` appear in `hay`, in order? This is what
// makes "ghb" find "web/github.com" — the behaviour the upstream plugin
// advertises and the reason this is not a plain substring filter.
//
// Deliberately NOT scored by gap size or clustering. A password store holds
// tens of entries, not thousands, and the ranking below already puts exact
// and prefix matches above every subsequence hit — adding fuzzy-match
// scoring on top would reorder the tail for no gain anyone could perceive.
function subsequence(hay, needle) {
    var h = 0;
    for (var n = 0; n < needle.length; n++) {
        var found = -1;
        while (h < hay.length) {
            if (hay.charAt(h) === needle.charAt(n)) {
                found = h;
                h++;
                break;
            }
            h++;
        }
        if (found === -1)
            return false;
    }
    return true;
}

function matches(entry, query) {
    var needle = String(query || "").trim().toLowerCase();
    if (!needle)
        return true;
    return subsequence(String(entry.name || "").toLowerCase(), needle);
}

// Bands, widest first. Recency breaks ties inside a band and never across
// one: a store you touched yesterday must not outrank the name being typed.
function score(entry, query) {
    var needle = String(query || "").trim().toLowerCase();
    if (!needle)
        return 0;
    var name = String(entry.name || "").toLowerCase();
    var leaf = String(entry.leaf || "").toLowerCase();

    if (leaf === needle || name === needle)
        return 500;
    if (leaf.indexOf(needle) === 0)
        return 400;
    if (name.indexOf(needle) === 0)
        return 300;
    if (name.indexOf(needle) !== -1)
        return 200;
    // Matched only as a subsequence — "ghb" in "web/github.com".
    return 100;
}

function rank(entries, query) {
    var rows = (Array.isArray(entries) ? entries : []).filter(function (entry) {
        return matches(entry, query);
    });
    var needle = String(query || "").trim();

    return rows.sort(function (a, b) {
        if (needle) {
            var byScore = score(b, needle) - score(a, needle);
            if (byScore !== 0)
                return byScore;
        }
        // bin/pass-store handed these over recency-first, so index order IS
        // recency order.
        return a.order - b.order;
    });
}

function heroMeta(total, shown, query) {
    if (total === 0)
        return "The store is empty";
    if (String(query || "").trim() && shown !== total)
        return shown + " of " + total + " entries";
    return total + (total === 1 ? " entry" : " entries");
}

function tooltipText(total) {
    if (total <= 0)
        return "Passwords — the store is empty";
    return "Passwords — " + total + (total === 1 ? " entry" : " entries");
}

// The keys the panel advertises, filtered to what this machine can actually
// do — `caps` from bin/pass-store says whether pass-otp and wtype are here,
// and a shortcut that will only ever report a missing package should not be
// on screen.
function actionHints(caps) {
    var can = Array.isArray(caps) ? caps : [];
    var hints = ["Enter copies"];
    hints.push("Alt+U username");
    if (can.indexOf("otp") !== -1)
        hints.push("Alt+O code");
    if (can.indexOf("type") !== -1)
        hints.push("Ctrl+Enter types");
    hints.push("Alt+E edits");
    // The whole chain — screenshot-qr, zbarimg, pass-otp — or nothing; see
    // qr_available in bin/pass-store.
    if (can.indexOf("qr") !== -1)
        hints.push("Alt+N scans a QR");
    return hints.join(" · ");
}

// ------------------------------------------------------------- the captured QR
//
// Everything below reads `pass-store otp-scan`'s answer, which is FOUR FIELDS
// and never the URI: issuer, account, type, digits. That is deliberate and it
// is the reason this file can still say, at the top, that it never sees a
// secret — the shell learns what the code IS ABOUT, and `pass` is the only
// thing that ever holds what it is.

// Long enough for "saiful.apm@gmail.com", short enough that a hostile QR
// cannot push the panel off the screen.
function captureField(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim();
    return value.length > 64 ? value.substring(0, 63) + "…" : value;
}

function parseCapture(raw) {
    var line = String(raw || "").split("\n")[0] || "";
    var parts = line.split("\t");
    if (parts.length < 4)
        return null;
    // A type this does not recognise means the line did not come from
    // otp-scan, so nothing here should be trusted to describe it.
    var type = String(parts[2] || "").trim().toUpperCase();
    if (type !== "TOTP" && type !== "HOTP")
        return null;
    var issuer = captureField(parts[0]);
    var account = captureField(parts[1]);
    if (!issuer && !account)
        return null;
    var digits = parseInt(parts[3], 10);
    return {
        issuer: issuer,
        account: account,
        type: type,
        digits: digits >= 6 && digits <= 10 ? digits : 6
    };
}

// The issuer is the thing you recognise — "GitHub" — so it leads. A QR whose
// label carried no issuer names the account instead rather than a placeholder
// nobody can act on.
function captureTitle(capture) {
    if (!capture)
        return "";
    return capture.issuer || capture.account || "Captured code";
}

function captureMeta(capture) {
    if (!capture)
        return "";
    var parts = [];
    // Only when the title is not already the account — repeating it would
    // read as two different facts.
    if (capture.issuer && capture.account)
        parts.push(capture.account);
    parts.push(capture.type);
    parts.push(capture.digits + " digits");
    return parts.join(" · ");
}

// One element of a store path, from a name written by whoever made the QR.
//
// The slash is the one that matters: an issuer of "a/b" would quietly create
// a folder. Whitespace becomes a dash to match how the entries imported from
// Google Authenticator were named — multi-word issuers arrived hyphenated or
// joined, never spaced. It is a SUGGESTION in an editable field, so this
// follows the existing convention rather than inventing a rule.
//
// The same rules, deliberately, as bin/otp-import's pass_path: slash and space
// to a dash, unprintables dropped, dots and dashes trimmed off both ends. A
// code imported in bulk from Google Authenticator and one captured off the
// screen should land at the same path, or the store grows two conventions.
function pathSegment(text) {
    return String(text || "").replace(/[\/\\]+/g, "-").replace(/[\x00-\x1f\x7f]/g, "").replace(/\s+/g, "-")
    // A leading dot hides the file from `pass ls`; a leading dash reads as a
    // flag to everything that later handles the name.
    .replace(/^[.\-]+/, "").replace(/[.\-]+$/, "").trim();
}

// otp/<Issuer>/<account>, which is what the 21 entries already in this store
// look like — and otp/<Issuer> alone for the six of them that carry no
// account, because a QR with only an issuer should land beside those rather
// than invent a second convention.
function suggestedPath(capture) {
    if (!capture)
        return "";
    var issuer = pathSegment(capture.issuer);
    var account = pathSegment(capture.account);
    var parts = ["otp"];
    if (issuer)
        parts.push(issuer);
    if (account && account !== issuer)
        parts.push(account);
    // bin/otp-import's fallback, so a nameless code has one name and not two.
    if (parts.length === 1)
        parts.push("unnamed");
    return parts.join("/");
}

// What the panel is allowed to do with the path in the box. `exists` is not
// pedantry: `pass otp insert` would REPLACE that entry, taking its password
// with it, and pass's own "overwrite?" prompt answers itself when stdin is a
// pipe. bin/pass-store refuses it too — this is the copy that can say so
// before the key is pressed rather than after.
function pathState(path, names) {
    var value = String(path || "").trim();
    if (!value)
        return "empty";
    if (value.charAt(0) === "/" || value.charAt(value.length - 1) === "/" || value.indexOf("//") !== -1)
        return "invalid";
    if (/(^|\/)\.\.?(\/|$)/.test(value))
        return "invalid";
    var list = Array.isArray(names) ? names : [];
    for (var i = 0; i < list.length; i++)
        if (list[i] === value)
            return "exists";
    return "ok";
}

function pathNotice(state, path) {
    if (state === "exists")
        return "“" + String(path || "").trim() + "” already exists — choose it from the list to append instead";
    if (state === "invalid")
        return "That is not a path inside the store";
    return "";
}

// The footers for the two captured screens. Written as sentences about the
// code rather than about the store, because that is what is on screen.
function captureHints(mode) {
    if (mode === "new")
        return "Enter creates the entry · Esc goes back";
    return "Enter adds the code to the entry · Alt+N a new entry · Esc discards it";
}

function parseCaps(raw) {
    return String(raw || "").split("\n").map(function (line) {
        return line.trim();
    }).filter(function (line) {
        return line !== "";
    });
}

if (typeof module !== "undefined") {
    module.exports = {
        actionHints: actionHints,
        captureHints: captureHints,
        captureMeta: captureMeta,
        captureTitle: captureTitle,
        heroMeta: heroMeta,
        matches: matches,
        parseCaps: parseCaps,
        parseCapture: parseCapture,
        parseEntries: parseEntries,
        pathNotice: pathNotice,
        pathSegment: pathSegment,
        pathState: pathState,
        rank: rank,
        score: score,
        subsequence: subsequence,
        suggestedPath: suggestedPath,
        tooltipText: tooltipText
    };
}

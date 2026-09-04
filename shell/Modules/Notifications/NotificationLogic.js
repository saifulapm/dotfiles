// Non-visual half of the notification module: body sanitising, snapshotting,
// history parsing and popup placement. Near-verbatim port of omarchy's
// shell/plugins/notifications/NotificationLogic.js, plus the
// window-matching helpers click-to-focus needs on niri (they shell out to a
// Hyprland helper instead).
//
// Kept free of QML types so it can be exercised under node.

function isChromiumDerived(app, appIcon) {
    var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase();
    return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0 || source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0 || source.indexOf("opera") >= 0;
}

// True when a `<...>` run is an image tag, so the name is read the way Qt's
// parser reads it: after the `<`, the leading run of letters and digits.
//
// Skip everything up to that run rather than matching the separator, because
// there is no JavaScript expression for what Qt skips. QQuickStyledText calls
// skipSpace(), which is QChar::isSpace(), and that set is NOT `\s`: Qt counts
// U+0085 NEL and `\s` does not, while `\s` counts U+FEFF and Qt does not. A
// name read with `\s` therefore misses a tag written as `<`, U+0085, `img` —
// Qt skips the NEL, reads `img` and issues the GET, while the regex finds no
// name at all and keeps the tag.
//
// Over-skipping is the safe direction. It can only classify more runs as
// images, and dropping a run never manufactures a tag: a dropped run joins two
// stretches of text that each contain no `<`.
function isImageTag(tag) {
    var name = /^<[^A-Za-z0-9]*([A-Za-z0-9]+)/.exec(tag);
    return !!name && name[1].toLowerCase() === "img";
}

// The body renders as StyledText (NotificationCard), and StyledText honours
// <img src> — a remote src makes the shell issue an unauthenticated GET with
// no user action, so image tags go before the renderer sees them.
//
// Work in WHOLE TAGS, never in substrings of one. A `<` opens a tag that runs
// to the next `>`, nested `<` and all, and only a tag whose own name is `img`
// is dropped.
//
// That is the conservative bound, not Qt's exact one: Qt lets a `>` inside a
// quoted attribute value pass without closing the tag, so a Qt tag can be
// longer than the run taken here. Do NOT "correct" this to match Qt. Taking
// the shorter run only ever splits one Qt tag into several, and a split can
// only expose an `<img` to be dropped, never hide one — whereas honouring
// quotes would let `<b title="a>b"><img src="http://host/x.png">` through.
//
// Deleting a substring is what made the previous `/<img[^>]*>/gi` here unsafe.
// Given
//
//   <im<img src="http://a/decoy.png">g src="http://a/beacon.png">
//
// Qt reads ONE malformed tag named `im` and renders nothing, but removing the
// inner match closes the surviving halves up into `<img src=".../beacon.png">`
// — a live tag the input never contained. The stripper was manufacturing the
// very thing it exists to remove.
//
// Because every `<` opens a tag, the text between tags never contains one, so
// dropping a tag cannot splice its neighbours into a new one. One pass is
// therefore sufficient, with no re-scanning and no input bound to police.
function stripImageTags(text) {
    var out = "";
    var i = 0;

    while (i < text.length) {
        var open = text.indexOf("<", i);
        if (open === -1) {
            out += text.slice(i);
            break;
        }

        out += text.slice(i, open);

        // An unterminated tag at the end of the string still reaches the
        // renderer, which closes it itself, so treat the remainder as one tag.
        var close = text.indexOf(">", open);
        var tag = close === -1 ? text.slice(open) : text.slice(open, close + 1);

        if (!isImageTag(tag))
            out += tag;
        i = close === -1 ? text.length : close + 1;
    }

    return out;
}

// Chromium and its forks prefix the body with the origin ("mail.google.com"),
// which the card already implies — strip it, and drop inline <img> markup
// nothing here can render.
function sanitizeBody(body, app, appIcon) {
    var text = stripImageTags(String(body || ""));
    if (!isChromiumDerived(app, appIcon))
        return text;

    return text.replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "").replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "");
}

// What the card renders, and the LAST thing to touch the string before Qt
// parses it. The newline rewrite lives here rather than in the card because it
// inserts `<br/>` into text stripImageTags chose to KEEP, and a kept tag may
// hold a `<` of its own: `<x`, newline, `<img src="http://…">` is one tag named
// `x` to both the stripper and Qt, until the rewrite splits it into `<x<br/>`
// and a live image tag the input never contained. So strip again after, and
// what Qt parses is what was checked last.
function styledBody(body, app, appIcon) {
    return stripImageTags(sanitizeBody(body, app, appIcon).replace(/\r\n|\r|\n/g, "<br/>"));
}

// A sender that opens its summary with a glyph and two spaces has already
// drawn its own icon — the icon slot would just repeat it.
function summaryStartsWithGlyph(summary) {
    var text = String(summary || "").replace(/^\s+/, "");
    if (!text)
        return false;

    var offset = 1;
    var first = text.charCodeAt(0);
    if (first >= 0xd800 && first <= 0xdbff && text.length > 1)
        offset = 2;

    var spaces = 0;
    while (offset < text.length && text.charAt(offset) === " ") {
        spaces++;
        offset++;
    }

    return spaces >= 2;
}

// DND bypass: only what we trust to be intentional and rare.
//   - app_name "qshell": one of our own action toasts (this shell's scripts
//     all send with `notify-send -a qshell`). The user just did the thing;
//     their feedback should show. Upstream's equivalent is "omarchy-action".
//   - urgency=critical AND app_name "notify-send": bare-CLI emergency alerts.
//     Chat apps brand themselves (Discord/Slack), so they fall outside this.
function shouldBypassDnd(notification, criticalUrgency) {
    var appName = String((notification && notification.appName) || "");
    if (appName === "qshell")
        return true;
    return appName === "notify-send" && notification && notification.urgency === criticalUrgency;
}

// Ephemeral senders never reach the history buckets: "notify-send" is the
// CLI default (the sender didn't bother declaring an identity) and "qshell"
// is our own action feedback.
function isEphemeralApp(appName) {
    var name = String(appName || "");
    return name === "notify-send" || name === "qshell";
}

function stringHint(hints, name) {
    try {
        if (hints) {
            var value = hints[name];
            if (value !== undefined && value !== null)
                return String(value);
        }
    } catch (e) {}
    return "";
}

function glyphFromHints(hints) {
    return stringHint(hints, "qshell-glyph");
}

// What to run when the card is clicked: a JSON argv array, sent as
// `--hint=string:qshell-exec-argv:<json>`. Carrying the action as DATA is what
// makes it survive: it travels with the row into the popup files and the
// history, so a toast restored after a shell restart clicks through exactly
// like a live one. A libnotify action cannot — its identifier only means
// something to the server generation that handed it out, and the sender is
// still blocked waiting on an id from a server that no longer exists.
//
// An ARGV, not a shell string (omarchy 07443f3): the old `qshell-exec` hint was
// free-form and safe only while every sender quoted every interpolated value
// perfectly, and one slip is command execution — a hostile video title forged a
// yt-dlp output record and put an mpv option in the click command. Rows still
// carrying the old role simply lose their click; the 100-row cap ages them out.
function execArgvFromHints(hints) {
    return stringHint(hints, "qshell-exec-argv");
}

// Turn a persisted qshell-exec-argv into a runnable argv, or null. STRUCTURAL
// only: it fails closed on a malformed hint (not an array, empty, a non-string
// element, or a leading-dash program that the runner would read as an option).
// It does not judge intent — a well-formed ["bash", "-c", …] is accepted, and
// nothing here is a privilege boundary, since any process on the session bus
// can set the hint at all, which already means same-uid code execution.
function parseExecArgv(value) {
    var text = String(value || "");
    if (!text)
        return null;

    var parsed;
    try {
        parsed = JSON.parse(text);
    } catch (e) {
        return null;
    }

    if (!Array.isArray(parsed) || parsed.length === 0)
        return null;
    for (var i = 0; i < parsed.length; i++) {
        if (typeof parsed[i] !== "string")
            return null;
    }
    if (!parsed[0] || parsed[0].charAt(0) === "-")
        return null;
    return parsed;
}

// Files a notification is ABOUT, for dragging out of its card — the first and
// strongest of the three payloads dragPayload can produce.
//
// The first source is the exec-argv hint rather than a hint of its own, so it
// works on every row exec-argv already reaches: live toasts, replayed
// history, rows restored across a shell restart. Only commands whose
// arguments ARE the subject files qualify: yazi-yank-clipboard (Taildrop
// arrivals) and mpv (the ytdlp download toast). An allowlist, not "any
// absolute argument" — crash-watch's argv carries the crashed binary's path,
// and a crash toast must not drag /usr/bin/foo around.
var DRAG_CARRIERS = {
    "yazi-yank-clipboard": true,
    "mpv": true
};

// An absolute path, or "" for an icon-theme name, an image:// provider URL,
// or anything else with no file behind it.
function localFile(value) {
    var v = String(value || "");
    if (v.indexOf("file://") === 0)
        v = decodeURIComponent(v.substring(7));
    return v.charAt(0) === "/" ? v : "";
}

// Absolute app_icon paths that are DECORATION rather than a file the
// notification is about. Two kinds, and both have to be excluded before
// app_icon can be treated as a subject:
//
//   - Icon-theme assets. A sender that names its icon by path rather than by
//     theme name hands over /usr/share/icons/…/thunderbird.png, and dragging
//     a notification must not scatter application icons around.
//   - Anything under /tmp. Chromium-family senders pass the AVATAR as an
//     app_icon file in a scoped temporary directory they delete when the
//     notification closes (the same behaviour Notifs.qml caches around), so
//     every web-chat notification would otherwise drag the sender's profile
//     picture. That is never what someone dragging a message wants, and the
//     file is gone moments later anyway.
//
// Deliberately a path test rather than a sender test: a web notification's
// app_name is the origin ("web.whatsapp.com"), so isChromiumDerived does not
// recognise it, and the thing that identifies an avatar is where it lives.
var ICON_ASSET_HINTS = ["/icons/", "/pixmaps/", "/share/app-info/"];

function isDecorationPath(path) {
    var p = String(path || "");
    if (p.indexOf("/tmp/") === 0)
        return true;
    for (var i = 0; i < ICON_ASSET_HINTS.length; i++) {
        if (p.indexOf(ICON_ASSET_HINTS[i]) !== -1)
            return true;
    }
    return false;
}

function dragPaths(execArgv, image, appIcon) {
    var argv = parseExecArgv(execArgv);
    if (argv && DRAG_CARRIERS[argv[0].split("/").pop()]) {
        var paths = [];
        for (var i = 1; i < argv.length; i++) {
            if (argv[i].charAt(0) === "/")
                paths.push(argv[i]);
        }
        if (paths.length > 0)
            return paths;
    }

    // The notification's own image, which is what the hint is for.
    var img = localFile(image);
    if (img)
        return [img];

    // ...then app_icon, which is how niri hands over a screenshot: its
    // "Screenshot captured" notification leaves `image` empty and puts the
    // saved PNG in app_icon so the toast can preview it. Reading only `image`
    // is why a screenshot toast was not draggable.
    var icon = localFile(appIcon);
    if (icon && !isDecorationPath(icon))
        return [icon];

    return [];
}

// A notification announcing that something is now ON the clipboard — ours all
// say so in as many words ("Copied text to clipboard", "…copied to clipboard",
// "Clipboard from tailnet"), and so does anyone else's.
//
// Word-bounded so a message that merely contains "copies" or a filename with
// "clipboard" in it does not qualify.
function isClipboardNotification(summary, body) {
    return /\b(copied|clipboard)\b/i.test(String(summary || "") + "\n" + String(body || ""));
}

// The body as PLAIN text, for dropping into something that wanted text.
//
// The card renders the body as markup, so a text payload has to be the text
// without it: every tag goes, and the five XML entities libnotify senders
// escape come back. `&amp;` is unescaped LAST or `&amp;lt;` would decode
// twice and produce a `<` the sender never wrote.
function dragText(summary, body, app, appIcon) {
    var text = sanitizeBody(body, app, appIcon).replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&amp;/g, "&").trim();
    // A notification with no body at all is carried by its summary — a toast
    // that says only "Build failed" should still drop those two words.
    return text || String(summary || "").trim();
}

// What dragging a notification hands over, in the order the user asked for:
// the file it is about, else what it just put on the clipboard, else what it
// says.
//
// clipboardText is passed in rather than read here because reading it is
// asynchronous and this file has to stay free of QML types; the service
// captures it when a clipboard notification ARRIVES, which is also the only
// moment the clipboard is guaranteed to still hold what the toast is talking
// about.
function dragPayload(entry, clipboardText) {
    var e = entry || {};

    var paths = dragPaths(e.execArgv, e.image, e.appIcon);
    if (paths.length > 0)
        return {
            kind: "files",
            paths: paths,
            text: paths.join("\n")
        };

    if (isClipboardNotification(e.summary, e.body)) {
        var clip = String(clipboardText || "");
        if (clip)
            return {
                kind: "clipboard",
                paths: [],
                text: clip
            };
        // No clipboard text to hand over — an image-only clipboard, or a read
        // that failed. Fall through to the body rather than dragging nothing.
    }

    return {
        kind: "text",
        paths: [],
        text: dragText(e.summary, e.body, e.app, e.appIcon)
    };
}

// Same wire format as the Shelf's uriList: file:// URIs, CRLF-joined,
// trailing terminator — what every uri-list consumer expects.
function dragUriList(paths) {
    return paths.map(function (p) {
        return "file://" + String(p).split("/").map(encodeURIComponent).join("/");
    }).join("\r\n") + "\r\n";
}

function shouldRenderCompactGlyph(glyph, iconSource, singleLineToast) {
    return String(glyph || "").length > 0 && String(iconSource || "").length === 0 && !!singleLineToast;
}

function snapshotOf(notification, timestamp) {
    var n = notification || {};
    var id = n.id || 0;
    var expireTimeout = Number(n.expireTimeout || 0);
    if (!isFinite(expireTimeout) || expireTimeout < 0)
        expireTimeout = 0;
    return {
        id: id,
        originalId: id,
        app: n.appName || "",
        appIcon: n.appIcon || "",
        desktopEntry: n.desktopEntry || "",
        summary: String(n.summary || ""),
        body: n.body || "",
        image: n.image || "",
        glyph: glyphFromHints(n.hints),
        execArgv: execArgvFromHints(n.hints),
        urgency: n.urgency,
        expireTimeout: expireTimeout,
        timestamp: timestamp === undefined ? Date.now() : timestamp
    };
}

function historyEntry(value, normalUrgency) {
    var e = value || {};
    return {
        id: e.id || 0,
        originalId: e.originalId || e.id || 0,
        app: e.app || "",
        appIcon: e.appIcon || "",
        desktopEntry: e.desktopEntry || "",
        summary: e.summary || "",
        body: e.body || "",
        image: e.image || "",
        glyph: e.glyph || "",
        execArgv: e.execArgv || "",
        urgency: typeof e.urgency === "number" ? e.urgency : normalUrgency,
        expireTimeout: 0,
        timestamp: e.timestamp || 0
    };
}

function dedupeByOriginalId(rows) {
    var values = Array.isArray(rows) ? rows : [];
    var keep = {};
    for (var i = 0; i < values.length; i++) {
        var row = values[i];
        if (!row)
            continue;
        var key = row.originalId;
        if (key === undefined || key === null)
            key = "_" + i;
        var prior = keep[key];
        if (!prior || (row.timestamp || 0) >= (prior.timestamp || 0))
            keep[key] = row;
    }

    var out = [];
    for (var id in keep)
        out.push(keep[id]);
    out.sort(function (a, b) {
        return (b.timestamp || 0) - (a.timestamp || 0);
    });
    return out;
}

function parseHistory(raw, normalUrgency, historyCap) {
    var text = String(raw || "").trim();
    var cap = historyCap === undefined || historyCap === null ? 100 : Number(historyCap);
    if (isNaN(cap))
        cap = 100;
    cap = Math.max(0, cap);
    if (!text)
        return {
            empty: true,
            error: false,
            dnd: null,
            sound: null,
            muted: [],
            pending: [],
            past: [],
            hadDuplicates: false
        };

    try {
        var parsed = JSON.parse(text);
        var pendingRaw = (parsed && Array.isArray(parsed.pending)) ? parsed.pending : [];
        var pastRaw = (parsed && Array.isArray(parsed.past)) ? parsed.past : [];
        if (parsed && Array.isArray(parsed.entries))
            pastRaw = pastRaw.concat(parsed.entries);

        var pendingDeduped = dedupeByOriginalId(pendingRaw);
        var pastDeduped = dedupeByOriginalId(pastRaw);

        return {
            empty: false,
            error: false,
            dnd: parsed && typeof parsed.dnd === "boolean" ? parsed.dnd : null,
            // null, not false, so a file written before sounds existed keeps
            // the service's own default instead of being read as "off".
            sound: parsed && typeof parsed.sound === "boolean" ? parsed.sound : null,
            muted: muteRules(parsed ? parsed.muted : null),
            pending: pendingDeduped.slice(0, cap).map(function (entry) {
                return historyEntry(entry, normalUrgency);
            }),
            past: pastDeduped.slice(0, cap).map(function (entry) {
                return historyEntry(entry, normalUrgency);
            }),
            hadDuplicates: pendingDeduped.length !== pendingRaw.length || pastDeduped.length !== pastRaw.length
        };
    } catch (e) {
        return {
            empty: false,
            error: true,
            errorMessage: String(e),
            dnd: null,
            sound: null,
            muted: [],
            pending: [],
            past: [],
            hadDuplicates: false
        };
    }
}

// Newest N across both buckets, deduped by libnotify id — what the history
// replay pops back onto the screen.
function recentHistoryRows(pending, past, limit, normalUrgency) {
    var max = limit === undefined || limit === null ? 5 : Number(limit);
    if (isNaN(max))
        max = 5;
    max = Math.max(0, max);

    var values = [];
    function collect(rows) {
        var source = Array.isArray(rows) ? rows : [];
        for (var i = 0; i < source.length; i++) {
            if (source[i])
                values.push(source[i]);
        }
    }
    collect(pending);
    collect(past);

    var keep = {};
    for (var j = 0; j < values.length; j++) {
        var row = values[j];
        var key = row.originalId;
        if (key === undefined || key === null)
            key = row.id;
        if (key === undefined || key === null)
            key = "_" + j;
        var prior = keep[key];
        if (!prior || (row.timestamp || 0) >= (prior.timestamp || 0))
            keep[key] = row;
    }

    var out = [];
    for (var id in keep)
        out.push(historyEntry(keep[id], normalUrgency));
    out.sort(function (a, b) {
        return (b.timestamp || 0) - (a.timestamp || 0);
    });
    return out.slice(0, max);
}

// ------------------------------------------------------------ mute rules
//
// A per-sender silence, sitting between DND's all-or-nothing and living with
// an app that pings all day.
//
// Matched as a case-insensitive SUBSTRING rather than by equality, because
// `app_name` is not a stable identifier: the same program names itself
// differently depending on how it was started ("Vesktop" from a desktop
// entry, "vesktop" from a shell), and Electron senders drift between
// releases. Equality rules go stale silently — the app keeps notifying and
// the rule looks like it is on. The cost is that a short rule matches
// broadly ("sig" would also catch "signal-desktop-beta"), which is tolerable
// only because a rule is never typed: it is always created FROM a
// notification's own app name, so it is as specific as the sender that made
// it. (The shape is abran-labs/omarchy-notification-center's Rules.js; the
// reasoning is theirs and it holds here for the same reason.)
function muteRules(value) {
    if (!value || typeof value === "string" || typeof value.length !== "number")
        return [];
    var out = [];
    for (var i = 0; i < value.length; i++) {
        var rule = String(value[i] || "").trim();
        if (rule && out.indexOf(rule) === -1)
            out.push(rule);
    }
    return out;
}

function isMutedApp(rules, app) {
    var name = String(app || "").toLowerCase();
    if (!name)
        return false;
    var list = muteRules(rules);
    for (var i = 0; i < list.length; i++) {
        if (name.indexOf(list[i].toLowerCase()) !== -1)
            return true;
    }
    return false;
}

function addMuteRule(rules, app) {
    var rule = String(app || "").trim();
    var list = muteRules(rules);
    if (!rule)
        return list;
    for (var i = 0; i < list.length; i++) {
        if (list[i].toLowerCase() === rule.toLowerCase())
            return list;
    }
    return list.concat([rule]);
}

function removeMuteRule(rules, app) {
    var rule = String(app || "").trim().toLowerCase();
    var list = muteRules(rules);
    var out = [];
    for (var i = 0; i < list.length; i++) {
        if (list[i].toLowerCase() !== rule)
            out.push(list[i]);
    }
    return out;
}

// ---------------------------------------------------------- day sections
//
// History is grouped by the day an entry arrived on. The names are spelled
// out rather than formatted because Quickshell's QML engine ships no
// ECMA-402 — `Intl is not defined`, measured in the real engine while
// porting the world clock — so there is no toLocaleDateString(locale) to
// call, and this file has to give the same answer under node anyway.
var WEEKDAY_NAMES = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"];
var MONTH_NAMES = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

// Local midnight, which is what "a day" means to someone reading the panel.
// Deliberately not UTC days: a notification at 01:00 belongs to the day the
// user was awake for, not to whatever UTC calls it.
function startOfDay(ms) {
    var d = new Date(Number(ms) || 0);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
}

// The half-open range [from, to) covering the day a timestamp falls in —
// what the panel's per-day CLEAR acts on.
function dayBounds(timestamp) {
    var from = startOfDay(timestamp);
    // Not from + 86400000: a DST boundary makes a local day 23 or 25 hours
    // long, and a fixed step would either leak an hour into the next day or
    // leave an hour of this one unclearable.
    var next = new Date(from);
    next.setDate(next.getDate() + 1);
    return {
        from: from,
        to: next.getTime()
    };
}

function daySection(timestamp, nowMs) {
    var day = startOfDay(timestamp);
    var today = startOfDay(nowMs);
    if (day === today)
        return "TODAY";

    // Step back a calendar day at a time for the same DST reason as above.
    var yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    if (day === yesterday.getTime())
        return "YESTERDAY";

    var week = new Date(today);
    week.setDate(week.getDate() - 6);
    var when = new Date(day);
    // Within the last week a weekday name is the fastest thing to read; past
    // that it stops being unambiguous and the date has to appear.
    if (day > week.getTime())
        return WEEKDAY_NAMES[when.getDay()];

    var label = when.getDate() + " " + MONTH_NAMES[when.getMonth()];
    if (when.getFullYear() !== new Date(today).getFullYear())
        label += " " + when.getFullYear();
    return label;
}

// ----------------------------------------------------------- history view
//
// Free-text filter over the three fields a person actually remembers: who
// sent it, what it was called, what it said. Case-insensitive substring, and
// every whitespace-separated term has to hit somewhere, so "signal aisha"
// narrows instead of widening.
function matchesQuery(entry, query) {
    var text = String(query || "").trim().toLowerCase();
    if (!text)
        return true;
    var e = entry || {};
    var hay = (String(e.app || "") + "\n" + String(e.summary || "") + "\n" + String(e.body || "")).toLowerCase();
    var terms = text.split(/\s+/);
    for (var i = 0; i < terms.length; i++) {
        if (terms[i] && hay.indexOf(terms[i]) === -1)
            return false;
    }
    return true;
}

// The notification center's list: both buckets merged, newest first, day
// sections attached.
//
// Merged rather than stacked (unseen above seen, which is what this panel
// showed while history only lived 15 minutes) because durable history makes
// stacking read wrong: a three-day-old unseen entry would sit above
// everything that arrived today. Unseen becomes a per-row mark instead of a
// section, which is also what makes a chronological list possible at all.
//
// `section` is set only on the row that OPENS a day, with `sectionCount`
// carrying that day's total, so the delegate can draw a header without the
// view having to look at its neighbours.
function centerRows(pending, past, query, nowMs) {
    var merged = [];
    var i;
    for (i = 0; i < (pending || []).length; i++) {
        if (matchesQuery(pending[i], query))
            merged.push({ entry: pending[i], unseen: true });
    }
    for (i = 0; i < (past || []).length; i++) {
        if (matchesQuery(past[i], query))
            merged.push({ entry: past[i], unseen: false });
    }

    merged.sort(function (a, b) {
        var delta = (b.entry.timestamp || 0) - (a.entry.timestamp || 0);
        // Same millisecond: show the one still awaiting review first.
        return delta !== 0 ? delta : (a.unseen === b.unseen ? 0 : (a.unseen ? -1 : 1));
    });

    var now = Number(nowMs) || Date.now();
    var out = [];
    var openIndex = -1;
    var current = null;
    for (i = 0; i < merged.length; i++) {
        var label = daySection(merged[i].entry.timestamp, now);
        var row = {
            entry: merged[i].entry,
            unseen: merged[i].unseen,
            section: "",
            sectionCount: 0
        };
        if (label !== current) {
            current = label;
            row.section = label;
            openIndex = out.length;
        }
        out.push(row);
        out[openIndex].sectionCount += 1;
    }
    return out;
}

// ---------------------------------------------------------------- sound
//
// freedesktop sound-naming-spec event ids, so the theme decides what a
// notification sounds like and we only decide which event it is. Urgency is
// the only axis worth splitting on: a critical toast that sounded like a
// chat message would be a critical toast nobody looks up for.
//
// The enum values arrive as arguments rather than being read from
// NotificationUrgency, the way shouldBypassDnd already takes its own — this
// file has to give the same answers under node, where that enum does not
// exist.
function soundEventFor(urgency, criticalUrgency, lowUrgency) {
    if (urgency === criticalUrgency)
        return "dialog-warning";
    if (urgency === lowUrgency)
        return "message";
    return "message-new-instant";
}

// ---------------------------------------------------- popup persistence
//
// Each on-screen popup is mirrored to its own file under
// ~/.local/state/qshell/notifications/ so toasts survive real shell restarts
// (the server's keepOnReload only spans in-process reloads). The file exists
// exactly as long as the popup is on screen: written when the toast appears,
// deleted when it expires, is dismissed, overflows the cap, or its action is
// invoked.

function popupEntry(value, normalUrgency) {
    var entry = historyEntry(value, normalUrgency);
    var expire = Number((value || {}).expireTimeout || 0);
    if (!isFinite(expire) || expire < 0)
        expire = 0;
    entry.expireTimeout = expire;
    // Absolute expiry deadline, set only when a restore resets a surviving
    // popup's display lifetime. Kept out of the entry entirely when unset so
    // restored rows match the roles of freshly received ones.
    var deadline = Number((value || {}).deadline || 0);
    if (isFinite(deadline) && deadline > 0)
        entry.deadline = deadline;
    return entry;
}

function popupFileName(entry) {
    var e = entry || {};
    return String(e.timestamp || 0) + "-" + String(e.originalId || 0) + ".json";
}

function serializePopup(entry, normalUrgency) {
    // Compact (single-line) on purpose: restore reads every file together
    // and parses line by line, which only works when each file is one line.
    return JSON.stringify(popupEntry(entry, normalUrgency));
}

// Parse the concatenation of every persisted popup file into entries,
// newest-first. Deliberately NO dedupe: each file is a popup that was on
// screen, and originalId already folds in the session epoch, so files from
// different runs can never name the same notification. The one case that
// leaves a genuine duplicate (a crash between a replacement's write and the
// replaced file's delete) merely re-shows a superseded toast, which expires
// or is dismissed and cleans itself up.
function parsePopupFiles(raw, normalUrgency) {
    var lines = String(raw || "").split("\n");
    var entries = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line)
            continue;
        try {
            var value = JSON.parse(line);
            if (value && typeof value === "object")
                entries.push(popupEntry(value, normalUrgency));
        } catch (e) {
            // A torn write from a crash mid-save — skip the line, keep the rest.
        }
    }
    entries.sort(function (a, b) {
        return (b.timestamp || 0) - (a.timestamp || 0);
    });
    return entries;
}

// A persisted popup whose lifetime already ran out would have expired on
// screen had the shell kept running, so it is not restored. That covers
// critical toasts too: their lifetime is five minutes, not forever, so one
// persisted longer ago than that is dropped. A restore-reset deadline
// outranks the original timestamp: without it, a second restart would judge
// a re-shown toast by a clock that no longer governs its display and drop
// it while it is still on screen.
function popupExpired(entry, duration, now) {
    var deadline = Number((entry || {}).deadline || 0);
    if (isFinite(deadline) && deadline > 0)
        return Number(now) >= deadline;
    var lifetime = Number(duration || 0);
    if (!isFinite(lifetime) || lifetime <= 0)
        return false;
    return (Number(now) - Number((entry || {}).timestamp || 0)) >= lifetime;
}

// Toasts sit in the top-right corner. They only clear the bar when the bar
// occupies the top or right edge, so a left/bottom bar does not pull the
// popups away from where they are expected.
function popupPlacement(barPosition, barClearance, gapsOut) {
    var position = String(barPosition || "top");
    var clearance = Number(barClearance);
    var gap = Number(gapsOut);
    if (!isFinite(clearance))
        clearance = 0;
    if (!isFinite(gap))
        gap = 0;

    return {
        anchors: {
            top: true,
            bottom: false,
            left: false,
            right: true
        },
        margins: {
            top: position === "top" ? clearance : gap,
            bottom: gap,
            left: gap,
            right: position === "right" ? clearance : gap
        }
    };
}

function imageExtension(srcPath) {
    var lower = String(srcPath || "").toLowerCase();
    var dot = lower.lastIndexOf(".");
    if (dot < 0)
        return "png";
    var ext = lower.substring(dot + 1);
    if (ext.length === 0 || ext.length > 5)
        return "png";
    return ext;
}

// ------------------------------------------------------- click-to-focus
//
// Ours, not upstream's: they hand the app name to a Hyprland helper script
// that does the class matching. On niri the window list is already in the
// shell, so the match happens here and the result is one FocusWindow action.

function normalizeAppToken(value) {
    var text = String(value || "").trim().toLowerCase();
    if (!text)
        return "";
    // Paths (icon files, absolute exec lines) name no window class.
    if (text.indexOf("/") >= 0 || text.indexOf(":") >= 0)
        return "";
    if (text.length > 9 && text.lastIndexOf(".desktop") === text.length - 8)
        text = text.substring(0, text.length - 8);
    return text;
}

function lastSegment(value) {
    var text = String(value || "");
    var dot = text.lastIndexOf(".");
    return dot >= 0 && dot < text.length - 1 ? text.substring(dot + 1) : text;
}

// Best-first: the desktop-entry hint is what the spec says identifies the
// sending application, the app name is what it calls itself, the icon name
// is the last resort (it is usually the binary name).
function focusCandidates(entry, desktopEntry) {
    var out = [];
    function push(value) {
        var token = normalizeAppToken(value);
        if (token && out.indexOf(token) < 0)
            out.push(token);
    }
    push(desktopEntry);
    if (entry) {
        push(entry.desktopEntry);
        push(entry.app);
        push(entry.appIcon);
    }
    return out;
}

function appIdScore(candidate, appId) {
    var cand = normalizeAppToken(candidate);
    var id = normalizeAppToken(appId);
    if (!cand || !id)
        return 0;
    if (cand === id)
        return 100;
    if (lastSegment(id) === cand || lastSegment(cand) === id || lastSegment(id) === lastSegment(cand))
        return 80;
    if (cand.length >= 3 && (id.indexOf(cand) >= 0 || cand.indexOf(id) >= 0))
        return 60;
    return 0;
}

// windows: the { id: {title, appId} } map Services/Niri.qml keeps. Returns
// the numeric window id to focus, or null when nothing matches. Ties go to
// the highest id, i.e. the most recently opened window of that app.
function matchWindowId(candidates, windows) {
    var list = Array.isArray(candidates) ? candidates : [];
    if (list.length === 0 || !windows)
        return null;

    var bestId = null;
    var bestScore = 0;
    for (var key in windows) {
        var win = windows[key];
        if (!win)
            continue;
        var id = Number(key);
        if (!isFinite(id))
            continue;
        for (var i = 0; i < list.length; i++) {
            // Earlier candidates outrank later ones at equal match quality.
            var score = appIdScore(list[i], win.appId) - i;
            if (score <= 0)
                continue;
            if (score > bestScore || (score === bestScore && bestId !== null && id > bestId)) {
                bestScore = score;
                bestId = id;
            }
        }
    }
    return bestId;
}

if (typeof module !== "undefined") {
    module.exports = {
        isChromiumDerived: isChromiumDerived,
        sanitizeBody: sanitizeBody,
        stripImageTags: stripImageTags,
        isImageTag: isImageTag,
        styledBody: styledBody,
        summaryStartsWithGlyph: summaryStartsWithGlyph,
        shouldBypassDnd: shouldBypassDnd,
        isEphemeralApp: isEphemeralApp,
        glyphFromHints: glyphFromHints,
        execArgvFromHints: execArgvFromHints,
        parseExecArgv: parseExecArgv,
        dragPaths: dragPaths,
        dragUriList: dragUriList,
        localFile: localFile,
        isDecorationPath: isDecorationPath,
        isClipboardNotification: isClipboardNotification,
        dragText: dragText,
        dragPayload: dragPayload,
        shouldRenderCompactGlyph: shouldRenderCompactGlyph,
        snapshotOf: snapshotOf,
        historyEntry: historyEntry,
        dedupeByOriginalId: dedupeByOriginalId,
        parseHistory: parseHistory,
        recentHistoryRows: recentHistoryRows,
        muteRules: muteRules,
        isMutedApp: isMutedApp,
        addMuteRule: addMuteRule,
        removeMuteRule: removeMuteRule,
        startOfDay: startOfDay,
        dayBounds: dayBounds,
        daySection: daySection,
        matchesQuery: matchesQuery,
        centerRows: centerRows,
        soundEventFor: soundEventFor,
        popupEntry: popupEntry,
        popupFileName: popupFileName,
        serializePopup: serializePopup,
        parsePopupFiles: parsePopupFiles,
        popupExpired: popupExpired,
        popupPlacement: popupPlacement,
        imageExtension: imageExtension,
        normalizeAppToken: normalizeAppToken,
        focusCandidates: focusCandidates,
        appIdScore: appIdScore,
        matchWindowId: matchWindowId
    };
}

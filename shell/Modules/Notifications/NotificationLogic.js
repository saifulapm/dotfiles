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

// Chromium and its forks prefix the body with the origin ("mail.google.com"),
// which the card already implies — strip it, and drop inline <img> markup
// nothing here can render.
function sanitizeBody(body, app, appIcon) {
    var text = String(body || "").replace(/<img[^>]*>/gi, "");
    if (!isChromiumDerived(app, appIcon))
        return text;

    return text.replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "").replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "");
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

// Files a notification is ABOUT, for dragging out of its card. Derived from
// the exec-argv hint rather than declared as its own hint, so it works on
// every row exec-argv already reaches — live toasts, replayed history, rows
// restored across a shell restart. Only commands whose arguments ARE the
// subject files qualify: yazi-yank-clipboard (Taildrop arrivals) and mpv
// (the ytdlp download toast). An allowlist, not "any absolute argument" —
// crash-watch's argv carries the crashed binary's path, and a crash toast
// must not drag /usr/bin/foo around. Falls back to a file-backed image (a
// screenshot toast drags the shot); icon-theme names and image:// provider
// URLs have no file behind them.
var DRAG_CARRIERS = {
    "yazi-yank-clipboard": true,
    "mpv": true
};

function dragPaths(execArgv, image) {
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
    var img = String(image || "");
    if (img.indexOf("file://") === 0)
        img = decodeURIComponent(img.substring(7));
    if (img.charAt(0) === "/")
        return [img];
    return [];
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
        summaryStartsWithGlyph: summaryStartsWithGlyph,
        shouldBypassDnd: shouldBypassDnd,
        isEphemeralApp: isEphemeralApp,
        glyphFromHints: glyphFromHints,
        execArgvFromHints: execArgvFromHints,
        parseExecArgv: parseExecArgv,
        dragPaths: dragPaths,
        dragUriList: dragUriList,
        shouldRenderCompactGlyph: shouldRenderCompactGlyph,
        snapshotOf: snapshotOf,
        historyEntry: historyEntry,
        dedupeByOriginalId: dedupeByOriginalId,
        parseHistory: parseHistory,
        recentHistoryRows: recentHistoryRows,
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

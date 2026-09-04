// Unit tests for NotificationLogic.js's body sanitiser. Run with:
//
//     node shell/Modules/Notifications/NotificationLogic.test.js
//
// The notification body is the most hostile string this shell renders: it
// arrives over the session bus from any process, it is drawn as
// Text.StyledText so Qt parses markup in it, and StyledText honours <img src>
// — a remote src is an unauthenticated GET with no user action. These tests
// are the ones that would have caught the two holes the naive
// `/<img[^>]*>/gi` left (ported from omarchy 6e962b44/e428dc26/7026ede9).

const assert = require("node:assert/strict");
const Logic = require("./NotificationLogic.js");

let failures = 0;
function test(name, fn) {
    try {
        fn();
        console.log(`  ok  ${name}`);
    } catch (error) {
        failures += 1;
        console.log(`FAIL  ${name}\n      ${error.message}`);
    }
}

const strip = Logic.stripImageTags;
const styled = (body, app) => Logic.styledBody(body, app || "SomeApp", "");

// ------------------------------------------------------------ the basics
test("a plain image tag goes", () => {
    assert.equal(strip('before<img src="http://host/x.png">after'), "beforeafter");
});

test("non-image tags are kept, because the body may legitimately use markup", () => {
    assert.equal(strip("<b>bold</b> and <i>italic</i>"), "<b>bold</b> and <i>italic</i>");
    assert.equal(strip("plain text"), "plain text");
    assert.equal(strip(""), "");
});

test("a closing image tag goes too", () => {
    assert.equal(strip("<img><\/img>"), "");
});

// THE INVARIANT, and it is not "the output contains no `<img` substring".
// A substring inside a longer tag is harmless: in `<im<img src=…>` the first
// `<` opens the tag, so Qt reads one malformed tag named `im` and renders
// nothing. What must hold is that none of the tags QT WOULD PARSE is an image
// tag. Model that split here rather than pattern-matching the raw string,
// which is the same mistake the naive regex made.
function qtTags(text) {
    const tags = [];
    let i = 0;
    while (i < text.length) {
        const open = text.indexOf("<", i);
        if (open === -1)
            break;
        const close = text.indexOf(">", open);
        tags.push(close === -1 ? text.slice(open) : text.slice(open, close + 1));
        i = close === -1 ? text.length : close + 1;
    }
    return tags;
}
function assertNoLiveImage(out, label) {
    for (const tag of qtTags(out))
        assert.ok(!Logic.isImageTag(tag), `live image tag in ${label}: ${JSON.stringify(out)}`);
}

// ------------------------ hole 1: substring deletion manufactures a tag
test("nested decoy cannot splice a live tag out of the remainder", () => {
    // Qt reads ONE malformed tag named `im` here and renders nothing, so the
    // walker correctly KEEPS it whole. A naive /<img[^>]*>/g removes the INNER
    // match and closes the halves up into `<img src=".../beacon.png">` — a
    // live tag the input never contained.
    const attack = '<im<img src="http://a/decoy.png">g src="http://a/beacon.png">';

    const naive = attack.replace(/<img[^>]*>/gi, "");
    assert.deepEqual(qtTags(naive).filter(Logic.isImageTag).length, 1, "the naive regex really does manufacture a live tag");

    assert.equal(strip(attack), attack, "the walker keeps the malformed tag whole");
    assertNoLiveImage(strip(attack), "nested decoy");
});

test("no known shape survives as a tag Qt would fetch", () => {
    const attacks = [
        '<im<img src="http://a/d.png">g src="http://a/b.png">',
        '<b title="a>b"><img src="http://host/x.png">',
        '<<img src="http://host/x.png">',
        '<img src="http://host/x.png"',
        '<IMG SRC="http://host/x.png">',
        '<  img  src="http://host/x.png">',
        '</img src="http://host/x.png">',
        '<img src="http://host/x.png">',
        'a<img src=x>b<img src=y>c'
    ];
    for (const a of attacks)
        assertNoLiveImage(strip(a), a);
});

// --------------------- hole 2: the separator Qt skips but \s does not
test("U+0085 NEL between < and img is still an image tag", () => {
    // QQuickStyledText skips with QChar::isSpace(), which counts U+0085.
    // JavaScript's \s does not, so a name read with \s finds nothing, keeps
    // the tag, and Qt then reads `img` and issues the GET.
    const attack = '<img src="http://host/x.png">';
    assert.equal(Logic.isImageTag('<img'), true, "isImageTag must see through the NEL");
    assert.equal(strip(attack), "");
});

test("other separators Qt tolerates are covered by over-skipping", () => {
    for (const sep of ["", "﻿", " ", "\t", "\n", "/", "", ""])
        assert.equal(strip(`<${sep}img src="http://h/x">`), "", `separator ${JSON.stringify(sep)} leaked`);
});

// --------------------------- hole 3: the newline rewrite reopened a tag
test("the newline rewrite cannot splice a live image tag", () => {
    // `<x` + newline + `<img …>` is ONE tag named `x` to both the stripper and
    // Qt, so the stripper keeps it. Rewriting the newline to <br/> then splits
    // it into `<x<br/>` and a live image tag. styledBody must strip AGAIN
    // after the rewrite.
    const attack = '<x\n<img src="http://host/x.png">';
    assert.equal(strip(attack), attack, "one kept tag before the rewrite");

    const rewrittenThenUnchecked = strip(attack).replace(/\r\n|\r|\n/g, "<br/>");
    assert.ok(/<img src=/.test(rewrittenThenUnchecked), "the old ordering really does reopen it");

    assertNoLiveImage(styled(attack), "styledBody after rewrite");
});

test("styledBody still turns real newlines into breaks", () => {
    assert.equal(styled("line one\nline two"), "line one<br/>line two");
    assert.equal(styled("a\r\nb"), "a<br/>b");
});

// ------------------------------------------------- the chromium behaviour
test("the chromium origin prefix is still stripped", () => {
    assert.equal(Logic.sanitizeBody("mail.google.com  You have mail", "Chromium", ""), "You have mail");
    // ...and only for chromium-derived senders.
    assert.equal(Logic.sanitizeBody("mail.google.com  You have mail", "Thunderbird", ""), "mail.google.com  You have mail");
});

test("an image tag is dropped before the origin prefix is matched", () => {
    // The prefix regex is anchored at ^, so a leading image tag would hide the
    // origin from it if the strip ran second.
    assert.equal(Logic.sanitizeBody('<img src="http://a/x">mail.google.com  Hi', "Chromium", ""), "Hi");
});

// ------------------------------------------------------------ robustness
test("sanitizeBody tolerates junk input", () => {
    for (const v of [null, undefined, 0, false])
        assert.equal(typeof Logic.sanitizeBody(v, "App", ""), "string", String(v));
});

test("a body of only tags collapses to nothing", () => {
    assert.equal(strip('<img><img src="a"><img/>'), "");
});

test("an unterminated tag at the end is treated as one tag", () => {
    assert.equal(strip('text<img src="http://h/x'), "text");
    assert.equal(strip("text<b"), "text<b");
});

// ------------------------------------------------------------ mute rules
test("a mute rule matches its sender case-insensitively, as a substring", () => {
    const rules = Logic.addMuteRule([], "Vesktop");
    assert.equal(Logic.isMutedApp(rules, "vesktop"), true);
    assert.equal(Logic.isMutedApp(rules, "Vesktop"), true);
    // The whole reason the match is a substring: the same app renames itself.
    assert.equal(Logic.isMutedApp(rules, "vesktop-canary"), true);
    assert.equal(Logic.isMutedApp(rules, "Signal"), false);
});

test("muting is idempotent and unmuting is exact", () => {
    let rules = Logic.addMuteRule([], "Spotify");
    rules = Logic.addMuteRule(rules, "spotify");
    assert.deepEqual(rules, ["Spotify"], "a differently-cased duplicate must not add a second rule");

    rules = Logic.addMuteRule(rules, "Signal");
    assert.deepEqual(Logic.removeMuteRule(rules, "SPOTIFY"), ["Signal"]);
    assert.deepEqual(Logic.removeMuteRule(rules, "nothing"), ["Spotify", "Signal"]);
});

test("mute rules survive junk without matching everything", () => {
    // An empty rule as a substring would match every app name there is.
    assert.deepEqual(Logic.muteRules(["", "  ", "Signal"]), ["Signal"]);
    assert.deepEqual(Logic.muteRules(null), []);
    assert.deepEqual(Logic.muteRules("Signal"), [], "a bare string is not a rule list");
    assert.equal(Logic.isMutedApp([""], "anything"), false);
    assert.equal(Logic.isMutedApp(["Signal"], ""), false);
});

// ---------------------------------------------------------- day sections
const DAY = 24 * 60 * 60 * 1000;
// Local noon, so no test here can be flipped by a timezone offset.
function noonDaysAgo(n) {
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    d.setDate(d.getDate() - n);
    return d.getTime();
}

test("today and yesterday are named, the rest of the week is a weekday", () => {
    const now = noonDaysAgo(0);
    assert.equal(Logic.daySection(now, now), "TODAY");
    assert.equal(Logic.daySection(noonDaysAgo(1), now), "YESTERDAY");
    const threeAgo = Logic.daySection(noonDaysAgo(3), now);
    assert.ok(/^(SUN|MON|TUES|WEDNES|THURS|FRI|SATUR)DAY$/.test(threeAgo), threeAgo);
});

test("past a week a weekday is ambiguous, so the date appears", () => {
    const now = noonDaysAgo(0);
    const old = Logic.daySection(noonDaysAgo(20), now);
    assert.ok(/^\d{1,2} [A-Z]{3}$/.test(old), old);
    // A different year has to say so, or "3 JAN" is unreadable.
    const ancient = Logic.daySection(noonDaysAgo(400), now);
    assert.ok(/^\d{1,2} [A-Z]{3} \d{4}$/.test(ancient), ancient);
});

test("a day is the LOCAL day, and boundaries land where midnight does", () => {
    const now = noonDaysAgo(0);
    const bounds = Logic.dayBounds(now);
    assert.equal(new Date(bounds.from).getHours(), 0);
    assert.equal(bounds.from, Logic.startOfDay(now));
    assert.ok(bounds.to > bounds.from);
    // One minute before local midnight is still yesterday; one minute after
    // is today. A UTC-day split would get one of these wrong for most of the
    // world, and this machine is UTC+6.
    assert.equal(Logic.daySection(bounds.from - 60000, now), "YESTERDAY");
    assert.equal(Logic.daySection(bounds.from + 60000, now), "TODAY");
    // The range is half-open, so the last millisecond of today is inside it
    // and tomorrow's midnight is not — which is what stops a per-day CLEAR
    // from taking the first notification of the following day with it.
    assert.equal(Logic.daySection(bounds.to - 1, now), "TODAY");
    assert.ok(bounds.to > now && Logic.startOfDay(bounds.to) === bounds.to, "to is the next local midnight");
});

test("dayBounds steps a calendar day, not a fixed 24 hours", () => {
    // A DST-shifted day is 23 or 25 hours long. Asserting only that the span
    // is within an hour of a day catches a `from + 86400000` regression on a
    // DST machine without pinning this test to one timezone.
    const bounds = Logic.dayBounds(noonDaysAgo(0));
    const span = bounds.to - bounds.from;
    assert.ok(Math.abs(span - DAY) <= 60 * 60 * 1000, `span ${span}`);
});

// ---------------------------------------------------------------- search
const entry = (over) => Object.assign({
    originalId: 1,
    app: "Signal",
    summary: "Aisha",
    body: "on my way",
    timestamp: noonDaysAgo(0),
    urgency: 1
}, over || {});

test("search looks at sender, summary and body", () => {
    assert.equal(Logic.matchesQuery(entry(), "signal"), true);
    assert.equal(Logic.matchesQuery(entry(), "AISHA"), true);
    assert.equal(Logic.matchesQuery(entry(), "my way"), true);
    assert.equal(Logic.matchesQuery(entry(), "telegram"), false);
});

test("every term has to hit, so a second word narrows", () => {
    assert.equal(Logic.matchesQuery(entry(), "signal aisha"), true);
    assert.equal(Logic.matchesQuery(entry(), "signal telegram"), false);
    // An empty or blank query is not a filter.
    assert.equal(Logic.matchesQuery(entry(), ""), true);
    assert.equal(Logic.matchesQuery(entry(), "   "), true);
});

// ----------------------------------------------------------- centerRows
test("both buckets merge into one chronological list", () => {
    const now = noonDaysAgo(0);
    // The regression this guards: an unseen entry from days ago must NOT be
    // hoisted above everything seen today just for being unseen. That is what
    // the old pending-then-past ordering did, and it is why the panel could
    // not be grouped by day.
    const pending = [entry({ originalId: 1, summary: "old unseen", timestamp: noonDaysAgo(3) })];
    const past = [entry({ originalId: 2, summary: "seen today", timestamp: now })];

    const rows = Logic.centerRows(pending, past, "", now);
    assert.deepEqual(rows.map(r => r.entry.summary), ["seen today", "old unseen"]);
    assert.deepEqual(rows.map(r => r.unseen), [false, true]);
});

test("a section header opens each day and carries that day's count", () => {
    const now = noonDaysAgo(0);
    const rows = Logic.centerRows([], [
        entry({ originalId: 1, timestamp: now }),
        entry({ originalId: 2, timestamp: now - 1000 }),
        entry({ originalId: 3, timestamp: noonDaysAgo(1) })
    ], "", now);

    assert.deepEqual(rows.map(r => r.section), ["TODAY", "", "YESTERDAY"]);
    assert.equal(rows[0].sectionCount, 2, "TODAY holds two");
    assert.equal(rows[2].sectionCount, 1);
});

test("filtering re-sections what is left rather than leaving a gap", () => {
    const now = noonDaysAgo(0);
    // Drop the only TODAY row: YESTERDAY must become the opening section,
    // and its count must describe the FILTERED list, not the whole history.
    const rows = Logic.centerRows([], [
        entry({ originalId: 1, app: "Signal", timestamp: now }),
        entry({ originalId: 2, app: "Gmail", timestamp: noonDaysAgo(1) }),
        entry({ originalId: 3, app: "Gmail", timestamp: noonDaysAgo(1) })
    ], "gmail", now);

    assert.equal(rows.length, 2);
    assert.deepEqual(rows.map(r => r.section), ["YESTERDAY", ""]);
    assert.equal(rows[0].sectionCount, 2);
});

test("centerRows tolerates empty buckets", () => {
    assert.deepEqual(Logic.centerRows([], [], "", Date.now()), []);
    assert.deepEqual(Logic.centerRows(null, null, "", Date.now()), []);
});

// ----------------------------------------------------------------- sound
test("urgency picks the sound event, and critical is not a chat ping", () => {
    // Low=0, Normal=1, Critical=2, as the freedesktop enum has them.
    assert.equal(Logic.soundEventFor(2, 2, 0), "dialog-warning");
    assert.equal(Logic.soundEventFor(1, 2, 0), "message-new-instant");
    assert.equal(Logic.soundEventFor(0, 2, 0), "message");
});

// ------------------------------------------------------- persisted state
test("history round-trips the new settings, and old files keep their defaults", () => {
    const parsed = Logic.parseHistory(JSON.stringify({
        version: 3,
        dnd: true,
        sound: false,
        muted: ["Spotify", "", "Spotify"],
        pending: [],
        past: []
    }), 1, 100);
    assert.equal(parsed.dnd, true);
    assert.equal(parsed.sound, false);
    assert.deepEqual(parsed.muted, ["Spotify"], "blank and duplicate rules are dropped on load");

    // A v2 file has no `sound` key. It must read as null so the service keeps
    // its own default — reading a missing key as false would silently turn
    // sound off for anyone upgrading.
    const old = Logic.parseHistory('{"version":2,"dnd":false,"pending":[],"past":[]}', 1, 100);
    assert.equal(old.sound, null);
    assert.deepEqual(old.muted, []);

    for (const bad of ["", "{oops"]) {
        const p = Logic.parseHistory(bad, 1, 100);
        assert.equal(p.sound, null, bad);
        assert.deepEqual(p.muted, [], bad);
    }
});

// ------------------------------------------------------------- drag payload
const argvOf = (...a) => JSON.stringify(a);

test("a niri screenshot drags the shot, which is in app_icon and not image", () => {
    // The exact notification niri sends, captured off the bus 2026-09-04:
    // `image` is empty and the saved PNG rides in app_icon. Reading only
    // `image` is why screenshots were not draggable.
    const shot = {
        app: "niri",
        appIcon: "file:///home/saiful/Pictures/Screenshots/Screenshot%20from%202026-09-04%2015-09-59.png",
        image: "",
        execArgv: "",
        summary: "Screenshot captured",
        body: "You can paste the image from the clipboard."
    };
    const payload = Logic.dragPayload(shot, "some clipboard text");
    assert.equal(payload.kind, "files");
    assert.deepEqual(payload.paths, ["/home/saiful/Pictures/Screenshots/Screenshot from 2026-09-04 15-09-59.png"]);
    // ...and the file wins even though the body mentions the clipboard.
});

test("an app icon is not a subject file", () => {
    const themed = { app: "Thunderbird", appIcon: "/usr/share/icons/hicolor/64x64/apps/thunderbird.png", body: "New mail" };
    assert.equal(Logic.dragPayload(themed, "").kind, "text", "dragging must not scatter application icons");

    // Chromium hands the sender's AVATAR over as an app_icon in a scoped
    // temp dir. The app name is the origin, so no sender test would catch
    // it — the path is what identifies it.
    const chat = { app: "web.whatsapp.com", appIcon: "/tmp/.org.chromium.Chromium.AbCdEf/avatar.png", summary: "Aisha", body: "on my way" };
    const payload = Logic.dragPayload(chat, "");
    assert.equal(payload.kind, "text");
    assert.equal(payload.text, "on my way");
});

test("an icon-theme NAME has no file behind it", () => {
    assert.equal(Logic.localFile("firefox"), "");
    assert.equal(Logic.localFile("image://icon/firefox"), "");
    assert.equal(Logic.localFile(""), "");
    assert.equal(Logic.localFile("/home/x/a b.png"), "/home/x/a b.png");
    assert.equal(Logic.localFile("file:///home/x/a%20b.png"), "/home/x/a b.png");
});

test("the exec-argv allowlist still outranks everything", () => {
    const taildrop = {
        app: "qshell",
        execArgv: argvOf("yazi-yank-clipboard", "/home/saiful/Downloads/report.pdf"),
        appIcon: "/home/saiful/Pictures/decoy.png",
        body: "File received"
    };
    assert.deepEqual(Logic.dragPayload(taildrop, "").paths, ["/home/saiful/Downloads/report.pdf"]);

    // ...and a crash toast's argv is NOT a subject file.
    const crash = { app: "qshell", execArgv: argvOf("coredumpctl", "info", "/usr/bin/qs"), summary: "Process crashed", body: "qs dumped core" };
    const payload = Logic.dragPayload(crash, "");
    assert.equal(payload.kind, "text");
    assert.deepEqual(payload.paths, []);
});

test("a clipboard notification drags the clipboard, not the sentence about it", () => {
    const ocr = { app: "qshell", summary: "OCR", body: "Copied text to clipboard" };
    const payload = Logic.dragPayload(ocr, "the recognised text");
    assert.equal(payload.kind, "clipboard");
    assert.equal(payload.text, "the recognised text");

    // Every wording our own copy scripts use has to be recognised.
    for (const [summary, body] of [["Color picked", "#89b4fa copied to clipboard (rgb(137, 177, 250))"], ["󰅍 URL copied to clipboard", ""], ["󰅌 Clipboard from tailnet", "a preview"], ["Copied 😀", "Could not type it — on the clipboard, paste with Ctrl+V"]])
        assert.equal(Logic.isClipboardNotification(summary, body), true, summary);

    // Word-bounded, so this is not a clipboard notification.
    assert.equal(Logic.isClipboardNotification("Build failed", "3 copies of the artifact differ"), false);
});

test("an empty clipboard falls back to the body instead of dragging nothing", () => {
    const ocr = { app: "qshell", summary: "OCR", body: "Copied text to clipboard" };
    const payload = Logic.dragPayload(ocr, "");
    assert.equal(payload.kind, "text");
    assert.equal(payload.text, "Copied text to clipboard");
});

test("an ordinary notification drags its body as PLAIN text", () => {
    // The card renders the body as markup, so the text payload must not
    // carry any of it — and the entity unescape must not double-decode.
    const marked = { app: "Some App", summary: "Heads up", body: "<b>done</b> in 3&amp;a bit<br/>second line &lt;not a tag&gt;" };
    const payload = Logic.dragPayload(marked, "");
    assert.equal(payload.kind, "text");
    assert.equal(payload.text, "done in 3&a bit\nsecond line <not a tag>");
});

test("a body-less notification drags its summary", () => {
    assert.equal(Logic.dragPayload({ app: "cargo", summary: "Build failed", body: "" }, "").text, "Build failed");
    // Nothing at all is not a drag source; the card checks text.length.
    assert.equal(Logic.dragPayload({ app: "x", summary: "", body: "" }, "").text, "");
});

test("the image hint still wins when a sender sets it", () => {
    const shot = { app: "grim", image: "file:///home/saiful/Pictures/a.png", appIcon: "grim", body: "saved" };
    assert.deepEqual(Logic.dragPayload(shot, "").paths, ["/home/saiful/Pictures/a.png"]);
});

test("the uri-list wire format is unchanged", () => {
    assert.equal(Logic.dragUriList(["/home/x/a b.png"]), "file:///home/x/a%20b.png\r\n");
    assert.equal(Logic.dragUriList(["/a", "/b"]), "file:///a\r\nfile:///b\r\n");
});

console.log(failures === 0 ? "\nall NotificationLogic tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);

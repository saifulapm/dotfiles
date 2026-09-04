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

console.log(failures === 0 ? "\nall NotificationLogic tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);

// Unit tests for PassModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/PassModel.test.js
//
// Fixtures here name only services this repo already names about itself —
// GitHub, iCloud — and are otherwise invented.
//
// That is a rule rather than a preference. Entry names are plaintext on disk
// (gpg encrypts contents, not filenames), which is the stated reason
// ~/.password-store is a separate PRIVATE repo; see the `pass` entry in
// packages/manifest.toml. Real names used as fixtures would publish, piecemeal
// into a public repo, an index of which services this machine holds accounts
// with — and the commercial ones are exactly the targeting information that
// rule exists to withhold. These tests care about SHAPES, so invented names
// cost them nothing.

const assert = require("node:assert/strict");
const Model = require("./PassModel.js");

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

// bin/pass-store hands these over already recency-ordered.
const LIST = [
    "github/cli-token",
    "email/icloud/saiful.apm",
    "web/github.com",
    "web/gitlab.com",
    "banking/hsbc",
    "shopping"
].join("\n");

const entries = Model.parseEntries(LIST);
const byName = name => entries.find(e => e.name === name);

// ------------------------------------------------------------------ parsing

test("entries split into folder and leaf", () => {
    assert.equal(entries.length, 6);
    const github = byName("web/github.com");
    assert.equal(github.folder, "web");
    assert.equal(github.leaf, "github.com");
});

test("a deeply nested entry keeps its whole folder path", () => {
    const icloud = byName("email/icloud/saiful.apm");
    assert.equal(icloud.folder, "email/icloud");
    assert.equal(icloud.leaf, "saiful.apm");
});

test("a top-level entry has no folder", () => {
    assert.equal(byName("shopping").folder, "");
    assert.equal(byName("shopping").leaf, "shopping");
});

test("the list order is preserved, because it is the recency order", () => {
    assert.equal(entries[0].name, "github/cli-token");
    assert.equal(entries[0].order, 0);
});

test("blank lines are ignored", () => {
    assert.equal(Model.parseEntries("").length, 0);
    assert.equal(Model.parseEntries("\n\n  \n").length, 0);
});

// -------------------------------------------------------- subsequence match

test("the advertised case works: ghb finds web/github.com", () => {
    assert.ok(Model.matches(byName("web/github.com"), "ghb"));
});

test("subsequence means in order, not merely present", () => {
    assert.ok(Model.subsequence("web/github.com", "ghb"));
    assert.ok(Model.subsequence("web/github.com", "wgc"));
    assert.ok(!Model.subsequence("web/github.com", "bhg"), "same letters, wrong order");
    assert.ok(!Model.subsequence("web/github.com", "xyz"));
});

test("repeated characters need repeated occurrences", () => {
    assert.ok(Model.subsequence("banana", "aaa"));
    assert.ok(!Model.subsequence("banana", "aaaa"));
});

test("an empty query matches everything", () => {
    assert.ok(Model.subsequence("anything", ""));
    assert.equal(Model.rank(entries, "").length, 6);
    assert.equal(Model.rank(entries, "   ").length, 6);
});

test("matching is case-insensitive", () => {
    assert.ok(Model.matches(byName("banking/hsbc"), "HSBC"));
    assert.ok(Model.matches(byName("banking/hsbc"), "Hsbc"));
});

// ----------------------------------------------------------------- ranking

test("an exact leaf beats a prefix beats a substring beats a subsequence", () => {
    assert.ok(Model.score(byName("shopping"), "shopping") > Model.score(byName("web/github.com"), "github"));
    assert.ok(Model.score(byName("web/github.com"), "github") > Model.score(byName("web/github.com"), "hub"));
    assert.ok(Model.score(byName("web/github.com"), "hub") > Model.score(byName("web/github.com"), "ghb"));
});

test("typing a leaf name puts it first even against a recent entry", () => {
    // github/cli-token is the most recently used; typing "github.com" must
    // still surface web/github.com.
    assert.equal(Model.rank(entries, "github.com")[0].name, "web/github.com");
});

test("a leaf-prefix match outranks a folder-prefix one", () => {
    // "git" prefixes the LEAF of web/github.com but only the FOLDER of
    // github/cli-token, and the leaf is the entry's real name — so
    // github.com leads even though cli-token is the more recently used.
    // (This is the assertion that was written backwards first: recency does
    // not cross a relevance band.)
    const order = Model.rank(entries, "git").map(e => e.name);
    assert.equal(order[0], "web/github.com");
    assert.ok(order.includes("github/cli-token"));
    assert.ok(order.includes("web/gitlab.com"));
});

test("recency leads inside a band", () => {
    // "com" is a substring of both leaves and a prefix of neither, so the
    // two land in the same band and the list order — which is recency —
    // decides. github.com is listed before gitlab.com.
    const order = Model.rank(entries, "com").map(e => e.name);
    const github = order.indexOf("web/github.com");
    const gitlab = order.indexOf("web/gitlab.com");
    assert.ok(github !== -1 && gitlab !== -1);
    assert.ok(github < gitlab, "same band, so the more recent one leads");
    assert.equal(Model.score(byName("web/github.com"), "com"), Model.score(byName("web/gitlab.com"), "com"));
});

test("a subsequence-only hit ranks below every real one", () => {
    const order = Model.rank(entries, "gh").map(e => e.name);
    // "github/cli-token" contains "gh" as a substring; "shopping" does not
    // match at all; anything reached only by skipping letters trails.
    assert.equal(order[0], "github/cli-token");
});

test("a query that matches nothing yields nothing", () => {
    assert.deepEqual(Model.rank(entries, "zzzzz"), []);
});

// ------------------------------------------------------------ capabilities

test("caps parse from the script's line output", () => {
    assert.deepEqual(Model.parseCaps("type"), ["type"]);
    assert.deepEqual(Model.parseCaps("otp\ntype"), ["otp", "type"]);
    assert.deepEqual(Model.parseCaps(""), []);
});

test("hints only advertise what the machine can do", () => {
    // This machine right now: wtype yes, pass-otp not installed.
    const withoutOtp = Model.actionHints(["type"]);
    assert.ok(!withoutOtp.includes("Alt+O"), "no OTP key when pass-otp is absent");
    assert.ok(withoutOtp.includes("Ctrl+Enter types"));

    const both = Model.actionHints(["otp", "type"]);
    assert.ok(both.includes("Alt+O code"));

    const neither = Model.actionHints([]);
    assert.ok(!neither.includes("Alt+O"));
    assert.ok(!neither.includes("Ctrl+Enter"));
    // Copy and edit need nothing beyond pass itself, so they are always there.
    assert.ok(neither.includes("Enter copies"));
    assert.ok(neither.includes("Alt+E edits"));
});

test("the QR chord is advertised only where the whole chain exists", () => {
    // `qr` is one capability covering screenshot-qr + zbarimg + pass-otp, so
    // the panel never offers a capture that can only end in a missing package.
    assert.ok(Model.actionHints(["otp", "type", "qr"]).includes("Alt+N scans a QR"));
    assert.ok(!Model.actionHints(["otp", "type"]).includes("Alt+N"));
});

// ---------------------------------------------------------- the captured QR

test("otp-scan's four fields parse, and there is no fifth", () => {
    const capture = Model.parseCapture("GitHub\tsaiful.apm@gmail.com\tTOTP\t6\n");
    assert.deepEqual(capture, {
        issuer: "GitHub",
        account: "saiful.apm@gmail.com",
        type: "TOTP",
        digits: 6
    });
    // The point of the whole arrangement: there is nowhere for a secret to be.
    assert.deepEqual(Object.keys(capture).sort(), ["account", "digits", "issuer", "type"]);
});

test("a label with no issuer still describes itself", () => {
    // otpauth://hotp/Fastmail?… — the label is the account, and there is no
    // issuer parameter. A QR whose label carries no issuer looks exactly like that.
    const capture = Model.parseCapture("\tFastmail\tHOTP\t6");
    assert.equal(capture.issuer, "");
    assert.equal(Model.captureTitle(capture), "Fastmail");
    // The account is the title already, so the caption does not repeat it.
    assert.equal(Model.captureMeta(capture), "HOTP · 6 digits");
});

test("the hero says what was captured and nothing else", () => {
    const capture = Model.parseCapture("GitHub\tsaiful.apm@gmail.com\tTOTP\t8");
    assert.equal(Model.captureTitle(capture), "GitHub");
    assert.equal(Model.captureMeta(capture), "saiful.apm@gmail.com · TOTP · 8 digits");
});

test("anything that is not otp-scan's answer is refused", () => {
    assert.equal(Model.parseCapture(""), null);
    assert.equal(Model.parseCapture("GitHub\tuser\tTOTP"), null, "too few fields");
    assert.equal(Model.parseCapture("GitHub\tuser\tWHAT\t6"), null, "unknown type");
    // A URI that somehow reached this function is not a capture, and must not
    // be displayed as one.
    assert.equal(Model.parseCapture("otpauth://totp/GitHub?secret=SEEKRIT"), null);
    assert.equal(Model.parseCapture("\t\tTOTP\t6"), null, "nothing to show");
});

test("digits outside the plausible range fall back to the spec's six", () => {
    assert.equal(Model.parseCapture("GitHub\tuser\tTOTP\t").digits, 6);
    assert.equal(Model.parseCapture("GitHub\tuser\tTOTP\t0").digits, 6);
    assert.equal(Model.parseCapture("GitHub\tuser\tTOTP\t99").digits, 6);
    assert.equal(Model.parseCapture("GitHub\tuser\tTOTP\t8").digits, 8);
});

test("a hostile issuer cannot push the panel off the screen", () => {
    const capture = Model.parseCapture("x".repeat(400) + "\tuser\tTOTP\t6");
    assert.ok(capture.issuer.length <= 64);
    assert.ok(capture.issuer.endsWith("…"));
});

// ------------------------------------------------------------ the new path

test("the suggested path matches what the store already looks like", () => {
    assert.equal(Model.suggestedPath(Model.parseCapture("GitHub\tsaiful.apm@gmail.com\tTOTP\t6")), "otp/GitHub/saiful.apm@gmail.com");
    // Issuer only — otp/Fastmail, and a bare service name are both this shape.
    assert.equal(Model.suggestedPath(Model.parseCapture("\tFastmail\tHOTP\t6")), "otp/Fastmail");
    assert.equal(Model.suggestedPath(null), "");
});

test("a slash in an issuer becomes a dash rather than a folder", () => {
    // The one sanitizing rule with a consequence: "Acme/Prod" would otherwise
    // silently write otp/Acme/Prod/<account>.
    assert.equal(Model.pathSegment("Acme/Prod"), "Acme-Prod");
    assert.equal(Model.suggestedPath(Model.parseCapture("Acme/Prod\tops\tTOTP\t6")), "otp/Acme-Prod/ops");
});

test("spaces follow the store's own habit and become dashes", () => {
    assert.equal(Model.pathSegment("Acme Ads"), "Acme-Ads");
    assert.equal(Model.pathSegment("  Amazon  Web  Services "), "Amazon-Web-Services");
});

test("a segment cannot start with a dot or a dash", () => {
    assert.equal(Model.pathSegment(".hidden"), "hidden");
    assert.equal(Model.pathSegment("--force"), "force");
    // Dots inside a name are ordinary — otp/secure.example.com is one shape it has.
    assert.equal(Model.pathSegment("secure.example.com"), "secure.example.com");
});

test("an issuer that duplicates the account is not written twice", () => {
    assert.equal(Model.suggestedPath(Model.parseCapture("Fastmail\tFastmail\tTOTP\t6")), "otp/Fastmail");
});

test("a nameless code still lands somewhere writable", () => {
    // Nothing survives sanitizing — the field is editable, so it needs a
    // valid starting point rather than a refusal.
    const capture = Model.parseCapture("...\t///\tTOTP\t6");
    // "otp/unnamed" is bin/otp-import's fallback for the same case.
    assert.equal(Model.suggestedPath(capture), "otp/unnamed");
    assert.equal(Model.pathState(Model.suggestedPath(capture), []), "ok");
});

test("an existing path is refused before the key is pressed", () => {
    const names = entries.map(e => e.name);
    assert.equal(Model.pathState("web/github.com", names), "exists");
    assert.equal(Model.pathState("  web/github.com  ", names), "exists", "trimmed first");
    assert.equal(Model.pathState("otp/GitHub/new", names), "ok");
    assert.ok(Model.pathNotice("exists", "web/github.com").includes("append"));
});

test("a path that would leave the store is invalid", () => {
    // The same refusals bin/pass-store makes; this copy exists to say so
    // while the field still has focus.
    assert.equal(Model.pathState("/etc/passwd", []), "invalid");
    assert.equal(Model.pathState("../escape", []), "invalid");
    assert.equal(Model.pathState("otp/../../escape", []), "invalid");
    assert.equal(Model.pathState("otp/./here", []), "invalid");
    assert.equal(Model.pathState("otp//here", []), "invalid");
    assert.equal(Model.pathState("otp/", []), "invalid");
    assert.equal(Model.pathState("", []), "empty");
    assert.equal(Model.pathState("   ", []), "empty");
    assert.equal(Model.pathNotice("ok", "otp/x"), "");
    assert.equal(Model.pathNotice("empty", ""), "");
});

test("a name that merely contains dots is fine", () => {
    assert.equal(Model.pathState("otp/secure.example.com", []), "ok");
    assert.equal(Model.pathState("otp/a..b", []), "ok", "not a traversal");
});

test("the captured footers name the keys that exist there", () => {
    assert.ok(Model.captureHints("destination").includes("Alt+N"));
    assert.ok(Model.captureHints("destination").includes("Esc discards"));
    assert.ok(Model.captureHints("new").includes("Enter creates"));
    assert.ok(!Model.captureHints("new").includes("Alt+N"), "nothing to be new from in there");
});

// -------------------------------------------------------------------- prose

test("the hero counts and narrows", () => {
    assert.equal(Model.heroMeta(6, 6, ""), "6 entries");
    assert.equal(Model.heroMeta(1, 1, ""), "1 entry");
    assert.equal(Model.heroMeta(6, 2, "git"), "2 of 6 entries");
    assert.equal(Model.heroMeta(0, 0, ""), "The store is empty");
});

test("the tooltip never names an entry", () => {
    // The bar tooltip is visible without any interaction, so it says how
    // many there are and nothing about what they are.
    const text = Model.tooltipText(6);
    assert.equal(text, "Passwords — 6 entries");
    assert.ok(!text.includes("github"));
    assert.equal(Model.tooltipText(0), "Passwords — the store is empty");
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

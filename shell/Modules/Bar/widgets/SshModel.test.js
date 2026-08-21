// Unit tests for SshModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/SshModel.test.js
//
// The fixture is this machine's real `bin/ssh-hosts` output (2026-08-21,
// user column kept as it actually reads), plus two synthetic rows for the
// cases the live config has no example of: a non-default port on a named
// host, and a ProxyJump.
//
// SshModel.js is dependency-free so these run under plain node; `node <file>`
// is the runner, as with WarpModel.test.js.

const assert = require("node:assert/strict");
const Model = require("./SshModel.js");

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

// ---------------------------------------------------- real bin/ssh-hosts TSV

const TSV = [
    "github.com\tssh.github.com\tsaiful\t443\t\t0",
    "github.com-work\tssh.github.com\tsaiful\t443\t\t0",
    "github.com-project\tssh.github.com\tsaiful\t443\t\t0",
    "macbook\tmacbook\tsaiful\t22\t\t0",
    "mini\tmini\tsaiful\t22\t\t1787318089",
    "nuc\tnuc\tsaiful\t22\t\t1787318089",
    "behind\tbehind.example\tzoe\t2222\tmini\t0"
].join("\n");

const hosts = Model.parseRows(TSV);
const byAlias = alias => hosts.find(h => h.alias === alias);

// ------------------------------------------------------------------ parsing

test("every row becomes a host, in file order", () => {
    assert.equal(hosts.length, 7);
    assert.equal(hosts[0].alias, "github.com");
    assert.equal(hosts[0].order, 0);
    assert.equal(hosts[6].alias, "behind");
    assert.equal(hosts[6].order, 6);
});

test("columns land in the right fields", () => {
    const behind = byAlias("behind");
    assert.equal(behind.hostname, "behind.example");
    assert.equal(behind.user, "zoe");
    assert.equal(behind.port, "2222");
    assert.equal(behind.jump, "mini");
    assert.equal(behind.lastUsed, 0);
});

test("an empty proxyjump column stays empty, not 'undefined'", () => {
    assert.equal(byAlias("mini").jump, "");
});

test("blank lines and trailing newlines are ignored", () => {
    assert.equal(Model.parseRows("").length, 0);
    assert.equal(Model.parseRows("\n\n").length, 0);
    assert.equal(Model.parseRows(TSV + "\n").length, 7);
});

// ---------------------------------------------------------------- subtitles

test("a user is always shown attached to its host", () => {
    // `Host mini` with no HostName resolves to "mini". The subtitle is
    // "saiful@mini" — the thing you would type — rather than a bare "saiful",
    // and never "saiful@mini · mini".
    assert.equal(Model.subtitle(byAlias("mini")), "saiful@mini");
    assert.equal(Model.subtitle(byAlias("macbook")), "saiful@macbook");
});

test("with no user, a hostname that echoes the alias is dropped", () => {
    // Nothing to attach it to, and the row is already titled with the alias.
    assert.equal(Model.subtitle({ alias: "mini", hostname: "mini", user: "", port: "22", jump: "" }), "");
    assert.equal(Model.subtitle({ alias: "mini", hostname: "other.example", user: "", port: "22", jump: "" }), "other.example");
});

test("a real hostname is shown when it differs from the alias", () => {
    assert.equal(Model.subtitle(byAlias("github.com-work")), "saiful@ssh.github.com · port 443");
});

test("port 22 is left off; anything else is spelled out", () => {
    assert.ok(!Model.subtitle(byAlias("macbook")).includes("port"));
    assert.ok(Model.subtitle(byAlias("behind")).includes("port 2222"));
});

test("a proxy jump is named", () => {
    assert.equal(Model.subtitle(byAlias("behind")), "zoe@behind.example · port 2222 · via mini");
});

test("subtitle survives a host with nothing but an alias", () => {
    assert.equal(Model.subtitle({ alias: "bare", hostname: "bare", user: "", port: "22", jump: "" }), "");
    assert.equal(Model.subtitle(null), "");
});

// ---------------------------------------------------------------- filtering

test("an empty query lists every host you could get a shell on", () => {
    // Seven rows, three of which are github transports — the default list is
    // the four real machines.
    assert.equal(Model.rank(hosts, "").length, 4);
    assert.equal(Model.rank(hosts, "   ").length, 4);
    assert.ok(!Model.rank(hosts, "").some(h => h.alias.startsWith("github")));
});

test("matching is case-insensitive and hits any field", () => {
    assert.ok(Model.matches(byAlias("mini"), "MINI"));
    assert.ok(Model.matches(byAlias("behind"), "zoe"), "user");
    assert.ok(Model.matches(byAlias("behind"), "2222"), "port");
    assert.ok(Model.matches(byAlias("behind"), "mini"), "jump host");
    assert.ok(!Model.matches(byAlias("mini"), "nothing-like-this"));
});

test("multiple terms all have to match, in any order", () => {
    assert.ok(Model.matches(byAlias("github.com-work"), "github work"));
    assert.ok(Model.matches(byAlias("github.com-work"), "work github"));
    assert.ok(!Model.matches(byAlias("github.com-work"), "github nuc"));
});

// ----------------------------------------------------------------- ordering

test("with no query, recently used hosts come first", () => {
    const order = Model.rank(hosts, "").map(h => h.alias);
    assert.deepEqual(order.slice(0, 2), ["mini", "nuc"], "both used at the same second, config order breaks the tie");
    // Everything else keeps the order the config reads in.
    assert.deepEqual(order.slice(2), ["macbook", "behind"]);
});

test("a typed name outranks a recently used one", () => {
    // "macbook" has never been opened and "mini"/"nuc" were opened today;
    // typing it must still put it first.
    assert.equal(Model.rank(hosts, "macbook")[0].alias, "macbook");
    assert.equal(Model.rank(hosts, "mac")[0].alias, "macbook");
});

test("an exact alias beats a prefix beats a substring", () => {
    // Searching by name is also what un-hides the forges.
    const scored = Model.rank(hosts, "github.com").map(h => h.alias);
    assert.equal(scored[0], "github.com");
    assert.deepEqual(scored.slice(1, 3), ["github.com-work", "github.com-project"]);
});

test("a hostname match ranks below an alias match", () => {
    // "behind" the alias vs "behind.example" the hostname — same host here,
    // but the alias band must be the one that wins.
    assert.ok(Model.score(byAlias("behind"), "behind") > Model.score(byAlias("behind"), "example"));
});

test("recency only breaks ties inside a relevance band", () => {
    const recentMacbook = hosts.map(h => h.alias === "macbook" ? Object.assign({}, h, { lastUsed: 9999999999 }) : h);
    // Both start with "m"; macbook is now the recent one, so it leads.
    assert.equal(Model.rank(recentMacbook, "m")[0].alias, "macbook");
    // But an exact query still wins over recency.
    assert.equal(Model.rank(recentMacbook, "mini")[0].alias, "mini");
});

// -------------------------------------------------------------------- prose

test("the hero counts what you can reach, and admits what it hid", () => {
    assert.equal(Model.heroMeta(hosts, 4, ""), "4 hosts · 3 git remotes hidden");
    // With no forges in the config there is nothing to admit.
    const plain = hosts.filter(h => !Model.isForge(h));
    assert.equal(Model.heroMeta(plain, 4, ""), "4 hosts");
    assert.equal(Model.heroMeta([plain[0]], 1, ""), "1 host", "singular");
    // A query searches everything, so it counts against the whole config.
    assert.equal(Model.heroMeta(hosts, 3, "github"), "3 of 7 hosts");
    assert.equal(Model.heroMeta([], 0, ""), "No hosts in ~/.ssh/config");
});

test("one hidden git remote is singular too", () => {
    const one = hosts.filter(h => !Model.isForge(h)).concat(hosts.find(h => h.alias === "github.com"));
    assert.equal(Model.heroMeta(one, 4, ""), "4 hosts · 1 git remote hidden");
});

test("the tooltip counts reachable hosts, not config lines", () => {
    assert.equal(Model.tooltipText([]), "SSH — no hosts configured");
    assert.equal(Model.tooltipText(hosts), "SSH — 4 hosts", "seven Host blocks, four you can reach");
    assert.equal(Model.tooltipText([byAlias("mini")]), "SSH — 1 host");
    // A config of nothing but git remotes has nothing for this widget to do.
    assert.equal(Model.tooltipText(hosts.filter(Model.isForge)), "SSH — only git remotes configured");
});

// -------------------------------------------------------------- git forges

test("a forge is recognized by its resolved hostname, not its alias", () => {
    assert.equal(Model.isForge(byAlias("github.com")), true);
    assert.equal(Model.isForge(byAlias("github.com-work")), true, "alias differs, hostname is ssh.github.com");
    assert.equal(Model.isForge(byAlias("mini")), false);
    // A machine you happened to name after a forge is still a machine.
    assert.equal(Model.isForge({ alias: "github", hostname: "box.lan" }), false);
    // …and an alias that hides its forge is still a forge.
    assert.equal(Model.isForge({ alias: "work", hostname: "ssh.github.com" }), true);
});

test("subdomains of a forge count, unrelated lookalikes do not", () => {
    assert.equal(Model.isForge({ hostname: "altssh.gitlab.com" }), true);
    assert.equal(Model.isForge({ hostname: "git.example.com" }), false);
    assert.equal(Model.isForge({ hostname: "notgithub.com" }), false, "suffix match must be on a dot boundary");
    assert.equal(Model.isForge({ hostname: "" }), false);
    assert.equal(Model.isForge(null), false);
});

test("forges are counted and excluded from the reachable total", () => {
    assert.equal(Model.forgeCount(hosts), 3);
    assert.equal(Model.shellHostCount(hosts), 4);
    assert.equal(Model.forgeCount([]), 0);
});

test("only a forge carries the no-shell note", () => {
    assert.equal(Model.noteText(byAlias("github.com")), "git remote — no shell");
    assert.equal(Model.noteText(byAlias("mini")), "");
});

// ------------------------------------------------------------------ command

test("the connect command passes the alias after --, never through a shell", () => {
    const command = Model.connectCommand(byAlias("mini"), "foot-run");
    assert.deepEqual(command, ["foot-run", "--app-id=ssh-mini", "ssh", "--", "mini"]);
    // An alias that looks like an option is data, not a flag.
    const hostile = Model.connectCommand({ alias: "-oProxyCommand=touch /tmp/pwned" }, "foot-run");
    assert.equal(hostile[hostile.length - 2], "--");
    assert.equal(hostile[hostile.length - 1], "-oProxyCommand=touch /tmp/pwned");
});

test("a host with no alias yields no command at all", () => {
    assert.deepEqual(Model.connectCommand(null, "foot-run"), []);
    assert.deepEqual(Model.connectCommand({ alias: "" }, "foot-run"), []);
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

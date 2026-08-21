// Unit tests for PortsModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/PortsModel.test.js
//
// The fixture is real `bin/ports` output from the NUC (2026-08-21) — the
// caddy dev proxy, the on-demand database sockets, sshd, the tailnet
// listeners — with one synthetic row for a user-owned dev server, captured
// from a `python3 -m http.server` used to test the kill guard.

const assert = require("node:assert/strict");
const Model = require("./PortsModel.js");

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

// ------------------------------------------------------- real bin/ports rows

const TSV = [
    "22\t0.0.0.0\tany\t0\t\t\t0\tsystem\t\tport 22",
    "22\t[::]\tany\t0\t\t\t0\tsystem\t\tport 22",
    "80\t100.103.142.87\ttailnet\t0\t\t\t0\tsystem\tcaddy-dev-http.socket\tport 80",
    "80\t127.0.0.1\tloopback\t0\t\t\t0\tsystem\tcaddy-dev-http.socket\tport 80",
    "443\t127.0.0.1\tloopback\t0\t\t\t0\tsystem\tcaddy-dev-https.socket\tport 443",
    "1025\t127.0.0.1\tloopback\t0\t\t\t0\tsystem\tmailpit-smtp-proxy.socket\tport 1025",
    "3306\t127.0.0.1\tloopback\t0\t\t\t0\tsystem\tmysql84-proxy.socket\tport 3306",
    "5432\t127.0.0.1\tloopback\t0\t\t\t0\tsystem\tpostgres18-proxy.socket\tport 5432",
    "8025\t127.0.0.1\tloopback\t0\t\t\t0\tsystem\tmailpit-web-proxy.socket\tport 8025",
    "8787\t127.0.0.1\tloopback\t1094\thub\t\t9001\tself\thub.service\thub",
    "8787\t100.103.142.87\ttailnet\t0\t\t\t0\tsystem\t\tport 8787",
    "63581\t[fd7a:115c:a1e0::6034:8e58]\ttailnet\t0\t\t\t0\tsystem\t\tport 63581",
    "5173\t0.0.0.0\tany\t4211\tnode\t/home/saiful/Sites/laravel/shopfront\t370204\tself\t\tshopfront"
].join("\n");

const rows = Model.parseRows(TSV);
const byPort = port => rows.find(r => r.port === port);
const vite = byPort(5173);
const mysql = byPort(3306);
const HOME = "/home/saiful";

// ------------------------------------------------------------------ parsing

test("every listener parses, keeping its column meanings", () => {
    assert.equal(rows.length, 13);
    assert.equal(vite.port, 5173);
    assert.equal(vite.comm, "node");
    assert.equal(vite.cwd, "/home/saiful/Sites/laravel/shopfront");
    assert.equal(vite.owner, "self");
    assert.equal(vite.pid, 4211);
    assert.equal(vite.start, "370204");
});

test("a root-owned socket has no pid, cwd or start", () => {
    assert.equal(mysql.pid, 0);
    assert.equal(mysql.cwd, "");
    assert.equal(mysql.start, "0");
    assert.equal(mysql.owner, "system");
});

test("junk rows are dropped", () => {
    assert.deepEqual(Model.parseRows(""), []);
    assert.deepEqual(Model.parseRows("not-a-port\tx"), []);
    assert.deepEqual(Model.parseRows("0\t127.0.0.1\tloopback"), []);
});

// ------------------------------------------------------- declared vs started

test("a socket unit or an unattributable owner means declared", () => {
    assert.equal(Model.isDeclared(byPort(3306)), true, "mysql socket unit");
    assert.equal(Model.isDeclared(byPort(22)), true, "root daemon, no unit");
    assert.equal(Model.isDeclared(vite), false, "ours, no unit — you started it");
});

test("a user service that holds its own socket is still declared", () => {
    // hub.service is attributable to us AND has a unit: bin/ports only fills
    // that column when the process is the unit's MainPID, so a dev server
    // launched inside a terminal cannot pick it up by accident.
    const hub = rows.find(r => r.port === 8787 && r.owner === "self");
    assert.equal(hub.unit, "hub.service");
    assert.equal(Model.isDeclared(hub), true);
});

test("the default list is only what you started", () => {
    const shown = Model.rank(rows, "").map(r => r.port);
    assert.deepEqual(shown, [5173], "the vite server, and nothing else");
});

test("a declared service bound wide is NOT forced into the list", () => {
    // sshd on 0.0.0.0 is deliberate and in the manifest; permanently
    // colouring it as a warning is the noise this filter removes. The bar
    // tooltip still counts it.
    assert.equal(Model.isExposed(byPort(22)), true);
    assert.ok(!Model.rank(rows, "").some(r => r.port === 22));
    assert.ok(Model.tooltipText(rows).includes("reachable off this machine"));
});

test("a query reaches everything the filter hid", () => {
    assert.deepEqual(Model.rank(rows, "3306").map(r => r.port), [3306]);
    // …and by the name you actually think in, not just the number.
    assert.deepEqual(Model.rank(rows, "mysql").map(r => r.port), [3306]);
    assert.deepEqual(Model.rank(rows, "mailpit").map(r => r.port).sort((a, b) => a - b), [1025, 8025]);
});

// ------------------------------------------------------------ port grouping

test("one row per port, not per bind address", () => {
    const grouped = Model.groupByPort(rows);
    assert.equal(rows.length, 13);
    assert.equal(grouped.length, 10, "22, 80 and 8787 each collapse");
    assert.equal(grouped.filter(r => r.port === 22).length, 1);
});

test("a group keeps the widest scope", () => {
    // 8787 listens on loopback and on the tailnet; who can reach it is the
    // tailnet answer.
    const g = Model.groupByPort(rows).find(r => r.port === 8787);
    assert.equal(g.scope, "tailnet");
    assert.equal(g.binds, 2);
});

test("a group keeps the member a process could be named for", () => {
    // The loopback socket is the one ss can attribute; it must not be lost
    // behind the tailnet row it cannot.
    const g = Model.groupByPort(rows).find(r => r.port === 8787);
    assert.equal(g.comm, "hub");
    assert.equal(g.pid, 1094);
    assert.equal(g.unit, "hub.service");
});

test("a transient unit does not make a listener declared", () => {
    // bin/app-run wraps every launch in its own `app-<cmd>-<random>.service`.
    // Those are filtered out on the bash side (systemd's Transient property),
    // so they reach the model with an empty unit and read as yours — which is
    // what they are. This asserts the contract that filtering has happened.
    const viaAppRun = Object.assign({}, vite, { port: 4322, unit: "" });
    assert.equal(Model.isDeclared(viaAppRun), false);
    // Had it arrived with the transient unit name still attached, it would
    // wrongly have been treated as infrastructure.
    assert.equal(Model.isDeclared(Object.assign({}, viaAppRun, { unit: "app-node-2520213785.service" })), true);
});

test("grouping an empty list is empty, not a crash", () => {
    assert.deepEqual(Model.groupByPort([]), []);
    assert.deepEqual(Model.groupByPort(null), []);
});

// ------------------------------------------------------------------ killing

test("only our own processes are killable", () => {
    assert.equal(Model.isKillable(vite), true);
    assert.equal(Model.isKillable(mysql), false, "root-owned");
});

test("a row missing its start time is not killable", () => {
    // Without the start time the PID-reuse guard cannot be satisfied, so
    // offering the action would only produce a refusal.
    assert.equal(Model.isKillable(Object.assign({}, vite, { start: "0" })), false);
    assert.equal(Model.isKillable(Object.assign({}, vite, { pid: 0 })), false);
    assert.equal(Model.isKillable(null), false);
});

// -------------------------------------------------------------------- scope

test("exposure is what is reachable from off this machine", () => {
    assert.equal(Model.isExposed(byPort(22)), true, "0.0.0.0");
    assert.equal(Model.isExposed(vite), true, "a dev server on every interface");
    assert.equal(Model.isExposed(mysql), false, "loopback");
    assert.equal(Model.isExposed(byPort(80)), false, "tailnet is not the open network");
});

test("scopes read as sentences", () => {
    assert.equal(Model.scopeLabel(mysql), "this machine only");
    assert.equal(Model.scopeLabel(byPort(80)), "tailnet");
    assert.equal(Model.scopeLabel(byPort(22)), "every interface");
    assert.equal(Model.scopeLabel({ scope: "lan" }), "local network");
});

// --------------------------------------------------------------------- URLs

test("loopback and wildcard binds are addressed as localhost", () => {
    // Pointing a browser at 0.0.0.0 works by accident on Linux and not at
    // all elsewhere.
    assert.equal(Model.urlFor(vite), "http://localhost:5173");
    assert.equal(Model.urlFor({ port: 3000, bind: "127.0.0.1", scope: "loopback" }), "http://localhost:3000");
});

test("a specific address is used as given", () => {
    assert.equal(Model.urlFor(byPort(80)), "http://100.103.142.87");
});

test("the default ports drop their number", () => {
    assert.equal(Model.urlFor({ port: 80, bind: "127.0.0.1", scope: "loopback" }), "http://localhost");
    assert.equal(Model.urlFor({ port: 443, bind: "127.0.0.1", scope: "loopback" }), "https://localhost");
});

test("non-HTTP services are not offered to a browser", () => {
    assert.equal(Model.urlFor(mysql), "", "mysql");
    assert.equal(Model.urlFor(byPort(5432)), "", "postgres");
    assert.equal(Model.urlFor(byPort(1025)), "", "smtp");
    assert.equal(Model.urlFor(byPort(22)), "", "ssh");
    // …but mailpit's web UI on 8025 is HTTP and should be.
    assert.equal(Model.urlFor(byPort(8025)), "http://localhost:8025");
});

// ---------------------------------------------------------------- filtering

test("a query hits the port, command, project and scope", () => {
    assert.ok(Model.matches(vite, "5173"));
    assert.ok(Model.matches(vite, "node"));
    assert.ok(Model.matches(vite, "shopfront"));
    assert.ok(Model.matches(vite, "any"));
    assert.ok(!Model.matches(vite, "postgres"));
});

test("all terms must match, in any order", () => {
    assert.ok(Model.matches(vite, "node shopfront"));
    assert.ok(Model.matches(vite, "shopfront node"));
    assert.ok(!Model.matches(vite, "node redis"));
});

// ----------------------------------------------------------------- ordering

test("our own processes lead, then port order", () => {
    // Under a query, where the declared ones are visible again. "1" matches
    // 5173 and 1025; the one you started leads despite the higher number,
    // which is the whole point of the ordering.
    const order = Model.rank(rows, "1").map(r => r.port);
    assert.equal(order[0], 5173, "ours first, not numerically first");
    assert.ok(order.indexOf(1025) > 0);
    // Among declared rows the order is numeric.
    const declared = Model.rank(rows, "port").map(r => r.port);
    assert.deepEqual(declared, declared.slice().sort((a, b) => a - b));
});

test("filtering narrows without changing the ordering rule", () => {
    const order = Model.rank(rows, "loopback").map(r => r.port);
    assert.deepEqual(order, [443, 1025, 3306, 5432, 8025]);
});

// -------------------------------------------------------------------- prose

test("the detail line abbreviates home", () => {
    assert.equal(Model.detailText(vite, HOME), "node · ~/Sites/laravel/shopfront");
});

test("a system service says so instead of showing a blank", () => {
    assert.equal(Model.detailText(mysql, HOME), "system service");
});

test("a home-relative path is only abbreviated when it is under home", () => {
    const elsewhere = Object.assign({}, vite, { cwd: "/opt/thing" });
    assert.equal(Model.detailText(elsewhere, HOME), "node · /opt/thing");
});

test("the hero says what it is showing and what it hid", () => {
    assert.equal(Model.heroMeta(rows, 1, ""), "1 listener · 9 services hidden");
    assert.equal(Model.heroMeta(rows, 2, "port"), "2 of 10 listeners");
    assert.equal(Model.heroMeta([], 0, ""), "Nothing listening");
    // Nothing of your own running is the ordinary state, and says so.
    const declaredOnly = rows.filter(r => Model.isDeclared(r));
    assert.equal(Model.heroMeta(declaredOnly, 0, ""), "Nothing you started · 9 services hidden");
});

test("the tooltip counts every port and flags exposure", () => {
    // Counted over grouped ports, and it never under-reports: the bar icon is
    // the passive view, so the exposure warning has to survive the filter.
    assert.equal(Model.tooltipText(rows), "Ports — 10 listeners, 1 yours · 2 reachable off this machine");
    assert.equal(Model.tooltipText([mysql]), "Ports — 1 listener, none of them yours");
    assert.equal(Model.tooltipText([]), "Ports — nothing listening");
});

test("the unit is rendered without its systemd suffix", () => {
    assert.equal(Model.unitText(byPort(3306)), "mysql84-proxy");
    assert.equal(Model.unitText(vite), "", "nothing declared it");
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

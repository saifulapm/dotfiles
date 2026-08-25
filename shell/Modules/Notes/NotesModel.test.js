// Unit tests for NotesModel.js. Run with:
//
//     node shell/Modules/Notes/NotesModel.test.js
//
// NotesModel.js is dependency-free so these run under plain node; `node
// <file>` is the runner, as with the bar widget model tests. The v1 fixture
// mirrors this machine's real pre-migration store shape.

const assert = require("node:assert/strict");
const Model = require("./NotesModel.js");

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

const V1 = JSON.stringify({
    version: 1,
    notes: [
        { id: 1, text: "Shopify themes monorepo", path: "", done: false },
        { id: 3, text: "", path: "/home/saiful/doc.pdf", done: true },
        { id: 4, text: "", path: "", done: false } // invalid: no content
    ]
});

// ---------------------------------------------------------------- migration

test("v1 parses and migrates: l-prefixed ids, epoch updatedAt", () => {
    const notes = Model.parseNotes(V1);
    assert.equal(notes.length, 2);
    assert.equal(notes[0].id, "l1");
    assert.equal(notes[0].updatedAt, Model.EPOCH);
    assert.equal(notes[1].id, "l3");
    assert.equal(notes[1].done, true);
});

test("v1 migration is deterministic — two parses are identical", () => {
    assert.deepEqual(Model.parseNotes(V1), Model.parseNotes(V1));
});

test("v2 roundtrips through serialize/parse", () => {
    const notes = Model.parseNotes(V1);
    assert.deepEqual(Model.parseNotes(Model.serialize(notes)), notes);
});

test("garbage and blank input parse to empty", () => {
    assert.deepEqual(Model.parseNotes(""), []);
    assert.deepEqual(Model.parseNotes("not json"), []);
    assert.deepEqual(Model.parseNotes('{"version":9,"notes":[]}'), []);
});

// -------------------------------------------------------------------- notes

test("makeNote mints a timestamped unique string id", () => {
    const a = Model.makeNote("hello", "");
    const b = Model.makeNote("world", "");
    assert.match(a.id, /^[0-9a-z]{9}-[0-9a-z]+$/);
    assert.notEqual(a.id, b.id);
    assert.ok(a.updatedAt > Model.EPOCH);
});

test("toggleDone flips and stamps updatedAt", () => {
    const notes = Model.parseNotes(V1);
    const toggled = Model.toggleDone(notes, "l1");
    assert.equal(toggled[0].done, true);
    assert.ok(toggled[0].updatedAt > Model.EPOCH);
    assert.equal(toggled[1].updatedAt, Model.EPOCH); // untouched row unstamped
});

test("removeNote leaves a content-free tombstone", () => {
    const notes = Model.removeNote(Model.parseNotes(V1), "l3");
    const t = Model.findNote(notes, "l3");
    assert.ok(t.deletedAt);
    assert.equal(t.text, "");
    assert.equal(t.path, "");
    assert.equal(Model.liveNotes(notes).length, 1);
});

test("displayRows skips tombstones", () => {
    const notes = Model.removeNote(Model.parseNotes(V1), "l1");
    const rows = Model.displayRows(notes, "");
    assert.equal(rows.length, 1);
    assert.equal(rows[0].noteId, "l3");
});

// -------------------------------------------------------------------- merge

const NOW = Date.parse("2026-08-26T00:00:00.000Z");
const note = (id, text, updatedAt, extra) => Model.normalizeNote(Object.assign({
    id, text, path: "", done: false, updatedAt
}, extra || {}));

test("merge unions distinct notes from both machines", () => {
    const merged = Model.mergeStores([
        [note("l1", "shared", Model.EPOCH), note("00000000a-x1", "mine", "2026-08-20T00:00:00.000Z")],
        [note("l1", "shared", Model.EPOCH), note("00000000b-y1", "theirs", "2026-08-21T00:00:00.000Z")]
    ], NOW);
    assert.deepEqual(merged.map(n => n.text), ["shared", "mine", "theirs"]);
});

test("newest updatedAt wins per id", () => {
    const merged = Model.mergeStores([
        [note("l1", "x", "2026-08-20T00:00:00.000Z", { done: false })],
        [note("l1", "x", "2026-08-21T00:00:00.000Z", { done: true })]
    ], NOW);
    assert.equal(merged.length, 1);
    assert.equal(merged[0].done, true);
});

test("a newer tombstone beats a live note, both list orders", () => {
    const live = note("l1", "x", "2026-08-20T00:00:00.000Z");
    const dead = note("l1", "", "2026-08-21T00:00:00.000Z", { deletedAt: "2026-08-21T00:00:00.000Z" });
    for (const lists of [[[live], [dead]], [[dead], [live]]]) {
        const merged = Model.mergeStores(lists, NOW);
        assert.equal(merged.length, 1);
        assert.ok(merged[0].deletedAt);
    }
});

test("equal-time tie resolves the same whichever side is local", () => {
    const a = note("l1", "x", Model.EPOCH, { done: true });
    const b = note("l1", "x", Model.EPOCH, { done: false });
    const one = Model.mergeStores([[a], [b]], NOW);
    const two = Model.mergeStores([[b], [a]], NOW);
    assert.deepEqual(one, two);
});

test("tombstones prune after the TTL, survive within it", () => {
    const fresh = note("l1", "", "2026-08-20T00:00:00.000Z", { deletedAt: "2026-08-20T00:00:00.000Z" });
    const stale = note("l2", "", "2026-06-01T00:00:00.000Z", { deletedAt: "2026-06-01T00:00:00.000Z" });
    const merged = Model.mergeStores([[fresh, stale]], NOW);
    assert.deepEqual(merged.map(n => n.id), ["l1"]);
});

test("merge order: legacy notes by number, then v2 by timestamp id", () => {
    const merged = Model.mergeStores([[
        note("00000000b-zz", "later", "2026-08-01T00:00:00.000Z"),
        note("l10", "ten", Model.EPOCH),
        note("l2", "two", Model.EPOCH),
        note("00000000a-aa", "earlier", "2026-08-01T00:00:00.000Z")
    ]], NOW);
    assert.deepEqual(merged.map(n => n.text), ["two", "ten", "earlier", "later"]);
});

test("merge is idempotent — merging the merge changes nothing", () => {
    const lists = [Model.parseNotes(V1), [note("00000000a-aa", "solo", "2026-08-01T00:00:00.000Z")]];
    const once = Model.mergeStores(lists, NOW);
    assert.deepEqual(Model.mergeStores([once], NOW), once);
});

process.exit(failures > 0 ? 1 : 0);

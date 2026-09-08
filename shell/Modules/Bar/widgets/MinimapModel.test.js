// Unit tests for MinimapModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/MinimapModel.test.js
//
// The window map below is a real `niri msg --json windows` capture from this
// MacBook (2026-09-08, five workspaces, 3490x1963 logical), reshaped into the
// entries Services/Niri.qml stores: tile widths of 1730 are the machine's
// half-screen columns, and the stacked pair on workspace 7 was added by hand
// (id 12/13) — the capture had none, and a column holding two tiles is the
// case the pill subdivision exists for.

const assert = require("node:assert/strict");
const Model = require("./MinimapModel.js");

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

const SCREEN = 3490;
const HALF = 1730;

const WINDOWS = {
    3: { title: "~/S/g/shopify_apps", appId: "foot", workspaceId: 1, floating: false, column: 1, tile: 1, tileWidth: HALF },
    7: { title: "✳ relay-core execution", appId: "ssh-nuc", workspaceId: 4, floating: false, column: 1, tile: 1, tileWidth: HALF },
    10: { title: "Sonnet 5 vs GLM 5.3 - Google Search - Chromium", appId: "chromium-browser", workspaceId: 5, floating: false, column: 2, tile: 1, tileWidth: HALF },
    11: { title: "◑ Niri minimap and workspace-scoped chromium", appId: "foot", workspaceId: 5, floating: false, column: 1, tile: 1, tileWidth: HALF },
    // A sign-in popup: chromium's app-id, floating, no place in the layout.
    12: { title: "Sign in - Google Accounts - Chromium", appId: "chromium-browser", workspaceId: 5, floating: true, column: 0, tile: 0, tileWidth: 0 },
    // Workspace 7: one full-width column of two stacked tiles.
    13: { title: "kak ~/.dotfiles", appId: "foot", workspaceId: 7, floating: false, column: 1, tile: 2, tileWidth: SCREEN },
    14: { title: "btop", appId: "foot", workspaceId: 7, floating: false, column: 1, tile: 1, tileWidth: SCREEN }
};

// --------------------------------------------------------------- grouping

test("a workspace's tiled windows group into columns, left to right", () => {
    const columns = Model.columnsOf(WINDOWS, 5);
    assert.equal(columns.length, 2);
    assert.deepEqual(columns.map(c => c.index), [1, 2]);
    assert.deepEqual(columns.map(c => c.tiles[0].id), [11, 10]);
});

test("windows on other workspaces are not in this strip", () => {
    assert.equal(Model.columnsOf(WINDOWS, 1).length, 1);
    assert.equal(Model.columnsOf(WINDOWS, 6).length, 0, "an empty workspace draws nothing");
});

test("a floating window has no column, so no pill", () => {
    const ids = Model.columnsOf(WINDOWS, 5).flatMap(c => c.tiles.map(t => t.id));
    assert.ok(!ids.includes(12), "the sign-in popup is left out");
});

test("a stacked column keeps its tiles in top-to-bottom order", () => {
    const columns = Model.columnsOf(WINDOWS, 7);
    assert.equal(columns.length, 1);
    assert.deepEqual(columns[0].tiles.map(t => t.id), [14, 13]);
});

// ------------------------------------------------------------------ labels

test("a tooltip label is the title, falling back to the app id", () => {
    assert.equal(Model.label("", "chromium-browser"), "chromium-browser");
    assert.equal(Model.label("btop", "foot"), "btop");
});

test("a long title is cut rather than handed whole to the tooltip", () => {
    const long = "x".repeat(200);
    assert.equal(Model.label(long, "chromium-browser").length, Model.MAX_LABEL);
    assert.ok(Model.label(long, "chromium-browser").endsWith("…"));
});

// ---------------------------------------------------------------- geometry

test("two half-screen columns take half the budget each, gaps included", () => {
    const strip = Model.strip(Model.columnsOf(WINDOWS, 5), SCREEN, 120);
    const lengths = strip.map(c => c.tiles[0].length);
    assert.deepEqual(lengths, [57, 57]);
    const total = lengths.reduce((a, b) => a + b, 0) + Model.COLUMN_GAP;
    assert.ok(total <= 120, `strip is ${total}px, over the 120px budget`);
});

test("one half-screen column draws half a strip — the rest is room on screen", () => {
    const strip = Model.strip(Model.columnsOf(WINDOWS, 1), SCREEN, 120);
    assert.equal(strip[0].tiles[0].length, 59);
});

test("a workspace wider than the screen fills the budget", () => {
    // Four half-screen columns: 6920px of layout on a 3490px screen, two of
    // them parked off the edges.
    const wide = {};
    for (let i = 1; i <= 4; i++)
        wide[i] = { title: `w${i}`, appId: "foot", workspaceId: 9, floating: false, column: i, tile: 1, tileWidth: HALF };
    const strip = Model.strip(Model.columnsOf(wide, 9), SCREEN, 120);
    const total = strip.reduce((sum, c) => sum + c.tiles[0].length, 0) + Model.COLUMN_GAP * 3;
    assert.equal(strip.length, 4);
    assert.ok(total >= 115 && total <= 120, `${total}px should fill the 120px budget`);
});

test("a stacked column subdivides its own pill, not the strip", () => {
    const strip = Model.strip(Model.columnsOf(WINDOWS, 7), SCREEN, 120);
    assert.equal(strip.length, 1);
    assert.deepEqual(strip[0].tiles.map(t => t.length), [59, 59]);
    assert.ok(59 * 2 + Model.TILE_GAP <= 120, "both halves plus their gap stay inside the budget");
});

test("a sliver of a column is still a visible, clickable pill", () => {
    const sliver = {
        1: { title: "a", appId: "foot", workspaceId: 9, floating: false, column: 1, tile: 1, tileWidth: 4 },
        2: { title: "b", appId: "foot", workspaceId: 9, floating: false, column: 2, tile: 1, tileWidth: SCREEN - 4 }
    };
    const strip = Model.strip(Model.columnsOf(sliver, 9), SCREEN, 120);
    assert.equal(strip[0].tiles[0].length, Model.MIN_PILL);
});

test("no screen width yet: the layout itself sets the scale", () => {
    const strip = Model.strip(Model.columnsOf(WINDOWS, 5), 0, 120);
    const total = strip.reduce((sum, c) => sum + c.tiles[0].length, 0) + Model.COLUMN_GAP;
    assert.ok(total >= 115 && total <= 120, `${total}px should fill the budget`);
});

// ------------------------------------------------------------- change guard

test("a retitled window rebuilds a different strip, a redrawn one does not", () => {
    const before = Model.build(WINDOWS, 5, SCREEN, 120);
    assert.ok(Model.same(before, Model.build(WINDOWS, 5, SCREEN, 120)), "same input, same strip");

    const retitled = Object.assign({}, WINDOWS, {
        10: Object.assign({}, WINDOWS[10], { title: "Anthropic - Google Search - Chromium" })
    });
    assert.ok(!Model.same(before, Model.build(retitled, 5, SCREEN, 120)), "the tooltip changed");

    const resized = Object.assign({}, WINDOWS, {
        10: Object.assign({}, WINDOWS[10], { tileWidth: 2000 }),
        11: Object.assign({}, WINDOWS[11], { tileWidth: 1490 })
    });
    assert.ok(!Model.same(before, Model.build(resized, 5, SCREEN, 120)), "the columns moved");

    // The animation case: a resize too small to move a rounded pill must not
    // churn the delegates.
    const nudged = Object.assign({}, WINDOWS, {
        10: Object.assign({}, WINDOWS[10], { tileWidth: HALF + 4 }),
        11: Object.assign({}, WINDOWS[11], { tileWidth: HALF - 4 })
    });
    assert.ok(Model.same(before, Model.build(nudged, 5, SCREEN, 120)), "sub-pixel resize, same strip");
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

// Minimap model — the pill strip behind the minimap widget, as pure
// functions so they can be checked under node (MinimapModel.test.js) without
// a Quickshell runtime.
//
// Input is the Niri service's window map, id -> { title, appId, workspaceId,
// floating, column, tile, tileWidth }: one entry per window in the session,
// with niri's 1-based [column, tile] position in the scrolling layout and the
// tile's width in logical pixels. Output is one entry per COLUMN of the asked
// workspace, in left-to-right order, each holding its tiles top to bottom —
// which is what the widget repeats over.

// Gaps inside the strip, in pixels: a wider one between columns than between
// two tiles of the same column, so a stacked column still reads as one
// column.
var COLUMN_GAP = 5;
var TILE_GAP = 2;
// A pill never shrinks below this, however narrow its column: the strip is a
// row of click targets, and a 1 px one cannot be hit or seen.
var MIN_PILL = 6;
// Tooltip titles are whole window titles — a browser tab's can be a
// paragraph, and the bar's tooltip bubble is as wide as its text.
var MAX_LABEL = 60;

function label(title, appId) {
    var text = String(title || "").trim() || String(appId || "").trim();
    if (text.length <= MAX_LABEL)
        return text;
    // .replace, not .trimEnd: Qt's JS engine has no String.trimEnd, and a
    // missing method there is a runtime TypeError per window per event.
    return text.slice(0, MAX_LABEL - 1).replace(/\s+$/, "") + "…";
}

// The tiled windows of one workspace, grouped into columns. Floating windows
// and anything niri has not placed in the scrolling layout are left out:
// they have no column to draw.
function columnsOf(windows, workspaceId) {
    var byColumn = {};
    for (var key in windows) {
        var w = windows[key];
        if (!w || w.workspaceId !== workspaceId || w.floating || !(w.column > 0))
            continue;
        if (!byColumn[w.column])
            byColumn[w.column] = [];
        byColumn[w.column].push({
            id: Number(key),
            tile: w.tile || 0,
            width: w.tileWidth || 0,
            label: label(w.title, w.appId)
        });
    }
    return Object.keys(byColumn).map(Number).sort(function (a, b) {
        return a - b;
    }).map(function (index) {
        var tiles = byColumn[index].sort(function (a, b) {
            return a.tile - b.tile || a.id - b.id;
        });
        return {
            index: index,
            width: tiles[0].width,
            tiles: tiles
        };
    });
}

// Pill lengths for one strip, mapped onto a fixed `budget` of bar space.
//
// What the budget maps ONTO is the point: a workspace narrower than the
// screen draws a strip shorter than the budget (the empty part is the room
// left on screen), and one wider than the screen — the scrolling case, where
// columns are parked off both edges — fills the budget exactly and divides
// it between however many columns there are. So the strip's own length says
// "everything fits" or "there is more than a screenful here", and the pill
// widths stay proportional to what each column takes of the screen.
function strip(columns, screenWidth, budget) {
    var total = columns.reduce(function (sum, col) {
        return sum + col.width;
    }, 0);
    var span = Math.max(screenWidth > 0 ? screenWidth : 0, total, 1);
    // The gaps between columns come out of the budget, not on top of it: the
    // widget reserves exactly `budget` of bar width whatever the workspace
    // holds, and a strip drawn wider than that would spill into its
    // neighbours. Tile gaps do not — they are subdivisions of a column pill.
    var available = Math.max(MIN_PILL, budget - COLUMN_GAP * Math.max(0, columns.length - 1));
    var scale = available / span;
    return columns.map(function (col) {
        var width = Math.max(MIN_PILL, Math.round(col.width * scale));
        var count = col.tiles.length;
        var each = Math.max(2, Math.floor((width - TILE_GAP * (count - 1)) / count));
        return {
            index: col.index,
            tiles: col.tiles.map(function (tile) {
                return {
                    id: tile.id,
                    label: tile.label,
                    length: each
                };
            })
        };
    });
}

function build(windows, workspaceId, screenWidth, budget) {
    return strip(columnsOf(windows, workspaceId), screenWidth, budget);
}

// Whether two strips would draw identically. Every window event bumps the
// service's revision — a terminal retitling itself is one — so the widget
// rebuilds far more often than the strip actually changes, and re-assigning
// an equal strip would destroy and recreate every delegate for nothing
// (Workspaces' sameIds rule, same reason).
function same(a, b) {
    if (!a || !b || a.length !== b.length)
        return false;
    return a.every(function (col, i) {
        var other = b[i];
        if (col.index !== other.index || col.tiles.length !== other.tiles.length)
            return false;
        return col.tiles.every(function (tile, j) {
            return tile.id === other.tiles[j].id && tile.length === other.tiles[j].length && tile.label === other.tiles[j].label;
        });
    });
}

if (typeof module !== "undefined") {
    module.exports = {
        COLUMN_GAP: COLUMN_GAP,
        TILE_GAP: TILE_GAP,
        MIN_PILL: MIN_PILL,
        MAX_LABEL: MAX_LABEL,
        build: build,
        columnsOf: columnsOf,
        label: label,
        same: same,
        strip: strip
    };
}

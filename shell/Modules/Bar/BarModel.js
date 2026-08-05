// Bar interaction math, ported from omarchy's plugins/bar/BarModel.js
// (CREDITS.md). Pure functions only, so they can be unit-tested under node:
//   node -e 'const M = require("./BarModel.js"); …'
//
// Our layout lives directly under shell.json's `bar` ({left, center, right}
// arrays), not under a `bar.layout` sub-object as theirs does, so the entry
// helpers take a section map rather than a whole config.

function isPlainObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

// Layout entries are plain widget-id strings ("clock") or inline settings
// objects ({"id": "clock", …}).
function entryId(entry) {
    if (typeof entry === "string")
        return entry;
    if (isPlainObject(entry)) {
        const id = entry["id"];
        if (id !== undefined && id !== null && String(id) !== "")
            return String(id);
    }
    return "";
}

function entryIndex(entries, name) {
    if (!Array.isArray(entries))
        return -1;
    for (let i = 0; i < entries.length; i++) {
        if (entryId(entries[i]) === name)
            return i;
    }
    return -1;
}

// Only top and bottom this pass: the vertical bar (their left/right, with the
// stacked module lists and the rotated labels that come with it) is a later
// piece of work, so a stored "left"/"right" is not a position we can render.
function normalizePosition(value) {
    const next = String(value || "").trim();
    return next === "bottom" ? "bottom" : "top";
}

// Split the screen along its diagonals (in normalized space, so widescreens
// don't bias toward left/right): whichever triangle holds the cursor names the
// candidate edge. Verbatim from theirs.
function nearestScreenEdge(point, screenWidth, screenHeight) {
    const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
    const nx = screenWidth > 0 ? clamp(point.x / screenWidth, 0, 1) : 0.5;
    const ny = screenHeight > 0 ? clamp(point.y / screenHeight, 0, 1) : 0.5;

    let edge = "top";
    let best = ny;
    if (1 - ny < best) {
        edge = "bottom";
        best = 1 - ny;
    }
    if (nx < best) {
        edge = "left";
        best = nx;
    }
    if (1 - nx < best) {
        edge = "right";
        best = 1 - nx;
    }
    return edge;
}

// With no vertical bar to move to, a left/right result is folded onto the
// nearer horizontal edge instead of being dropped: dragging into the left half
// of the screen still reads as "put the bar where I am pointing", and ignoring
// it would make the gesture feel broken over most of the screen.
function horizontalEdge(point, screenWidth, screenHeight) {
    const edge = nearestScreenEdge(point, screenWidth, screenHeight);
    if (edge === "top" || edge === "bottom")
        return edge;
    return screenHeight > 0 && point.y > screenHeight / 2 ? "bottom" : "top";
}

// Resolve a pointer anywhere along the bar to the closest insertion edge.
// Requiring the pointer to sit inside another widget makes the empty space
// around a centered group a dead zone, even though it visually reads as the
// most natural place to drop. Verbatim from theirs, minus the vertical axis.
function nearestDropTarget(candidates, point) {
    const rows = Array.isArray(candidates) ? candidates : [];
    const axis = Number(point && point.x);
    if (!isFinite(axis))
        return null;

    let best = null;
    let bestDistance = Infinity;
    for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        if (!row || !row.slot)
            continue;

        const start = Number(row.x);
        const size = Number(row.width);
        if (!isFinite(start) || !isFinite(size) || size <= 0)
            continue;

        const beforeDistance = Math.abs(axis - start);
        const afterDistance = Math.abs(axis - (start + size));
        const after = afterDistance < beforeDistance;
        const distance = after ? afterDistance : beforeDistance;
        if (distance < bestDistance) {
            best = {
                slot: row.slot,
                after: after
            };
            bestDistance = distance;
        }
    }
    return best;
}

// Move one entry between (or within) the section arrays of a bar config, in
// place. Port of their moveModuleInConfig: `beforeId` names the entry the moved
// one lands in front of, and an empty/unknown one appends. Returns false when
// nothing actually moved, so the caller can skip the write.
function moveEntry(bar, fromSection, fromId, toSection, beforeId) {
    if (!isPlainObject(bar))
        return false;
    if (!Array.isArray(bar[fromSection]))
        bar[fromSection] = [];
    if (!Array.isArray(bar[toSection]))
        bar[toSection] = [];

    const fromEntries = bar[fromSection];
    const toEntries = bar[toSection];
    const fromIndex = entryIndex(fromEntries, fromId);
    if (fromIndex < 0)
        return false;

    let toIndex = beforeId ? entryIndex(toEntries, beforeId) : toEntries.length;
    if (toIndex < 0)
        toIndex = toEntries.length;

    if (fromSection === toSection && fromIndex === toIndex)
        return false;

    const moved = fromEntries[fromIndex];
    fromEntries.splice(fromIndex, 1);

    if (fromSection === toSection && fromIndex < toIndex)
        toIndex -= 1;
    if (toIndex < 0)
        toIndex = 0;
    if (toIndex > toEntries.length)
        toIndex = toEntries.length;
    if (fromSection === toSection && fromIndex === toIndex) {
        fromEntries.splice(fromIndex, 0, moved);
        return false;
    }

    toEntries.splice(toIndex, 0, moved);
    return true;
}

if (typeof module !== "undefined") {
    module.exports = {
        entryId: entryId,
        entryIndex: entryIndex,
        normalizePosition: normalizePosition,
        nearestScreenEdge: nearestScreenEdge,
        horizontalEdge: horizontalEdge,
        nearestDropTarget: nearestDropTarget,
        moveEntry: moveEntry
    };
}

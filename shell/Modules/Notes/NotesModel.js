// Store semantics for Modules/Notes — pure JS with no QML types, so the
// shapes run headlessly under node (NotesModel.test.js is the runner, and
// bin/notes-merge requires this file for the cross-machine merge).
//
// Schema version 2 (2026-08-26): a note is
//
//     { id, text, path, done, updatedAt }            a live note
//     { id, text:"", path:"", done:false,
//       updatedAt, deletedAt }                       a tombstone
//
// `id` is a string, unique across machines: 9 base36 chars of creation-time
// milliseconds plus a random suffix, so two machines minting notes in the
// same millisecond still cannot collide. Version-1 stores (numeric ids,
// counted from 1 on every machine) migrate on parse: id n becomes "l" + n,
// IDENTICALLY on every machine — the old stores were bisynced copies of one
// file, so "l7" here and "l7" on the nuc are the same note and the merge
// dedupes them instead of triplicating. `updatedAt` for migrated notes is
// the epoch, so the first real edit anywhere wins the merge.
//
// Deletion is a tombstone, not removal: a note that simply vanished from one
// machine's file would be resurrected by the next union. The tombstone keeps
// the id and the deletion time, drops the content, and is pruned by the
// merge once every machine has had TOMBSTONE_TTL to hear about it. A machine
// offline longer than that can resurrect a deleted note — accepted, same
// class of edge as the ssh unit's conflict rule.
//
// mergeStores() is the cross-machine union bin/notes-merge runs: newest
// updatedAt wins per id, ties resolve deterministically, output sorts
// chronologically (legacy notes keep their v1 order, then v2 notes by the
// timestamp their id starts with) so every machine renders the same list.
//
// `text` is what the user typed (may be empty), `path` an optional
// attachment — a dropped or pasted file, referenced in place except for
// clipboard pastes, which live under the store's attachments dir. Display
// derives a label: the text, or the attachment's basename when there is no
// text and nothing visual to show. Order is chronological, oldest first: new
// notes land at the bottom of the list, next to the capture input that made
// them.

var EPOCH = "1970-01-01T00:00:00.000Z";
var TOMBSTONE_TTL_MS = 30 * 24 * 60 * 60 * 1000;

function nowIso() {
    return new Date().toISOString();
}

// 9 base36 chars hold millisecond timestamps until year ~5138; the random
// suffix separates two notes minted in the same millisecond (a multi-file
// drop) and two machines minting at once.
function newId() {
    var t = Date.now().toString(36);
    while (t.length < 9)
        t = "0" + t;
    return t + "-" + Math.random().toString(36).slice(2, 6);
}

// One key order everywhere: the merge tie-break and the persist-echo check
// both compare serialized forms, so field order is part of the contract.
function normalizeNote(n) {
    var out = {
        id: String(n.id),
        text: String(n.text || ""),
        path: String(n.path || ""),
        done: !!n.done,
        updatedAt: String(n.updatedAt || EPOCH)
    };
    if (n.deletedAt)
        out.deletedAt = String(n.deletedAt);
    return out;
}

function parseNotes(raw) {
    const text = String(raw || "").trim();
    if (!text)
        return [];
    try {
        const parsed = JSON.parse(text);
        if (parsed && parsed.version === 1 && Array.isArray(parsed.notes))
            return parsed.notes.filter(n => n && typeof n === "object" && typeof n.id === "number" && (n.text || n.path)).map(n => normalizeNote({
                id: "l" + n.id,
                text: n.text,
                path: n.path,
                done: n.done,
                updatedAt: EPOCH
            }));
        if (parsed && parsed.version === 2 && Array.isArray(parsed.notes))
            return parsed.notes.filter(n => n && typeof n === "object" && typeof n.id === "string" && n.id && (n.deletedAt || n.text || n.path)).map(normalizeNote);
    } catch (e) {}
    return [];
}

function serialize(notes) {
    return JSON.stringify({
        version: 2,
        notes: notes
    }, null, 2) + "\n";
}

function makeNote(text, path) {
    return normalizeNote({
        id: newId(),
        text: String(text || "").trim(),
        path: String(path || ""),
        done: false,
        updatedAt: nowIso()
    });
}

function addNote(notes, note) {
    return notes.concat([note]);
}

function toggleDone(notes, id) {
    return notes.map(n => n.id === id ? normalizeNote(Object.assign({}, n, {
        done: !n.done,
        updatedAt: nowIso()
    })) : n);
}

// Removal keeps the id as a tombstone so the deletion propagates instead of
// the note resurrecting from another machine's copy on the next merge.
function removeNote(notes, id) {
    const at = nowIso();
    return notes.map(n => n.id === id ? normalizeNote({
        id: n.id,
        text: "",
        path: "",
        done: false,
        updatedAt: at,
        deletedAt: at
    }) : n);
}

function liveNotes(notes) {
    return notes.filter(n => !n.deletedAt);
}

function findNote(notes, id) {
    for (let i = 0; i < notes.length; i++)
        if (notes[i].id === id)
            return notes[i];
    return null;
}

// ------------------------------------------------------------------- merge
// Chronological across machines: legacy ids ("l<n>") keep their v1 order and
// sort before every v2 id, whose base36 timestamp prefix makes the id itself
// the creation-time key.
function sortKey(id) {
    var s = String(id);
    if (s.charAt(0) === "l") {
        var n = parseInt(s.slice(1), 10);
        return "0" + ("00000000000000" + (isNaN(n) ? 0 : n)).slice(-14);
    }
    return "1" + s;
}

// Newest updatedAt wins (both writers stamp UTC ISO of one length, so string
// order IS time order). Ties break deterministically — tombstone first, then
// the larger serialized form — so every machine resolves the same pair the
// same way and the fleet converges instead of ping-ponging.
function wins(a, b) {
    if (a.updatedAt !== b.updatedAt)
        return a.updatedAt > b.updatedAt;
    if (!!a.deletedAt !== !!b.deletedAt)
        return !!a.deletedAt;
    return JSON.stringify(a) > JSON.stringify(b);
}

function mergeStores(lists, nowMs) {
    var byId = {};
    for (var i = 0; i < lists.length; i++) {
        var list = lists[i] || [];
        for (var j = 0; j < list.length; j++) {
            var n = normalizeNote(list[j]);
            var held = byId[n.id];
            if (!held || wins(n, held))
                byId[n.id] = n;
        }
    }
    var out = [];
    for (var id in byId) {
        var n = byId[id];
        if (n.deletedAt && nowMs - Date.parse(n.deletedAt) > TOMBSTONE_TTL_MS)
            continue;
        out.push(n);
    }
    out.sort(function (a, b) {
        var ka = sortKey(a.id), kb = sortKey(b.id);
        return ka < kb ? -1 : (ka > kb ? 1 : 0);
    });
    return out;
}

function isImagePath(path) {
    return /\.(png|jpe?g|webp|gif|bmp|svg|avif)$/i.test(String(path || ""));
}

// Case-insensitive substring over text and path, tombstones skipped. Role
// names are prefixed — `id` itself is unusable as a ListModel role (collides
// with the QML id keyword in a required property). `noteLabel` is the display
// text: the note's own text, or the attachment basename when the row would
// otherwise be blank next to a plain file chip (an image thumbnail speaks for
// itself).
function displayRows(notes, filter) {
    const q = String(filter || "").toLowerCase();
    const rows = [];
    for (let i = 0; i < notes.length; i++) {
        const n = notes[i];
        if (n.deletedAt)
            continue;
        if (q && (String(n.text || "") + " " + String(n.path || "")).toLowerCase().indexOf(q) === -1)
            continue;
        const attach = String(n.path || "");
        const image = isImagePath(attach);
        rows.push({
            noteId: n.id,
            noteLabel: String(n.text || "") || (attach && !image ? baseName(attach) : ""),
            noteAttach: attach,
            noteIsImage: image,
            noteDone: !!n.done
        });
    }
    return rows;
}

function baseName(path) {
    const s = String(path);
    const i = s.lastIndexOf("/");
    return i >= 0 ? s.slice(i + 1) : s;
}

// file:// URL -> filesystem path (drops arrive as URLs).
function urlToPath(url) {
    let s = String(url);
    if (s.indexOf("file://") !== 0)
        return "";
    s = s.slice(7);
    try {
        s = decodeURIComponent(s);
    } catch (e) {}
    return s;
}

// Per-segment encoding, the CardFrost idiom: encodeURI alone leaves `#` and
// `?` live, and a path containing either would truncate the exported URI.
function pathToUri(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
}

if (typeof module !== "undefined") {
    module.exports = {
        EPOCH: EPOCH,
        TOMBSTONE_TTL_MS: TOMBSTONE_TTL_MS,
        addNote: addNote,
        baseName: baseName,
        displayRows: displayRows,
        findNote: findNote,
        isImagePath: isImagePath,
        liveNotes: liveNotes,
        makeNote: makeNote,
        mergeStores: mergeStores,
        newId: newId,
        normalizeNote: normalizeNote,
        parseNotes: parseNotes,
        pathToUri: pathToUri,
        removeNote: removeNote,
        serialize: serialize,
        sortKey: sortKey,
        toggleDone: toggleDone,
        urlToPath: urlToPath
    };
}

// Store semantics for Modules/Notes — pure JS with no QML types, so the
// shapes can be exercised headlessly under node ((0,eval) the file and call
// the functions directly, the ClipboardHistory.js trick).
//
// A note is { id, text, path, done }: `text` is what the user typed (may be
// empty), `path` an optional attachment — a dropped or pasted file,
// referenced in place except for clipboard pastes, which live under the
// store's attachments dir. Display derives a label: the text, or the
// attachment's basename when there is no text and nothing visual to show.
// Order is chronological, oldest first: new notes land at the bottom of the
// list, next to the capture input that made them.

function parseNotes(raw) {
    const text = String(raw || "").trim();
    if (!text)
        return [];
    try {
        const parsed = JSON.parse(text);
        if (parsed && parsed.version === 1 && Array.isArray(parsed.notes))
            return parsed.notes.filter(n => n && typeof n === "object" && typeof n.id === "number" && (n.text || n.path));
    } catch (e) {}
    return [];
}

function serialize(notes) {
    return JSON.stringify({
        version: 1,
        notes: notes
    }, null, 2) + "\n";
}

// Monotonic per-store, not a timestamp: a multi-file drop adds several notes
// in the same millisecond.
function nextId(notes) {
    let max = 0;
    for (let i = 0; i < notes.length; i++)
        if (notes[i].id > max)
            max = notes[i].id;
    return max + 1;
}

function makeNote(id, text, path) {
    return {
        id: id,
        text: String(text || "").trim(),
        path: String(path || ""),
        done: false
    };
}

function addNote(notes, note) {
    return notes.concat([note]);
}

function toggleDone(notes, id) {
    return notes.map(n => n.id === id ? Object.assign({}, n, {
        done: !n.done
    }) : n);
}

function removeNote(notes, id) {
    return notes.filter(n => n.id !== id);
}

function findNote(notes, id) {
    for (let i = 0; i < notes.length; i++)
        if (notes[i].id === id)
            return notes[i];
    return null;
}

function isImagePath(path) {
    return /\.(png|jpe?g|webp|gif|bmp|svg|avif)$/i.test(String(path || ""));
}

// Case-insensitive substring over text and path. Role names are prefixed —
// `id` itself is unusable as a ListModel role (collides with the QML id
// keyword in a required property). `noteLabel` is the display text: the
// note's own text, or the attachment basename when the row would otherwise
// be blank next to a plain file chip (an image thumbnail speaks for itself).
function displayRows(notes, filter) {
    const q = String(filter || "").toLowerCase();
    const rows = [];
    for (let i = 0; i < notes.length; i++) {
        const n = notes[i];
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

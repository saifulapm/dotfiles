// Helpers for the file picker: the portal's filter format, the glyph for a
// row, and the size/time columns. No QML types in here, so it runs under node
// for testing.
//
// Glyphs are Material Design codepoints (U+F0001 and up) — the only Nerd Font
// range that renders under our Symbols Nerd Font fallback.

var FOLDER_GLYPH = "󰉋";
var FOLDER_UP_GLYPH = "󰁭";

var KIND_GLYPHS = {
    image: "󰋩",
    video: "󰕧",
    audio: "󰎈",
    document: "󰈙",
    pdf: "󰈦",
    archive: "󰗄",
    code: "󰅩",
    text: "󰈚",
    font: "󰛖",
    disk: "󰗮",
    binary: "󰘔"
};

var EXTENSION_KINDS = {
    jpg: "image",
    jpeg: "image",
    png: "image",
    gif: "image",
    webp: "image",
    avif: "image",
    heic: "image",
    svg: "image",
    bmp: "image",
    tif: "image",
    tiff: "image",
    ico: "image",
    mp4: "video",
    mkv: "video",
    mov: "video",
    avi: "video",
    webm: "video",
    m4v: "video",
    mpg: "video",
    mpeg: "video",
    mp3: "audio",
    flac: "audio",
    wav: "audio",
    ogg: "audio",
    opus: "audio",
    m4a: "audio",
    aac: "audio",
    pdf: "pdf",
    doc: "document",
    docx: "document",
    odt: "document",
    rtf: "document",
    xls: "document",
    xlsx: "document",
    ods: "document",
    ppt: "document",
    pptx: "document",
    odp: "document",
    zip: "archive",
    tar: "archive",
    gz: "archive",
    bz2: "archive",
    xz: "archive",
    zst: "archive",
    rar: "archive",
    "7z": "archive",
    rpm: "archive",
    deb: "archive",
    js: "code",
    ts: "code",
    jsx: "code",
    tsx: "code",
    qml: "code",
    py: "code",
    rb: "code",
    php: "code",
    go: "code",
    rs: "code",
    c: "code",
    h: "code",
    cpp: "code",
    hpp: "code",
    java: "code",
    kt: "code",
    sh: "code",
    bash: "code",
    json: "code",
    toml: "code",
    yaml: "code",
    yml: "code",
    kdl: "code",
    html: "code",
    css: "code",
    scss: "code",
    txt: "text",
    md: "text",
    log: "text",
    csv: "text",
    ttf: "font",
    otf: "font",
    woff: "font",
    woff2: "font",
    iso: "disk",
    img: "disk"
};

function extensionOf(name) {
    var value = String(name || "");
    var dot = value.lastIndexOf(".");
    if (dot <= 0 || dot === value.length - 1)
        return "";
    return value.substring(dot + 1).toLowerCase();
}

function glyphFor(name, isDir) {
    if (isDir)
        return FOLDER_GLYPH;
    var kind = EXTENSION_KINDS[extensionOf(name)];
    return kind ? KIND_GLYPHS[kind] : KIND_GLYPHS.binary;
}

function kindOf(name) {
    return EXTENSION_KINDS[extensionOf(name)] || "";
}

// The portal hands filters over as shell globs. Anchored, case-insensitive:
// the chooser's own matching is case-sensitive and upstream works around it by
// sending both cases, which we do not need to reproduce.
function globToRegExp(glob) {
    var pattern = String(glob || "");
    var out = "^";
    for (var i = 0; i < pattern.length; i++) {
        var ch = pattern.charAt(i);
        if (ch === "*")
            out += ".*";
        else if (ch === "?")
            out += ".";
        else if ("\\^$.|+()[]{}".indexOf(ch) !== -1)
            out += "\\" + ch;
        else
            out += ch;
    }
    return new RegExp(out + "$", "i");
}

// A portal filter is {name, globs: [...], mimes: [...]}. Mime patterns are
// carried through untouched but only matched loosely, by the extension table
// above — there is no shared mime database in the shell, and a filter nobody
// can satisfy would hide every file.
function matchesFilter(name, filter) {
    if (!filter)
        return true;
    var globs = filter.globs || [];
    var i;
    for (i = 0; i < globs.length; i++) {
        if (globToRegExp(globs[i]).test(String(name || "")))
            return true;
    }
    var mimes = filter.mimes || [];
    for (i = 0; i < mimes.length; i++) {
        var mime = String(mimes[i] || "");
        var slash = mime.indexOf("/");
        var group = slash > 0 ? mime.substring(0, slash) : mime;
        // Filter criteria are OR'd, and a mime outside the mapped groups
        // (application/zip, application/json, ...) is one the extension
        // table can never judge — it must count as a match, or a filter the
        // shell cannot evaluate would blank the whole dialog (against the
        // portal spec's intent).
        if (group !== "image" && group !== "video" && group !== "audio" && group !== "text" && mime !== "application/pdf")
            return true;
        var kind = EXTENSION_KINDS[extensionOf(name)];
        if (!kind)
            continue;
        if (group === "image" && kind === "image")
            return true;
        if (group === "video" && kind === "video")
            return true;
        if (group === "audio" && kind === "audio")
            return true;
        if (group === "text" && (kind === "text" || kind === "code"))
            return true;
        if (mime === "application/pdf" && kind === "pdf")
            return true;
    }
    return globs.length === 0 && mimes.length === 0;
}

function matchesQuery(name, query) {
    var q = String(query || "").trim().toLowerCase();
    if (q === "")
        return true;
    return String(name || "").toLowerCase().indexOf(q) !== -1;
}

function formatSize(bytes) {
    var value = Number(bytes);
    if (!isFinite(value) || value < 0)
        return "";
    if (value < 1000)
        return value + " B";
    var units = ["kB", "MB", "GB", "TB"];
    var index = -1;
    do {
        value /= 1000;
        index += 1;
    } while (value >= 1000 && index < units.length - 1);
    return (value < 10 ? value.toFixed(1) : Math.round(value)) + " " + units[index];
}

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

// Today shows a clock, this year drops the year, older keeps it — the same
// shortening the tray and the recent-files list use.
function formatTime(date, nowMs) {
    if (!date || isNaN(date.getTime && date.getTime()))
        return "";
    var now = new Date(nowMs || Date.now());
    var sameDay = date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
    if (sameDay)
        return pad(date.getHours()) + ":" + pad(date.getMinutes());
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    var stamp = months[date.getMonth()] + " " + pad(date.getDate());
    if (date.getFullYear() !== now.getFullYear())
        stamp += " " + date.getFullYear();
    return stamp;
}

// FolderListModel wants a URL. Percent-encode each segment so a folder with
// a space, a "#" or a "?" in its name is still reachable.
function pathToUrl(path) {
    var value = String(path || "/");
    var parts = value.split("/");
    var encoded = [];
    for (var i = 0; i < parts.length; i++)
        encoded.push(encodeURIComponent(parts[i]));
    return "file://" + encoded.join("/");
}

// Location-entry convention (GTK's ctrl+L, readline): ctrl+L prefills the
// current path, and typing a fresh start after it restarts from there —
// "/a/b//etc" means /etc, "/a/b/~/x" means ~/x. The last restart wins.
function rebaseTyped(input) {
    var value = String(input || "");
    var dbl = value.lastIndexOf("//");
    if (dbl >= 0)
        value = value.substring(dbl + 1);
    var tilde = value.lastIndexOf("~");
    if (tilde > 0 && value.charAt(tilde - 1) === "/")
        value = value.substring(tilde);
    return value;
}

// Collapse // and resolve . / .. — a typed path may contain any of them.
// Absolute input only; returns the cleaned path and whether a trailing
// slash marked it as "definitely a folder".
function normalizePath(path) {
    var value = String(path || "");
    var trailing = value.length > 1 && value.charAt(value.length - 1) === "/";
    var parts = value.split("/");
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        var seg = parts[i];
        if (seg === "" || seg === ".")
            continue;
        if (seg === "..") {
            if (out.length > 0)
                out.pop();
            continue;
        }
        out.push(seg);
    }
    return {
        path: "/" + out.join("/"),
        trailing: trailing
    };
}

function parentOf(path) {
    var value = String(path || "/");
    if (value === "/" || value === "")
        return "/";
    value = value.replace(/\/+$/, "");
    var slash = value.lastIndexOf("/");
    if (slash <= 0)
        return "/";
    return value.substring(0, slash);
}

function joinPath(dir, name) {
    var base = String(dir || "/").replace(/\/+$/, "");
    return base + "/" + String(name || "");
}

function baseName(path) {
    var value = String(path || "").replace(/\/+$/, "");
    if (value === "")
        return "/";
    var slash = value.lastIndexOf("/");
    return slash < 0 ? value : value.substring(slash + 1);
}

// Breadcrumb segments, home-relative where that is shorter to read.
function crumbsFor(path, home) {
    var value = String(path || "/");
    var crumbs = [];
    var homeDir = String(home || "").replace(/\/+$/, "");
    if (homeDir !== "" && (value === homeDir || value.indexOf(homeDir + "/") === 0)) {
        crumbs.push({
            label: "~",
            path: homeDir
        });
        var rest = value.substring(homeDir.length).replace(/^\/+/, "");
        var walked = homeDir;
        if (rest !== "") {
            var parts = rest.split("/");
            for (var i = 0; i < parts.length; i++) {
                if (parts[i] === "")
                    continue;
                walked = walked + "/" + parts[i];
                crumbs.push({
                    label: parts[i],
                    path: walked
                });
            }
        }
        return crumbs;
    }
    crumbs.push({
        label: "/",
        path: "/"
    });
    var segments = value.split("/");
    var current = "";
    for (var j = 0; j < segments.length; j++) {
        if (segments[j] === "")
            continue;
        current = current + "/" + segments[j];
        crumbs.push({
            label: segments[j],
            path: current
        });
    }
    return crumbs;
}

// -------------------------------------------------------------------- sort
// Sorting happens here, in JS, not in FolderListModel: flipping the model's
// sortField re-lists asynchronously with no reliable completion signal,
// while re-sorting the rows we already hold is synchronous and testable.
// Folders stay above files in every order, like every file manager.

function compareNames(a, b) {
    var an = String(a.name).toLowerCase();
    var bn = String(b.name).toLowerCase();
    if (an < bn)
        return -1;
    if (an > bn)
        return 1;
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
}

function sortEntries(rows, field, reversed) {
    var out = rows.slice();
    out.sort(function (a, b) {
        if (a.isDir !== b.isDir)
            return a.isDir ? -1 : 1;
        var cmp;
        if (field === "size")
            // A folder's size column is blank; among folders size order
            // falls back to name.
            cmp = a.isDir ? compareNames(a, b) : (a.size - b.size) || compareNames(a, b);
        else if (field === "time")
            cmp = ((a.modified ? a.modified.getTime() : 0) - (b.modified ? b.modified.getTime() : 0)) || compareNames(a, b);
        else
            cmp = compareNames(a, b);
        return reversed ? -cmp : cmp;
    });
    return out;
}

// ------------------------------------------------------------------ sidebar
// The places column: Home + the XDG user dirs, the user's GTK bookmarks
// (shared with every GTK app), and removable mounts.

var PLACE_GLYPHS = {
    Home: "󰋜",
    Desktop: "󰍹",
    Documents: "󰈙",
    Downloads: "󰇚",
    Music: "󰎈",
    Pictures: "󰋩",
    Videos: "󰕧"
};
var PIN_GLYPH = "󰐃";
var MOUNT_GLYPH = "󰋊";

// One `sh -c` probe per dialog open: which places exist, and what is
// mounted. user-dirs.dirs is shell syntax by design (xdg-user-dirs sources
// it), so sourcing it is the spec'd parse.
function probeScript() {
    return ['home=$HOME', 'conf="$home/.config/user-dirs.dirs"', '[ -r "$conf" ] && . "$conf" 2>/dev/null', 'printf "place\\t%s\\n" "$home"', 'for d in "${XDG_DESKTOP_DIR:-$home/Desktop}" "${XDG_DOCUMENTS_DIR:-$home/Documents}" "${XDG_DOWNLOAD_DIR:-$home/Downloads}" "${XDG_MUSIC_DIR:-$home/Music}" "${XDG_PICTURES_DIR:-$home/Pictures}" "${XDG_VIDEOS_DIR:-$home/Videos}"; do', '  [ -d "$d" ] && [ "$d" != "$home" ] && printf "place\\t%s\\n" "$d"', 'done', 'for d in /run/media/"$(id -un)"/* /media/*; do', '  [ -d "$d" ] && printf "mount\\t%s\\n" "$d"', 'done', 'true'].join("\n");
}

function parsePlaces(probeText, home) {
    var places = [];
    var mounts = [];
    var seen = {};
    var lines = String(probeText || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var tab = lines[i].indexOf("\t");
        if (tab === -1)
            continue;
        var kind = lines[i].substring(0, tab);
        var path = lines[i].substring(tab + 1).replace(/\/+$/, "");
        if (path === "" || seen[path])
            continue;
        seen[path] = true;
        if (kind === "place")
            places.push({
                path: path,
                label: path === home ? "Home" : baseName(path)
            });
        else if (kind === "mount")
            mounts.push({
                path: path,
                label: baseName(path)
            });
    }
    return {
        places: places,
        mounts: mounts
    };
}

// GTK bookmark lines are `file:///percent%20encoded/path Optional Label`.
function parseGtkBookmarks(text) {
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.indexOf("file://") !== 0)
            continue;
        var space = line.indexOf(" ");
        var uri = space === -1 ? line : line.substring(0, space);
        var label = space === -1 ? "" : line.substring(space + 1).trim();
        var path;
        try {
            path = decodeURIComponent(uri.substring(7));
        } catch (e) {
            continue;
        }
        path = path.replace(/\/+$/, "");
        if (path === "")
            continue;
        out.push({
            path: path,
            label: label !== "" ? label : baseName(path)
        });
    }
    return out;
}

// The bookmarks file with `path` pinned if it was not, unpinned if it was.
// Unmatched lines pass through byte-for-byte — this file belongs to GTK as
// much as to us.
function toggleBookmark(text, path) {
    var target = String(path || "").replace(/\/+$/, "");
    var lines = String(text || "").split("\n");
    var kept = [];
    var removed = false;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line === "")
            continue;
        var matched = false;
        if (line.indexOf("file://") === 0) {
            var space = line.indexOf(" ");
            var uri = space === -1 ? line : line.substring(0, space);
            try {
                matched = decodeURIComponent(uri.substring(7)).replace(/\/+$/, "") === target;
            } catch (e) {
            }
        }
        if (matched) {
            removed = true;
            continue;
        }
        kept.push(lines[i]);
    }
    if (!removed && target !== "")
        kept.push(pathToUrl(target));
    return kept.length > 0 ? kept.join("\n") + "\n" : "";
}

// The sidebar flattened to one list: section headers between numbered rows,
// ctrl+1..9 landing on the first nine rows top to bottom.
function sidebarRows(places, pinned, mounts) {
    var rows = [];
    var slot = 0;
    function pushSection(label, items, glyphOf) {
        if (!items || items.length === 0)
            return;
        rows.push({
            kind: "header",
            label: label,
            path: "",
            glyph: "",
            shortcut: 0
        });
        for (var i = 0; i < items.length; i++) {
            slot += 1;
            rows.push({
                kind: "item",
                label: items[i].label,
                path: items[i].path,
                glyph: glyphOf(items[i]),
                shortcut: slot <= 9 ? slot : 0
            });
        }
    }
    pushSection("Places", places, function (item) {
        return PLACE_GLYPHS[item.label] || FOLDER_GLYPH;
    });
    pushSection("Pinned", pinned, function () {
        return PIN_GLYPH;
    });
    pushSection("Devices", mounts, function () {
        return MOUNT_GLYPH;
    });
    return rows;
}

if (typeof module !== "undefined") {
    module.exports = {
        extensionOf: extensionOf,
        glyphFor: glyphFor,
        kindOf: kindOf,
        globToRegExp: globToRegExp,
        matchesFilter: matchesFilter,
        matchesQuery: matchesQuery,
        formatSize: formatSize,
        formatTime: formatTime,
        pathToUrl: pathToUrl,
        rebaseTyped: rebaseTyped,
        normalizePath: normalizePath,
        parentOf: parentOf,
        joinPath: joinPath,
        baseName: baseName,
        crumbsFor: crumbsFor,
        sortEntries: sortEntries,
        probeScript: probeScript,
        parsePlaces: parsePlaces,
        parseGtkBookmarks: parseGtkBookmarks,
        toggleBookmark: toggleBookmark,
        sidebarRows: sidebarRows,
        FOLDER_GLYPH: FOLDER_GLYPH,
        FOLDER_UP_GLYPH: FOLDER_UP_GLYPH
    };
}

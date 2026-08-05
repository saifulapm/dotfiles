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

if (typeof module !== "undefined") {
    module.exports = {
        extensionOf: extensionOf,
        glyphFor: glyphFor,
        globToRegExp: globToRegExp,
        matchesFilter: matchesFilter,
        matchesQuery: matchesQuery,
        formatSize: formatSize,
        formatTime: formatTime,
        pathToUrl: pathToUrl,
        parentOf: parentOf,
        joinPath: joinPath,
        baseName: baseName,
        crumbsFor: crumbsFor,
        FOLDER_GLYPH: FOLDER_GLYPH,
        FOLDER_UP_GLYPH: FOLDER_UP_GLYPH
    };
}

// Hub-sync parsing and phrasing for the sync widget — ours, in the shape of
// the devservices model ( for the family's lineage): the pure data
// the service and the panel read, with no Process and no state of its own.
//
// The input is bin/qshell-sync's status.json (version 2), which is the whole
// contract between the shell and the sync round. Every unit carries its own
// verdict, so the panel can say WHICH half of the sync broke and WHEN each
// half last worked — the questions the old single-ok status could not answer.
//
// Row glyphs are Material Design marks from the installed Symbols Nerd Font,
// each verified present with `fc-list :charset=<cp>` before being used here
// (the devservices catalog established that check).

var UNIT_GLYPHS = {
    "history": "󰆍" // md-console
    ,
    "fish-history": "󰈺" // md-fish
    ,
    "model-usage": "󰚩" // md-robot
    ,
    "screenshots": "󰊾" // md-image_multiple
    ,
    "notes": "󰦨" // md-note_text
    ,
    "ssh": "󰌆" // md-key
    ,
    "memory": "󰧡" // md-brain
    ,
    "parked": "󰏗" // md-package_variant_closed
};

// What each unit is for, in one line — the panel shows it where a unit has
// never run and has nothing more interesting to say about itself.
var UNIT_BLURBS = {
    "history": "Bash history, one file per machine",
    "fish-history": "Fish history, merged from every machine",
    "model-usage": "What the AI widget counts",
    "screenshots": "~/Pictures/Screenshots, both ways",
    "notes": "The notes panel's store, merged by note id",
    "ssh": "~/.ssh as one encrypted blob",
    "memory": "The mem store, both ways",
    "parked": "Parked work bundles, both ways"
};

// Where each unit's content sits on THIS machine, relative to $HOME — what
// the row's folder button opens, so the answer to "what is actually in there"
// is one click rather than a path hunt. These are bin/qshell-sync's own paths
// written down a second time; a unit that moves has to move here too, and a
// unit with no entry simply grows no button rather than opening the wrong
// thing.
//
// Two are not the directory you would guess. The push-own / pull-others units
// keep the hub's copies under the sync state dir rather than beside the live
// data, and that staging dir is the unit: history holds every machine's file
// including ours, fish-history holds only the OTHER machines' (ours is the
// live session file under ~/.local/share/fish, which fish must be the sole
// writer of — see the script's comment). Notes opens the store, whose
// notes.json and attachments/ are both inside the one unit.
var UNIT_DIRS = {
    "history": ".local/state/qshell/sync/history",
    "fish-history": ".local/state/qshell/sync/fish-history",
    "model-usage": ".local/state/qshell/sync/model-usage",
    "screenshots": "Pictures/Screenshots",
    "notes": ".local/state/qshell/notes",
    "ssh": ".ssh",
    "memory": ".local/share/mem/store",
    "parked": ".local/share/workflow/parked"
};

function unitGlyph(id) {
    return UNIT_GLYPHS[id] || "󰋗"; // md-help_circle
}

function unitBlurb(id) {
    return UNIT_BLURBS[id] || "";
}

function unitDir(id) {
    return UNIT_DIRS[id] || "";
}

// The same path as a person writes it, for the button's hint: the hover says
// WHERE it is about to send you, which is most of the value on the four rows
// whose folder is buried three levels into ~/.local.
function unitDirLabel(id) {
    var dir = unitDir(id);
    return dir === "" ? "" : "~/" + dir;
}

// ---------------------------------------------------------------- parsing
// A missing or unreadable file is not an error to shout about: it is simply a
// machine whose first round has not finished yet.
function parseStatus(raw) {
    var text = String(raw || "").trim();
    if (text === "")
        return emptyStatus("");
    var data = null;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return emptyStatus("status file is not valid JSON");
    }
    if (!data || typeof data !== "object")
        return emptyStatus("status file is not valid JSON");

    var units = [];
    var raws = Array.isArray(data.units) ? data.units : [];
    for (var i = 0; i < raws.length; i++) {
        var u = raws[i] || {};
        units.push({
            id: String(u.id || ""),
            label: String(u.label || u.id || ""),
            // Tri-state on purpose: null is "no verdict yet", which must not
            // read as failure on a machine that has simply never synced.
            ok: u.ok === true ? true : (u.ok === false ? false : null),
            lastRun: String(u.lastRun || ""),
            lastOk: String(u.lastOk || ""),
            error: String(u.error || ""),
            errorKind: String(u.errorKind || ""),
            detail: String(u.detail || "")
        });
    }

    return {
        valid: true,
        parseError: "",
        version: Number(data.version || 1),
        machine: String(data.machine || ""),
        lastRun: String(data.lastRun || ""),
        running: data.running === true,
        currentUnit: String(data.currentUnit || ""),
        ok: data.ok === true ? true : (data.ok === false ? false : null),
        // The hub's own headroom, from `rclone about` once per round; null
        // when the round could not ask (offline, unconfigured, old script).
        hub: data.hub && typeof data.hub === "object" ? {
            total: Number(data.hub.total || 0),
            used: Number(data.hub.used || 0),
            free: Number(data.hub.free || 0)
        } : null,
        units: units
    };
}

function emptyStatus(parseError) {
    return {
        valid: false,
        parseError: String(parseError || ""),
        version: 0,
        machine: "",
        lastRun: "",
        running: false,
        currentUnit: "",
        ok: null,
        hub: null,
        units: []
    };
}

// ------------------------------------------------------------------ state
// One word per row, which is what the panel colors on.
function unitState(unit, status) {
    if (!unit)
        return "idle";
    if (status && status.running && status.currentUnit === unit.id)
        return "running";
    if (unit.ok === false)
        return unit.errorKind === "conflict" ? "conflict" : "failed";
    if (unit.ok === true)
        return "ok";
    return "idle";
}

function failedUnits(status) {
    var out = [];
    if (!status || !status.units)
        return out;
    for (var i = 0; i < status.units.length; i++) {
        if (status.units[i].ok === false)
            out.push(status.units[i]);
    }
    return out;
}

function okCount(status) {
    var n = 0;
    if (!status || !status.units)
        return n;
    for (var i = 0; i < status.units.length; i++) {
        if (status.units[i].ok === true)
            n++;
    }
    return n;
}

// -------------------------------------------------------------------- hub
// The free-space line under the rows, and the early warning the quota
// errorKind exists for: this account is thin, so the wall should be visible
// from a distance, not discovered by the round that hits it.
var HUB_LOW_BYTES = 200 * 1024 * 1024;

function fmtBytes(n) {
    if (!(n > 0))
        return "0 B";
    if (n >= 1024 * 1024 * 1024)
        return (n / (1024 * 1024 * 1024)).toFixed(1) + " GiB";
    if (n >= 1024 * 1024)
        return Math.round(n / (1024 * 1024)) + " MiB";
    return Math.round(n / 1024) + " KiB";
}

function hubLow(status) {
    return !!(status && status.hub && status.hub.total > 0 && status.hub.free < HUB_LOW_BYTES);
}

function hubLine(status) {
    if (!status || !status.hub || !(status.hub.total > 0))
        return "";
    return "Dropbox: " + fmtBytes(status.hub.free) + " free of " + fmtBytes(status.hub.total);
}

// ------------------------------------------------------------------- time
// "when" as a person would say it. The reference clock is passed in rather
// than read here, so the panel can re-render every minute off one timer and
// the function stays pure.
function relative(iso, nowMs) {
    var text = String(iso || "");
    if (text === "")
        return "never";
    var then = Date.parse(text);
    if (isNaN(then))
        return "never";
    var secs = Math.round((nowMs - then) / 1000);
    if (secs < 0)
        secs = 0;
    if (secs < 45)
        return "just now";
    var mins = Math.round(secs / 60);
    if (mins < 60)
        return mins + (mins === 1 ? " minute ago" : " minutes ago");
    var hours = Math.round(mins / 60);
    if (hours < 24)
        return hours + (hours === 1 ? " hour ago" : " hours ago");
    var days = Math.round(hours / 24);
    if (days < 30)
        return days + (days === 1 ? " day ago" : " days ago");
    var months = Math.round(days / 30);
    return months + (months === 1 ? " month ago" : " months ago");
}

// The sentence under a row's label. A failing unit leads with WHEN it last
// worked, because "failed" without "and it has been broken for four days" is
// the gap that let the notes unit rot unnoticed (2026-08-17).
function unitLine(unit, status, nowMs) {
    if (!unit)
        return "";
    var state = unitState(unit, status);
    if (state === "running")
        return "syncing now…";
    if (state === "conflict")
        return "changed on two machines — pick a side";
    if (state === "failed") {
        var since = unit.lastOk === "" ? "never synced" : "last synced " + relative(unit.lastOk, nowMs);
        return "failed — " + since;
    }
    if (state === "ok") {
        var when = relative(unit.lastOk, nowMs);
        return unit.detail === "" ? when : when + " — " + unit.detail;
    }
    if (unit.detail !== "")
        return unit.detail;
    return unitBlurb(unit.id);
}

// ------------------------------------------------------------------- hero
function heroMeta(status, nowMs) {
    if (!status || !status.valid)
        return "never run";
    if (status.running)
        return status.currentUnit === "" ? "syncing…" : "syncing " + status.currentUnit + "…";
    var failed = failedUnits(status);
    if (failed.length > 0)
        return failed.length + (failed.length === 1 ? " unit failing" : " units failing");
    if (status.units.length === 0)
        return "never run";
    return "all synced " + relative(status.lastRun, nowMs);
}

// The bar tooltip: one line that answers the question without opening
// anything.
function tooltip(status, nowMs) {
    if (!status || !status.valid)
        return "Sync — never run";
    if (status.running)
        return "Sync — running";
    var failed = failedUnits(status);
    if (failed.length === 0)
        return "Sync — all " + status.units.length + " synced " + relative(status.lastRun, nowMs);
    var names = [];
    for (var i = 0; i < failed.length; i++)
        names.push(failed[i].label);
    return "Sync failing: " + names.join(", ");
}

// The one-line reason shown under the hero when something is wrong. Auth and
// quota outrank the rest: they are the two a human must go fix by hand, and
// they break every unit at once, so naming them beats listing six casualties.
function headlineError(status) {
    var failed = failedUnits(status);
    if (failed.length === 0)
        return "";
    for (var i = 0; i < failed.length; i++) {
        if (failed[i].errorKind === "auth")
            return "Dropbox needs re-authorizing — run: rclone config reconnect Dropbox:";
        if (failed[i].errorKind === "quota")
            return "Dropbox is full — free up space or upgrade.";
    }
    return failed[0].label + ": " + failed[0].error;
}

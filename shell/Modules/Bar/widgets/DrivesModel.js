// Removable-drives model — the shaping, throughput arithmetic and prose
// behind the drives widget, as pure functions so they can be checked under
// node (DrivesModel.test.js) without a Quickshell runtime.
//
// Input is bin/drives' TSV, two row shapes keyed by the first column:
//
//   drive<TAB>sys<TAB>dev<TAB>name<TAB>size<TAB>bus<TAB>reads<TAB>writes<TAB>sectors
//   vol<TAB>sys<TAB>dev<TAB>parentSys<TAB>label<TAB>fstype<TAB>size<TAB>mount<TAB>avail
//
// A `vol` row always follows the `drive` row it belongs to, but it names its
// parent anyway, so this parses by the name rather than by position.

// Linux reports block I/O in 512-byte sectors in /sys/class/block/*/stat,
// ALWAYS — this is the kernel's fixed unit and has nothing to do with the
// device's physical or logical sector size. A 4K-sector stick still counts
// in 512s here.
var SECTOR_BYTES = 512;

function parseRows(raw) {
    var drives = [];
    var byName = {};
    var lines = String(raw || "").split("\n");

    for (var i = 0; i < lines.length; i++) {
        if (!lines[i])
            continue;
        var c = lines[i].split("\t");
        var kind = String(c[0] || "");

        if (kind === "drive") {
            var drive = {
                sys: String(c[1] || ""),
                dev: String(c[2] || ""),
                name: String(c[3] || ""),
                size: String(c[4] || ""),
                bus: String(c[5] || ""),
                reads: Number(c[6]) || 0,
                writes: Number(c[7]) || 0,
                sectors: Number(c[8]) || 0,
                volumes: []
            };
            if (!drive.sys)
                continue;
            byName[drive.sys] = drive;
            drives.push(drive);
        } else if (kind === "vol") {
            var parent = byName[String(c[3] || "")];
            if (!parent)
                continue;
            parent.volumes.push({
                sys: String(c[1] || ""),
                dev: String(c[2] || ""),
                parent: String(c[3] || ""),
                label: String(c[4] || ""),
                fstype: String(c[5] || ""),
                size: String(c[6] || ""),
                mount: String(c[7] || ""),
                avail: String(c[8] || "")
            });
        }
    }
    return drives;
}

// What to call a volume. A label if it has one, else the filesystem and
// size, else just the size — a partition with no label and no recognized
// filesystem is still a real thing that has to be nameable in a list.
function volumeLabel(volume) {
    if (!volume)
        return "";
    if (volume.label)
        return volume.label;
    if (volume.fstype)
        return volume.fstype.toUpperCase() + (volume.size ? " · " + volume.size : "");
    return volume.size || volume.sys || "Unknown volume";
}

function isMounted(volume) {
    return !!volume && volume.mount !== "";
}

function mountedVolumes(drive) {
    return drive && Array.isArray(drive.volumes) ? drive.volumes.filter(isMounted) : [];
}

// The kernel says requests are in flight. This is the whole basis of the
// "not safe to pull yet" state — a copy dialog reaching 100% means the
// application is done writing, not that the device is.
function hasPendingIo(drive) {
    if (!drive)
        return false;
    return (Number(drive.reads) || 0) + (Number(drive.writes) || 0) > 0;
}

// Bytes per second between two samples of the same drive's lifetime sector
// counter.
//
// Returns 0 rather than a negative or absurd number when the counter went
// backwards, which happens for a real reason: unplug a drive and plug it
// back in and the counter restarts from zero, while the sysfs path stays the
// same. A rate of -800 GB/s on screen would be the tell.
function throughput(previousSectors, currentSectors, elapsedMs) {
    var previous = Number(previousSectors) || 0;
    var current = Number(currentSectors) || 0;
    var elapsed = Number(elapsedMs) || 0;
    if (elapsed <= 0 || current < previous)
        return 0;
    return (current - previous) * SECTOR_BYTES / (elapsed / 1000);
}

function rateText(bytesPerSecond) {
    var value = Number(bytesPerSecond) || 0;
    if (value < 1024)
        return "";
    if (value < 1048576)
        return Math.round(value / 1024) + " KB/s";
    if (value < 1073741824)
        return (value / 1048576).toFixed(value < 10485760 ? 1 : 0) + " MB/s";
    return (value / 1073741824).toFixed(1) + " GB/s";
}

// A drive's one-line state, in the order that matters when deciding whether
// to pull it out.
function driveStateText(drive, rate) {
    if (!drive)
        return "";
    if (hasPendingIo(drive)) {
        var moving = rateText(rate);
        return moving ? "Writing — " + moving : "Busy — do not remove";
    }
    var mounted = mountedVolumes(drive);
    if (mounted.length === 0)
        return drive.volumes.length === 0 ? "No volumes" : "Not mounted";
    if (mounted.length === 1)
        return "Mounted at " + mounted[0].mount;
    return mounted.length + " volumes mounted";
}

// Whether ejecting right now would interrupt something. The panel does not
// refuse in this state — it holds the request and fires when the drive goes
// quiet — but the button has to say which of the two is about to happen.
function ejectWouldWait(drive) {
    return hasPendingIo(drive);
}

function driveCount(drives) {
    return Array.isArray(drives) ? drives.length : 0;
}

function anyBusy(drives) {
    return (Array.isArray(drives) ? drives : []).some(hasPendingIo);
}

function tooltipText(drives) {
    var rows = Array.isArray(drives) ? drives : [];
    if (rows.length === 0)
        return "";
    if (rows.length === 1) {
        var only = rows[0];
        return only.name + (only.size ? " (" + only.size + ")" : "") + " — " + driveStateText(only, 0);
    }
    var busy = rows.filter(hasPendingIo).length;
    return rows.length + " removable drives" + (busy > 0 ? " — " + busy + " busy" : "");
}

function heroMeta(drives) {
    var rows = Array.isArray(drives) ? drives : [];
    if (rows.length === 0)
        return "Nothing plugged in";
    var mounted = rows.reduce(function (total, drive) {
        return total + mountedVolumes(drive).length;
    }, 0);
    var parts = [rows.length + (rows.length === 1 ? " drive" : " drives")];
    if (mounted > 0)
        parts.push(mounted + " mounted");
    if (anyBusy(rows))
        parts.push("busy");
    return parts.join(" · ");
}

// "Finder, Chromium and 2 more" from bin/drives' `busy` output — the
// difference between "target is busy" and knowing to close a file manager.
function holdersText(rows) {
    var names = [];
    var lines = String(rows || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        if (!lines[i])
            continue;
        var name = String(lines[i].split("\t")[1] || "").trim();
        if (name && names.indexOf(name) === -1)
            names.push(name);
    }
    if (names.length === 0)
        return "";
    if (names.length === 1)
        return names[0];
    if (names.length === 2)
        return names[0] + " and " + names[1];
    return names.slice(0, 2).join(", ") + " and " + (names.length - 2) + " more";
}

if (typeof module !== "undefined") {
    module.exports = {
        SECTOR_BYTES: SECTOR_BYTES,
        anyBusy: anyBusy,
        driveCount: driveCount,
        driveStateText: driveStateText,
        ejectWouldWait: ejectWouldWait,
        hasPendingIo: hasPendingIo,
        heroMeta: heroMeta,
        holdersText: holdersText,
        isMounted: isMounted,
        mountedVolumes: mountedVolumes,
        parseRows: parseRows,
        rateText: rateText,
        throughput: throughput,
        tooltipText: tooltipText,
        volumeLabel: volumeLabel
    };
}

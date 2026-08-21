// Unit tests for DrivesModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/DrivesModel.test.js
//
// HONEST NOTE ON THE FIXTURES: unlike the other model tests in this
// directory, these rows are NOT captured from the machine they were written
// on. The NUC has one NVMe disk and no removable media, so `bin/drives` there
// correctly prints nothing. The column layout and the human-size rendering
// below were verified by running the same lsblk+jq pipeline against that
// NVMe disk with the removable filter lifted (2026-08-21) — so the SHAPE is
// real even where the devices are invented. The live udev path and udisksctl
// actions remain unexercised until something is plugged in.

const assert = require("node:assert/strict");
const Model = require("./DrivesModel.js");

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

// ------------------------------------------------------------- the fixtures

// A two-partition USB stick, one partition mounted, and a bare SD card with
// a filesystem straight on the disk (no partition table).
const TSV = [
    "drive\tsda\t/dev/sda\tSanDisk Ultra\t28.6 GB\tusb\t0\t0\t120000",
    "vol\tsda1\t/dev/sda1\tsda\tPHOTOS\texfat\t28 GB\t/run/media/saiful/PHOTOS\t12.4 GB",
    "vol\tsda2\t/dev/sda2\tsda\t\t\t512 MB\t\t",
    "drive\tmmcblk0\t/dev/mmcblk0\tGeneric SD/MMC\t14.6 GB\t\t0\t3\t98765",
    "vol\tmmcblk0\t/dev/mmcblk0\tmmcblk0\t\tvfat\t14.6 GB\t\t"
].join("\n");

const drives = Model.parseRows(TSV);
const stick = drives[0];
const card = drives[1];

// ------------------------------------------------------------------ parsing

test("drives and their volumes are nested by parent name", () => {
    assert.equal(drives.length, 2);
    assert.equal(stick.sys, "sda");
    assert.equal(stick.name, "SanDisk Ultra");
    assert.equal(stick.bus, "usb");
    assert.equal(stick.volumes.length, 2);
    assert.equal(card.volumes.length, 1);
});

test("in-flight counts and the sector total are numbers", () => {
    assert.equal(stick.reads, 0);
    assert.equal(stick.writes, 0);
    assert.equal(stick.sectors, 120000);
    assert.equal(card.writes, 3);
});

test("a volume row with no matching drive is dropped, not orphaned", () => {
    const parsed = Model.parseRows("vol\tsdz1\t/dev/sdz1\tsdz\tGHOST\text4\t1 GB\t\t");
    assert.equal(parsed.length, 0);
});

test("a disk holding a filesystem directly is its own volume", () => {
    assert.equal(card.volumes[0].sys, "mmcblk0");
    assert.equal(card.volumes[0].fstype, "vfat");
});

test("junk and empty input parse to nothing", () => {
    assert.deepEqual(Model.parseRows(""), []);
    assert.deepEqual(Model.parseRows("\n\n"), []);
    assert.deepEqual(Model.parseRows("nonsense\trow"), []);
});

// ----------------------------------------------------------------- labelling

test("a labelled volume uses its label", () => {
    assert.equal(Model.volumeLabel(stick.volumes[0]), "PHOTOS");
});

test("an unlabelled volume falls back to filesystem and size", () => {
    assert.equal(Model.volumeLabel(card.volumes[0]), "VFAT · 14.6 GB");
});

test("a volume with neither label nor filesystem still has a name", () => {
    assert.equal(Model.volumeLabel(stick.volumes[1]), "512 MB");
    assert.equal(Model.volumeLabel({ sys: "sdb9" }), "sdb9");
    assert.equal(Model.volumeLabel(null), "");
});

// -------------------------------------------------------------- mount state

test("mounted volumes are the ones with a mount point", () => {
    assert.equal(Model.isMounted(stick.volumes[0]), true);
    assert.equal(Model.isMounted(stick.volumes[1]), false);
    assert.equal(Model.mountedVolumes(stick).length, 1);
    assert.equal(Model.mountedVolumes(card).length, 0);
});

// ------------------------------------------------------------ the busy state

test("in-flight requests mean the drive is busy", () => {
    assert.equal(Model.hasPendingIo(stick), false);
    assert.equal(Model.hasPendingIo(card), true, "3 writes in flight");
    assert.equal(Model.anyBusy(drives), true);
    assert.equal(Model.anyBusy([stick]), false);
});

test("an eject on a busy drive is a wait, not a refusal", () => {
    assert.equal(Model.ejectWouldWait(card), true);
    assert.equal(Model.ejectWouldWait(stick), false);
});

// ------------------------------------------------------------- throughput

test("throughput is sectors times 512 over the elapsed time", () => {
    // 2048 sectors in one second = 1 MiB/s.
    assert.equal(Model.throughput(1000, 3048, 1000), 1048576);
    // Half the time, twice the rate.
    assert.equal(Model.throughput(1000, 3048, 500), 2097152);
});

test("a counter that went backwards reports nothing, not a negative rate", () => {
    // Unplug and replug: same sysfs path, counter restarts at zero.
    assert.equal(Model.throughput(500000, 12, 1000), 0);
});

test("a zero or missing interval reports nothing", () => {
    assert.equal(Model.throughput(0, 5000, 0), 0);
    assert.equal(Model.throughput(0, 5000, -1), 0);
});

test("rates below a kilobyte are not worth printing", () => {
    assert.equal(Model.rateText(0), "");
    assert.equal(Model.rateText(900), "");
    assert.equal(Model.rateText(2048), "2 KB/s");
});

test("rate units step up and keep one decimal only where it helps", () => {
    assert.equal(Model.rateText(1048576), "1.0 MB/s");
    assert.equal(Model.rateText(4404019), "4.2 MB/s");
    assert.equal(Model.rateText(52428800), "50 MB/s");
    assert.equal(Model.rateText(1610612736), "1.5 GB/s");
});

// --------------------------------------------------------------------- prose

test("the state line leads with the reason not to pull it out", () => {
    assert.equal(Model.driveStateText(card, 4404019), "Writing — 4.2 MB/s");
    // Busy but too slow to name a rate: still say busy.
    assert.equal(Model.driveStateText(card, 0), "Busy — do not remove");
});

test("a quiet drive reports where it is mounted", () => {
    assert.equal(Model.driveStateText(stick, 0), "Mounted at /run/media/saiful/PHOTOS");
    const quietCard = Object.assign({}, card, { writes: 0 });
    assert.equal(Model.driveStateText(quietCard, 0), "Not mounted");
});

test("several mounted volumes are counted rather than listed", () => {
    const many = Object.assign({}, stick, {
        volumes: [
            { mount: "/run/media/a" },
            { mount: "/run/media/b" }
        ]
    });
    assert.equal(Model.driveStateText(many, 0), "2 volumes mounted");
});

test("a drive with no volumes at all says so", () => {
    assert.equal(Model.driveStateText({ volumes: [], reads: 0, writes: 0 }, 0), "No volumes");
});

test("the tooltip names a single drive and counts several", () => {
    assert.equal(Model.tooltipText([stick]), "SanDisk Ultra (28.6 GB) — Mounted at /run/media/saiful/PHOTOS");
    assert.equal(Model.tooltipText(drives), "2 removable drives — 1 busy");
    assert.equal(Model.tooltipText([]), "", "no drives means no tooltip and no icon");
});

test("the hero counts drives, mounts and busyness", () => {
    assert.equal(Model.heroMeta([]), "Nothing plugged in");
    assert.equal(Model.heroMeta([stick]), "1 drive · 1 mounted");
    assert.equal(Model.heroMeta(drives), "2 drives · 1 mounted · busy");
});

// ------------------------------------------------------------------ holders

test("holders are named, deduplicated, and capped", () => {
    assert.equal(Model.holdersText("101\tyazi"), "yazi");
    assert.equal(Model.holdersText("101\tyazi\n102\tchromium"), "yazi and chromium");
    assert.equal(Model.holdersText("101\tyazi\n102\tyazi"), "yazi", "same program twice is one holder");
    assert.equal(Model.holdersText("1\ta\n2\tb\n3\tc\n4\td"), "a, b and 2 more");
    assert.equal(Model.holdersText(""), "");
});

console.log(failures === 0 ? "\nall passed" : `\n${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

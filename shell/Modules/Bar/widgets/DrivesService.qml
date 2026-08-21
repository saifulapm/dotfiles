import QtQuick
import Quickshell
import Quickshell.Io
import "DrivesModel.js" as Model

// Drives service — removable storage for the drives widget and panel. ONE
// instance however many screens carry the widget (S2); created at the bar
// root.
//
// TWO CADENCES, and the second one is the interesting case for this shell's
// no-polling rule.
//
// Appearing and disappearing is event-driven: `udevadm monitor --udev
// --subsystem-match=block` is a long-lived process that prints a line when a
// block device arrives, leaves or is re-examined, and a debounced re-probe
// hangs off it. Plugging a stick in lights the icon without anything having
// asked.
//
// THROUGHPUT IS SAMPLED, and it has to be: a rate is two readings of a
// counter and the time between them, so there is no event that can deliver
// one. It runs at 1 Hz and ONLY while the panel is open or an eject is
// waiting for the drive to go quiet — which is the rule's own stated
// exception ("panels refreshing while open"), not a hole in it. With the
// panel shut and nothing pending, this service starts no process at all.
//
// The eject-when-quiet behaviour is the reason the sampling is worth having.
// A copy dialog reaching 100% means the application has finished writing,
// not that the device has; the kernel's in-flight count is what knows the
// difference, so an eject asked for mid-copy is HELD and fires when the
// queue drains rather than failing or corrupting.
QtObject {
    id: root

    // The presence probe has answered at least once.
    property bool probed: false

    // Model.parseRows output. Replaced wholesale, never mutated.
    property var drives: []

    // Set by the panel while it is on screen; the sampler gates on it.
    property bool panelOpen: false

    readonly property int driveCount: drives.length
    readonly property bool busy: Model.anyBusy(drives)
    readonly property string tooltip: Model.tooltipText(drives)
    readonly property string heroMeta: Model.heroMeta(drives)

    // Bytes/sec for the whole of removable storage, from the last two
    // samples. Zero whenever the sampler is not running, which is honest:
    // with nothing sampling, the rate is not "zero", it is unknown, and the
    // panel only ever shows it while it is open and therefore sampling.
    property real rate: 0
    property var _lastSectors: ({})
    property double _lastSampleMs: 0

    // sys name -> a request to eject once the drive stops moving data.
    property var pendingEject: ({})
    // sys name -> "Chromium and 2 more", from the last busy lookup.
    property var holders: ({})

    property bool refreshing: false
    property string lastError: ""

    property string _output: ""
    property string _error: ""
    property int _monitorRetries: 0

    function refresh() {
        if (listProcess.running)
            return;
        _output = "";
        _error = "";
        refreshing = true;
        listProcess.running = true;
    }

    function applyList(raw) {
        const parsed = Model.parseRows(raw);
        probed = true;

        // Fold the new sector counters into a rate before replacing the
        // list, while both readings are in hand.
        const now = Date.now();
        if (_lastSampleMs > 0) {
            let total = 0;
            const nextSectors = {};
            for (const drive of parsed) {
                nextSectors[drive.sys] = drive.sectors;
                total += Model.throughput(_lastSectors[drive.sys], drive.sectors, now - _lastSampleMs);
            }
            rate = total;
            _lastSectors = nextSectors;
        } else {
            const seed = {};
            for (const drive of parsed)
                seed[drive.sys] = drive.sectors;
            _lastSectors = seed;
            rate = 0;
        }
        _lastSampleMs = now;

        drives = parsed;
        lastError = "";
        dropStaleRequests();
        firePendingEjects();
        ensureMonitor();
    }

    // A drive that has left takes its pending request and its holder note
    // with it — otherwise unplugging something mid-eject leaves an entry
    // that nothing will ever clear.
    function dropStaleRequests() {
        const present = {};
        for (const drive of drives)
            present[drive.sys] = true;
        pendingEject = filterKeys(pendingEject, present);
        holders = filterKeys(holders, present);
    }

    function filterKeys(source, allowed) {
        const next = {};
        for (const key in source) {
            if (allowed[key])
                next[key] = source[key];
        }
        return next;
    }

    function driveBySys(sys) {
        return drives.find(drive => drive.sys === sys) || null;
    }

    // ------------------------------------------------------------- actions
    function mountVolume(volume) {
        if (!volume || !volume.dev)
            return;
        run(["udisksctl", "mount", "-b", String(volume.dev), "--no-user-interaction"]);
    }

    function unmountVolume(volume) {
        if (!volume || !volume.dev)
            return;
        run(["udisksctl", "unmount", "-b", String(volume.dev), "--no-user-interaction"]);
    }

    // Lazy unmount, offered only after an ordinary one has been refused. It
    // detaches the tree now and cleans up when the last user lets go, which
    // is a real answer to "target is busy" but NOT a safe default: anything
    // still holding a file keeps writing into a filesystem the user believes
    // is gone. The panel makes it a second, explicit choice.
    function forceUnmountVolume(volume) {
        if (!volume || !volume.mount)
            return;
        run(["umount", "-l", String(volume.mount)]);
    }

    // Eject the whole drive: unmount every volume on it, then power it down.
    // Held while the kernel still has requests in flight — see the header.
    function eject(drive) {
        if (!drive || !drive.sys)
            return;
        if (Model.ejectWouldWait(drive)) {
            const next = {};
            for (const key in pendingEject)
                next[key] = pendingEject[key];
            next[drive.sys] = true;
            pendingEject = next;
            // The sampler is what will notice the queue draining.
            return;
        }
        clearPending(drive.sys);
        // power-off unmounts what it has to; doing it in one call keeps the
        // whole sequence inside udisks rather than racing it.
        run(["udisksctl", "power-off", "-b", String(drive.dev), "--no-user-interaction"]);
    }

    function cancelEject(sys) {
        clearPending(sys);
    }

    function clearPending(sys) {
        if (pendingEject[sys] === undefined)
            return;
        const next = {};
        for (const key in pendingEject) {
            if (key !== sys)
                next[key] = pendingEject[key];
        }
        pendingEject = next;
    }

    // Any held eject whose drive has gone quiet now fires.
    function firePendingEjects() {
        for (const sys in pendingEject) {
            const drive = driveBySys(sys);
            if (!drive) {
                clearPending(sys);
                continue;
            }
            if (!Model.hasPendingIo(drive)) {
                clearPending(sys);
                run(["udisksctl", "power-off", "-b", String(drive.dev), "--no-user-interaction"]);
            }
        }
    }

    function openVolume(volume) {
        if (!volume || !volume.mount)
            return;
        Quickshell.execDetached(["xdg-open", String(volume.mount)]);
    }

    // Who is holding a mount open, asked only when an unmount has just been
    // refused — it costs a process, and the answer is only interesting in
    // exactly that moment.
    function lookupHolders(volume) {
        if (!volume || !volume.mount || holdersProcess.running)
            return;
        holdersProcess.sysName = String(volume.parent || volume.sys || "");
        holdersProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "drives", "busy", String(volume.mount)];
        holdersProcess.running = true;
    }

    function run(command) {
        _queue.push(["setpriv", "--pdeathsig", "TERM", "--"].concat(command));
        pumpQueue();
    }

    property var _queue: []

    function pumpQueue() {
        if (actionProcess.running || _queue.length === 0)
            return;
        actionProcess.command = _queue.shift();
        actionProcess.running = true;
    }

    function ensureMonitor() {
        if (monitorProcess.running)
            return;
        _monitorRetries = 0;
        monitorProcess.running = true;
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // ----------------------------------------------------------- the clocks
    // The sampler. Its `running` condition IS the no-polling compliance: the
    // panel being on screen, or an eject waiting for a drive to go quiet.
    // Nothing else can start it, and it stops the moment both end.
    readonly property Timer sampleTimer: Timer {
        interval: 1000
        repeat: true
        running: root.panelOpen || Object.keys(root.pendingEject).length > 0
        onTriggered: root.refresh()
        onRunningChanged: if (!running) {
            // A stale rate on a shut panel would be reported as current the
            // next time it opened.
            root.rate = 0;
            root._lastSampleMs = 0;
        }
    }

    // Coalesces the burst of udev lines one plug event produces (the disk,
    // then each partition) into a single re-probe.
    readonly property Timer eventDebounce: Timer {
        interval: 350
        repeat: false
        onTriggered: root.refresh()
    }

    readonly property Timer monitorRestartTimer: Timer {
        interval: 3000
        repeat: false
        onTriggered: if (!root.monitorProcess.running)
            root.monitorProcess.running = true
    }

    // --------------------------------------------------------- the processes
    readonly property Process listProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "drives"]
        stdout: StdioCollector {
            id: listStdout
            waitForEnd: true
            onStreamFinished: root._output = text
        }
        stderr: StdioCollector {
            id: listStderr
            waitForEnd: true
            onStreamFinished: root._error = text
        }
        onExited: exitCode => {
            root.refreshing = false;
            const out = String(listStdout.text || root._output || "");
            const err = String(listStderr.text || root._error || "");
            if (exitCode === 0)
                root.applyList(out);
            else {
                root.probed = true;
                root.lastError = root.elideStatus(err || "Could not list drives");
            }
        }
    }

    // The event source. Every line is a block-device change; none of them is
    // parsed, because the probe is the only thing that decides state — the
    // same trade DevServicesService makes with systemd's JobRemoved.
    readonly property Process monitorProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser {
            onRead: line => {
                // The two-line banner udevadm prints before it starts is not
                // an event; re-probing on it is harmless but pointless.
                if (String(line).indexOf("UDEV ") !== 0)
                    return;
                root._monitorRetries = 0;
                root.eventDebounce.restart();
            }
        }
        onExited: {
            if (root._monitorRetries >= 5) {
                root.lastError = "udev monitor stopped — refresh to reconnect";
                return;
            }
            root._monitorRetries += 1;
            root.monitorRestartTimer.restart();
        }
    }

    readonly property Process actionProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: actionStderr
            waitForEnd: true
            onStreamFinished: root._error = text
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.lastError = root.elideStatus(root._error || "The drive refused that");
            else
                root.lastError = "";
            root.pumpQueue();
            root.refresh();
        }
    }

    readonly property Process holdersProcess: Process {
        property string sysName: ""
        running: false
        command: []
        stdout: StdioCollector {
            id: holdersStdout
            waitForEnd: true
            onStreamFinished: {
                const text = Model.holdersText(holdersStdout.text);
                if (text === "")
                    return;
                const next = {};
                for (const key in root.holders)
                    next[key] = root.holders[key];
                next[root.holdersProcess.sysName] = text;
                root.holders = next;
            }
        }
    }

    Component.onCompleted: {
        refresh();
        ensureMonitor();
    }
}

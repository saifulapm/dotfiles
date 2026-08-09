import QtQuick
import Quickshell
import Quickshell.Io

// Cross-machine state sync, ported from the sync half of omarchy's
// model-usage Main.qml (CREDITS.md) and generalized into a service.
//
// There is no server and no protocol. Each machine writes ONE snapshot file
// of its own state into a shared directory and reads EVERY snapshot it finds
// there; whatever syncs that directory (Syncthing, Dropbox, NFS, a git
// checkout) is the transport. A machine that never sees another's file simply
// shows its own numbers.
//
// Config lives in shell.json's root `sync` block:
//
//     "sync": { "enabled": true, "dir": "~/Sync/qshell", "deviceId": "macbook" }
//
// `dir` empty (the default) means sync is off, which is also upstream's
// default. `deviceId` falls back to ~/.config/qshell/machine (chezmoi's
// detected machine id — every Asahi box here answers "fedora" to hostname,
// and two machines sharing an id collapse into one device), then the
// hostname, then $HOST, then $USER.
//
// Where upstream hardcodes model-usage's one payload, this takes named
// sections: a module calls `publish("providers", {...})` and reads back
// `snapshotsFor("providers")`. Sections sit at the top level of the file
// beside `deviceId`/`updatedAt`, so the model-usage snapshot this writes is
// byte-compatible with the one their shell writes and reads — and shell
// history (or anything else) is just another key.
//
// Merging is deliberately NOT here: what it means to combine two payloads is
// the module's business (model-usage sums token buckets but unions active
// dates). This layer owns identity, transport and enumeration only.
QtObject {
    id: root

    // The ShellRoot. Named `shellRoot`, not `shell`: a property named after
    // the outer id shadows it inside this object's own bindings.
    required property var shellRoot

    readonly property int schemaVersion: 1
    readonly property string home: Quickshell.env("HOME") || ""

    readonly property var syncConfig: shellRoot && shellRoot.config && shellRoot.config.sync && typeof shellRoot.config.sync === "object" ? shellRoot.config.sync : ({})

    // Upstream accepts a handful of spellings here because the value comes
    // from a hand-edited config file.
    readonly property bool enabledSetting: parseEnabled(syncConfig.enabled === undefined ? syncConfig.syncMode : syncConfig.enabled)
    readonly property string dirSetting: String(syncConfig.dir || "")
    readonly property string effectiveDir: expandPath(dirSetting)
    readonly property string deviceId: safeDeviceId(String(syncConfig.deviceId || ""))
    readonly property string fileName: deviceId + ".json"
    readonly property bool configured: enabledSetting && effectiveDir !== ""

    // The FileView needs a valid path even with sync switched off; upstream
    // parks it on a disabled name under the cache dir for the same reason.
    readonly property string snapshotPath: configured ? effectiveDir + "/" + fileName : ((Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")) + "/qshell/sync-disabled.json")

    // Sections staged by publish(), written as the top level of our snapshot.
    property var sections: ({})

    // Every snapshot found in the directory, ours included, most recently
    // parsed first-come. Bumping `revision` is what re-evaluates readers.
    property var snapshots: []
    property int revision: 0
    property bool running: false
    property string statusText: ""

    property bool requestedWhileRunning: false
    property string detectedHostname: ""
    property string detectedMachine: ""

    // ------------------------------------------------------------------ API
    // Stage a section and schedule a write. Called by whichever module owns
    // that key; the value must be plain JSON.
    function publish(key, value) {
        if (!key)
            return;
        const next = {};
        for (const k in sections)
            next[k] = sections[k];
        next[key] = value;
        sections = next;
        scheduleSync();
    }

    // Every device's payload for one section, ours included:
    // [{ deviceId, updatedAt, data }]
    function snapshotsFor(key) {
        // Read `revision` so callers binding to this re-evaluate on a scan.
        const rev = revision;
        const out = [];
        for (let i = 0; i < snapshots.length; i++) {
            const snapshot = snapshots[i];
            if (!snapshot || snapshot[key] === undefined || snapshot[key] === null)
                continue;
            out.push({
                deviceId: safeDeviceId(String(snapshot.deviceId || "")),
                updatedAt: String(snapshot.updatedAt || ""),
                data: snapshot[key]
            });
        }
        return out;
    }

    function deviceCountFor(key) {
        const devices = {};
        const entries = snapshotsFor(key);
        for (let i = 0; i < entries.length; i++)
            devices[entries[i].deviceId] = true;
        return Object.keys(devices).length;
    }

    // ------------------------------------------------------------- the cycle
    function scheduleSync() {
        if (!configured)
            return;
        debounce.restart();
    }

    function runSync() {
        if (!configured)
            return;
        if (running) {
            requestedWhileRunning = true;
            return;
        }
        requestedWhileRunning = false;
        statusText = "";
        running = true;
        mkdirProc.command = ["mkdir", "-p", effectiveDir];
        mkdirProc.running = true;
    }

    function localSnapshot() {
        const out = {
            schemaVersion: schemaVersion,
            deviceId: deviceId,
            updatedAt: new Date().toISOString()
        };
        for (const key in sections)
            out[key] = sections[key];
        return out;
    }

    function writeSnapshot() {
        if (!configured) {
            finishRun();
            return;
        }
        // The scan is chained off onSaved: setText writes on a worker thread,
        // so scheduling the scan any earlier can read the previous snapshot.
        snapshotFile.setText(JSON.stringify(localSnapshot(), null, 2) + "\n");
    }

    function startScan() {
        if (!configured) {
            finishRun();
            return;
        }
        scanProc.command = ["bash", "-c", scanScript, effectiveDir];
        scanProc.running = true;
    }

    // Upstream's reader: every *.json in the directory, framed by markers so
    // one stream carries them all. `nullglob` keeps an empty directory quiet.
    readonly property string scanScript: "dir=$0; [[ -d \"$dir\" ]] || exit 0; shopt -s nullglob; for f in \"$dir\"/*.json; do [[ -f \"$f\" ]] || continue; printf '===%s===\\n' \"$f\"; cat \"$f\"; printf '\\n=== EOM ===\\n'; done"

    function parseScanOutput(output) {
        const lines = String(output || "").split("\n");
        const found = [];
        let currentPath = "";
        let currentJson = [];

        function flush() {
            if (currentPath === "")
                return;
            const raw = currentJson.join("\n").trim();
            try {
                const parsed = JSON.parse(raw);
                if (parsed && typeof parsed === "object" && parsed.deviceId)
                    found.push(parsed);
            } catch (e) {
                console.warn("sync", "ignoring unparseable snapshot", currentPath);
            }
            currentPath = "";
            currentJson = [];
        }

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line === "=== EOM ===") {
                flush();
                continue;
            }
            const start = line.match(/^===(.+)===$/);
            if (start) {
                flush();
                currentPath = start[1];
                currentJson = [];
                continue;
            }
            if (currentPath !== "")
                currentJson.push(line);
        }
        flush();

        snapshots = found;
        revision++;
    }

    function finishRun() {
        running = false;
        if (requestedWhileRunning && configured) {
            requestedWhileRunning = false;
            scheduleSync();
        }
    }

    // Switching sync off drops what other devices contributed, so a module
    // reading snapshotsFor() falls back to its own numbers immediately.
    onConfiguredChanged: {
        if (configured) {
            scheduleSync();
        } else {
            debounce.stop();
            requestedWhileRunning = false;
            snapshots = [];
            statusText = "";
            revision++;
        }
    }

    onEffectiveDirChanged: if (configured)
        scheduleSync()

    // ------------------------------------------------------------- helpers
    function parseEnabled(value) {
        if (value === true)
            return true;
        const text = String(value || "").trim().toLowerCase();
        return text === "on" || text === "enabled" || text === "true" || text === "yes" || text === "1";
    }

    function expandPath(path) {
        const value = String(path || "").trim();
        if (value === "")
            return "";
        if (value === "~")
            return home;
        if (value.indexOf("~/") === 0)
            return home + value.substring(1);
        if (value.indexOf("$HOME/") === 0)
            return home + value.substring(5);
        if (value.charAt(0) !== "/")
            return home + "/" + value;
        return value;
    }

    // The id becomes a filename, so it is sanitised hard. Devices are keyed by
    // this, not by the file they arrived in: two machines sharing an id
    // collapse into one — which is why the machine file outranks the
    // hostname: every Asahi install here is named "fedora".
    function safeDeviceId(raw) {
        let value = String(raw || "").trim();
        if (value === "")
            value = detectedMachine || Quickshell.env("HOSTNAME") || detectedHostname || Quickshell.env("HOST") || Quickshell.env("USER") || "device";
        value = value.replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^[._-]+|[._-]+$/g, "");
        if (value === "")
            value = "device";
        return value.length > 80 ? value.substring(0, 80) : value;
    }

    // ------------------------------------------------------------- plumbing
    property FileView hostnameFile: FileView {
        path: "/etc/hostname"
        watchChanges: false
        printErrors: false
        onLoaded: root.detectedHostname = String(text() || "").trim()
        Component.onCompleted: reload()
    }

    // chezmoi's per-machine identity. Loads in milliseconds at startup —
    // long before any module has numbers to publish — so the hostname
    // fallback only ever fires on a machine that skipped `chezmoi apply`.
    property FileView machineFile: FileView {
        path: root.home + "/.config/qshell/machine"
        watchChanges: false
        printErrors: false
        onLoaded: root.detectedMachine = String(text() || "").trim()
        Component.onCompleted: reload()
    }

    property FileView snapshotFile: FileView {
        path: root.snapshotPath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onSaved: root.startScan()
        onSaveFailed: {
            root.statusText = "Usage sync write failed";
            root.finishRun();
        }
    }

    property Timer debounce: Timer {
        interval: 1000
        onTriggered: root.runSync()
    }

    property Process mkdirProc: Process {
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                root.statusText = "Usage sync mkdir failed";
                root.finishRun();
                return;
            }
            root.writeSnapshot();
        }
    }

    property Process scanProc: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseScanOutput(text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0)
                root.statusText = "Usage sync scan failed";
            root.finishRun();
        }
    }
}

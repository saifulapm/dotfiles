import QtQuick
import Quickshell
import Quickshell.Io
import "HubSyncModel.js" as Model

// Hub-sync service — ours, in the shape of the devservices and rclone-remote
// services: everything the sync widget and its panel read, for the one
// Dropbox hub this machine talks to.
//
// There is no polling here and no probe of any kind. bin/qshell-sync is the
// only thing that ever learns the truth, and it writes that truth to
// status.json after EVERY unit; this service just watches that file. So a
// round started by the 15-minute timer, by a terminal, or by the panel's own
// button all light up the panel identically and live — the shell never has to
// ask, and never duplicates the work.
//
// The one clock is a 60-second tick that only re-stamps `nowMs`. It exists so
// "last synced 4 minutes ago" stops being a lie a minute after the panel
// opens; it starts no process and touches no network, which is why it is
// allowed to run unconditionally where a probe would not be.
QtObject {
    id: root

    readonly property string statusPath: Quickshell.env("HOME") + "/.local/state/qshell/sync/status.json"
    readonly property string syncBin: Quickshell.env("HOME") + "/.dotfiles/bin/qshell-sync"
    readonly property string sshBin: Quickshell.env("HOME") + "/.dotfiles/bin/ssh-hub-sync"

    // The parsed status.json. Never null — an unread or unparseable file
    // yields the empty status, which reads as "never run" rather than as an
    // error, because on a fresh machine that is exactly what it is.
    property var status: Model.emptyStatus("")

    readonly property var units: status.units || []
    readonly property bool anyFailing: Model.failedUnits(status).length > 0
    readonly property int okCount: Model.okCount(status)

    // Running from ANY source: the timer's round and the panel's button are
    // the same script behind the same flock, and the panel must not offer to
    // start a second one just because it did not start the first.
    readonly property bool running: status.running === true || roundProcess.running
    readonly property string currentUnit: roundProcess.running && _requested !== "" ? _requested : String(status.currentUnit || "")

    property string lastError: ""
    property string actionStatus: ""
    property real nowMs: Date.now()

    // Which unit this service asked for, so the panel can show the row as
    // busy in the gap between the click and the script's first status write.
    property string _requested: ""

    readonly property string reauthCommand: "rclone config reconnect Dropbox:"

    // ----------------------------------------------------------- the actions
    function syncAll() {
        _run([]);
    }

    function retry(unitId) {
        if (!unitId)
            return;
        _run(["--only", String(unitId)]);
    }

    // Conflict resolution for the ssh blob, which is the one unit that can
    // stall on a question only a human can answer: two machines changed
    // ~/.ssh since they last agreed, and merging key material is not a thing
    // anyone should do automatically. Whichever side is adopted, the script
    // tars the current ~/.ssh into its state dir first.
    //
    // The adopt is chained with a `--only ssh` round in ONE command rather
    // than fired as two, so the status file is rewritten by the same
    // invocation that resolved the conflict — otherwise the panel would sit
    // on a stale "conflict" row until the next tick of the timer.
    function adoptSsh(side) {
        if (roundProcess.running)
            return;
        const flag = side === "local" ? "--adopt-local" : "--adopt-remote";
        _requested = "ssh";
        lastError = "";
        actionStatus = side === "local" ? "Publishing this machine's ~/.ssh…" : "Adopting the hub's ~/.ssh…";
        roundProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", '"$1" "$2" && "$3" --only ssh', "hub-sync-adopt", root.sshBin, flag, root.syncBin];
        roundProcess.running = true;
    }

    function _run(args) {
        if (roundProcess.running)
            return;
        _requested = args.length > 1 ? String(args[1]) : "";
        lastError = "";
        actionStatus = "";
        roundProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", root.syncBin].concat(args);
        roundProcess.running = true;
    }

    function copyReauthCommand() {
        Quickshell.execDetached(["wl-copy", "--type", "text/plain", reauthCommand]);
        actionStatus = "Command copied — run it in a terminal";
        actionStatusTimer.restart();
    }

    // Open one unit's folder in the file manager (yazi, via inode/directory).
    // Nothing guards a missing path: a row exists only once a round has
    // written a verdict for that unit, and a round creates the directory it
    // syncs before it can report on it.
    //
    // Replaced an openScreenshots() that hardcoded the one folder anybody had
    // asked for and was wired to nothing.
    function openUnitDir(unitId) {
        const dir = Model.unitDir(String(unitId || ""));
        if (dir === "")
            return;
        Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/" + dir]);
    }

    function elide(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 200 ? value.substring(0, 197) + "…" : value;
    }

    // ---------------------------------------------------------- the sources
    readonly property FileView statusFile: FileView {
        path: root.statusPath
        watchChanges: true
        printErrors: false
        onLoaded: root.status = Model.parseStatus(text())
        // A file that is not there yet is the fresh-machine case, not a
        // failure: the empty status says "never run" and the first round
        // fills it in.
        onLoadFailed: root.status = Model.emptyStatus("")
        onFileChanged: reload()
    }

    readonly property Process roundProcess: Process {
        running: false
        command: []
        stderr: StdioCollector {
            id: roundStderr
            waitForEnd: true
        }
        onExited: exitCode => {
            root._requested = "";
            // Exit 1 means a unit failed, and status.json already says which
            // — repeating it here would put the same sentence on screen
            // twice. Only a script that could not run at all is reported.
            if (exitCode !== 0 && exitCode !== 1) {
                const err = root.elide(String(roundStderr.text || ""));
                root.lastError = err !== "" ? err : "sync exited " + exitCode;
            }
            if (root.actionStatus !== "")
                root.actionStatusTimer.restart();
            root.statusFile.reload();
        }
    }

    // --------------------------------------------------------------- clocks
    readonly property Timer clock: Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
    }

    readonly property Timer actionStatusTimer: Timer {
        interval: 2600
        repeat: false
        onTriggered: root.actionStatus = ""
    }
}

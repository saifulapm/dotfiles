import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Idle service, ported from omarchy's idle plugin.
//
// One ext-idle-notify-v1 monitor arms at the FIRST stage deadline; the
// remaining stages hang off it as one-shot timers carrying the difference.
// That is upstream's shape: the compositor owns the "has the user stopped
// touching things" question (including idle inhibitors — a fullscreen video
// suspends the whole cycle), and the shell only sequences what happens after.
// Activity cancels the cycle wholesale, so nothing here counts, samples or
// polls.
//
// Config lives in shell.json's root `idle` block:
//
//     "idle": { "screensaver": 150, "blank": 300, "lock": 360 }
//
// Seconds. A missing/invalid value falls back to the default; 0 disables that
// stage; with every stage disabled the monitor itself never arms.
//
// Only the stage timings live here. What the screensaver actually shows — the
// quote list, how long each stays up, which effects, how fast — is nirisaver's
// configuration, not the shell's: it reads ~/.config/nirisaver/config.toml and
// ~/.config/nirisaver/quotes.txt itself, and bin/screensaver-launch passes it
// no flags at all.
//
// Three deliberate adaptations of upstream's semantics:
//
//  * Their first stage launches a screensaver window and their whole Hyprland
//    openwindow/closewindow dance exists to know whether that window is still
//    up. Ours launches bin/screensaver-launch (the native quotes overlay)
//    but keeps none of that bookkeeping: the screensaver polices itself. It
//    takes an exclusive keyboard grab on its own layer surface, so a
//    keystroke or a pointer move dismisses it without anyone asking.
//  * `blank` has no upstream counterpart. Powering the panel off was this
//    service's whole first stage until the screensaver took that slot over
//    (ce8bbac), which left the panel lit through the quotes right up to the
//    lock. It is its own stage now rather than a retimed screensaver, so the
//    two run in sequence: quotes first, dark panel after. Defaults to 0 (off)
//    so the stage is opt-in and upstream's two-stage shape is the fallback.
//    The screensaver keeps running behind the dark panel — between quotes
//    it presents nothing at all, and the wake path sweeps it either way.
//  * Because launching their screensaver itself reads as activity on
//    Hyprland, upstream ignores the wake signal while the screensaver is up.
//    niri's ext-idle-notify only resets on real input, so we keep the plain
//    swayidle-style rule: any activity cancels every pending stage, powers
//    the monitors back on, and sweeps the screensaver (belt to its own
//    braces: it dismisses itself on the same input, and the sweep is what
//    covers a wake this service saw first).
QtObject {
    id: root

    // The ShellRoot. Named `shellRoot`, not `shell`: a property named after
    // the outer id shadows it inside this object's own bindings.
    required property var shellRoot

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell"
    // Upstream keeps this flag at ~/.local/state/omarchy/indicators/stay-awake.
    // Presence is the whole state — the file's contents are never read.
    readonly property string stayAwakePath: stateDir + "/stay-awake"
    // Present exactly while the idle cycle is active, in the same
    // file-is-the-state pattern. hub's doorbell reads it (with the `locked`
    // marker and the stay-awake flag) to decide whether Saiful is watching
    // this machine — a phone that buzzes for someone sitting at the desk is
    // the defect it exists to prevent. Swept at startup: a flag left by a
    // shell that died mid-cycle would otherwise read as idle for ever.
    readonly property string idleFlagPath: stateDir + "/idle"

    // Upstream's defaults (their Service.qml); `blank` is ours and stays off
    // unless shell.json asks for it.
    readonly property int defaultScreensaverSeconds: 150
    readonly property int defaultBlankSeconds: 0
    readonly property int defaultLockSeconds: 300

    readonly property var idleConfig: shellRoot && shellRoot.config && shellRoot.config.idle && typeof shellRoot.config.idle === "object" ? shellRoot.config.idle : ({})
    readonly property int screensaverTimeoutSeconds: secondsFromConfig(idleConfig.screensaver, defaultScreensaverSeconds)
    readonly property int blankTimeoutSeconds: secondsFromConfig(idleConfig.blank, defaultBlankSeconds)
    readonly property int lockTimeoutSeconds: secondsFromConfig(idleConfig.lock, defaultLockSeconds)
    readonly property bool screensaverStageEnabled: screensaverTimeoutSeconds > 0
    readonly property bool blankStageEnabled: blankTimeoutSeconds > 0
    readonly property bool lockStageEnabled: lockTimeoutSeconds > 0

    // The monitor waits for whichever stage comes first; the rest are that
    // stage's deadline plus the difference.
    readonly property int firstIdleTimeoutSeconds: {
        const stages = [];
        if (screensaverStageEnabled)
            stages.push(screensaverTimeoutSeconds);
        if (blankStageEnabled)
            stages.push(blankTimeoutSeconds);
        if (lockStageEnabled)
            stages.push(lockTimeoutSeconds);
        return stages.length > 0 ? Math.min.apply(Math, stages) : 0;
    }
    readonly property int screensaverDelaySeconds: Math.max(0, screensaverTimeoutSeconds - firstIdleTimeoutSeconds)
    readonly property int blankDelaySeconds: Math.max(0, blankTimeoutSeconds - firstIdleTimeoutSeconds)
    readonly property int lockDelaySeconds: Math.max(0, lockTimeoutSeconds - firstIdleTimeoutSeconds)

    // Stay-awake state, mirrored from the flag file.
    property bool stayAwake: false
    property bool stayAwakeLoaded: false
    property bool hasPendingPersist: false
    property bool pendingPersist: false

    readonly property bool idleEnabled: stayAwakeLoaded && !stayAwake && firstIdleTimeoutSeconds > 0

    property bool idledThisCycle: false
    property bool monitorsPoweredOff: false
    property string lastEvent: "starting"

    // Upstream's IdleModel.secondsFromConfig, with 0 kept as a real value so
    // it can disable a stage instead of meaning "immediately".
    function secondsFromConfig(value, fallback) {
        if (value === undefined || value === null)
            return fallback;
        const n = Number(value);
        if (!isFinite(n) || n < 0)
            return fallback;
        return Math.floor(n);
    }

    function logEvent(event, details) {
        lastEvent = details === undefined || details === "" ? event : event + ": " + details;
    }

    function run(command) {
        Quickshell.execDetached(command);
    }

    // The keyboard backlight goes dark with the screen and comes back with it.
    // On a MacBook it is the only lit thing left once the panel is off, and it
    // reads as "still awake". bin/brightness-keyboard parks the level so the
    // wake half restores exactly what was set, and is a no-op on machines with
    // no such LED; the lock screen's own blank timer drives the same pair.
    function powerOffMonitors() {
        if (monitorsPoweredOff)
            return;
        monitorsPoweredOff = true;
        logEvent("blank", "power-off-monitors");
        run(["niri", "msg", "action", "power-off-monitors"]);
        run(["brightness-keyboard", "off"]);
    }

    function powerOnMonitors() {
        if (!monitorsPoweredOff)
            return;
        monitorsPoweredOff = false;
        logEvent("wake", "power-on-monitors");
        run(["niri", "msg", "action", "power-on-monitors"]);
        run(["brightness-keyboard", "restore"]);
    }

    function launchScreensaver() {
        if (shellRoot.locked) {
            logEvent("screensaver", "skipped-locked");
            return;
        }
        logEvent("screensaver", "launch");
        screensaverProcess.running = true;
    }

    function killScreensaver() {
        // One process, not a terminal with an animator inside it: nirisaver
        // owns its own overlay, and SIGTERM is a first-class dismissal for it
        // — it fades out and exits rather than being torn off the screen.
        // Nothing to wait for and nothing that can outlive it, so the
        // two-stage teardown this used to need for the terminal animator
        // (omarchy 438f7b3, f6fd2e7) is gone with the terminal.
        //
        // -x on the process name rather than -f on the command line, which
        // the old bracketed pattern needed. "nirisaver" is also a directory
        // name — ~/.local/src/nirisaver — so a -f match would sweep up the
        // git clone or the cargo install that update-all runs against it if
        // the idle cycle happened to fire mid-update. The name is exact and
        // cannot collide.
        run(["pkill", "-x", "nirisaver"]);
    }

    function lockNow(reason) {
        screensaverTimer.stop();
        blankTimer.stop();
        lockTimer.stop();
        idledThisCycle = false;
        // The `locked` marker takes over as the not-watching signal, but the
        // cycle is over: leaving the flag would double-report after unlock.
        run(["rm", "-f", idleFlagPath]);
        // The lock surface steals focus, so the screensaver would notice and
        // exit within a second anyway — the kill just skips the overlap.
        killScreensaver();
        if (shellRoot.locked) {
            logEvent("lock-skipped", "already locked");
            return;
        }
        logEvent("lock", reason || "requested");
        // The same entry point the `lock lock` IPC call uses.
        shellRoot.lockSession();
    }

    function startIdleCycle() {
        if (idledThisCycle)
            return;
        idledThisCycle = true;
        run(["touch", idleFlagPath]);
        logEvent("idle-cycle-start", "screensaver=" + screensaverTimeoutSeconds + " lock=" + lockTimeoutSeconds);

        if (screensaverStageEnabled) {
            if (screensaverDelaySeconds === 0)
                launchScreensaver();
            else
                screensaverTimer.restart();
        }

        if (blankStageEnabled) {
            if (blankDelaySeconds === 0)
                powerOffMonitors();
            else
                blankTimer.restart();
        }

        if (lockStageEnabled) {
            if (lockDelaySeconds === 0)
                lockNow("lock-timeout-immediate");
            else
                lockTimer.restart();
        }
    }

    function cancelIdleCycle(reason) {
        screensaverTimer.stop();
        blankTimer.stop();
        lockTimer.stop();
        if (idledThisCycle) {
            logEvent("idle-cycle-cancel", reason || "requested");
            killScreensaver();
        }
        powerOnMonitors();
        idledThisCycle = false;
        run(["rm", "-f", idleFlagPath]);
    }

    function handleIdleChanged() {
        if (!idleEnabled) {
            cancelIdleCycle("disabled");
            return;
        }
        if (idleMonitor.isIdle)
            startIdleCycle();
        else
            cancelIdleCycle("activity");
    }

    // ------------------------------------------------------------ stay awake
    function applyStayAwake(value, reason) {
        const on = !!value;
        const changed = !stayAwakeLoaded || stayAwake !== on;
        stayAwake = on;
        stayAwakeLoaded = true;
        if (!changed)
            return;
        logEvent("stay-awake", (on ? "enabled" : "disabled") + (reason ? " " + reason : ""));
        if (on)
            cancelIdleCycle("stay-awake");
        else
            Qt.callLater(handleIdleChanged);
    }

    function persistStayAwake(value) {
        if (stayAwakeWriter.running) {
            pendingPersist = !!value;
            hasPendingPersist = true;
            return;
        }
        stayAwakeWriter.command = ["bash", "-c", value ? "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"" : "rm -f \"$1\"", "qshell-stay-awake", stayAwakePath];
        stayAwakeWriter.running = true;
    }

    // Flip in memory first so the bar reacts on the click; the flag file is
    // the durable copy and its watcher re-delivers the same value.
    function setStayAwake(value) {
        const on = !!value;
        persistStayAwake(on);
        applyStayAwake(on, "requested");
        return on;
    }

    function statusJson() {
        return JSON.stringify({
            enabled: idleEnabled,
            stayAwake: stayAwake,
            stayAwakeLoaded: stayAwakeLoaded,
            stayAwakePath: stayAwakePath,
            idle: idleMonitor.isIdle,
            inIdleCycle: idledThisCycle,
            monitorsPoweredOff: monitorsPoweredOff,
            screensaver: screensaverTimeoutSeconds,
            blank: blankTimeoutSeconds,
            lock: lockTimeoutSeconds,
            firstIdle: firstIdleTimeoutSeconds,
            screensaverDelay: screensaverDelaySeconds,
            blankDelay: blankDelaySeconds,
            lockDelay: lockDelaySeconds,
            timers: {
                screensaver: screensaverTimer.running,
                blank: blankTimer.running,
                lock: lockTimer.running
            },
            lastEvent: lastEvent
        });
    }

    readonly property IdleMonitor idleMonitor: IdleMonitor {
        enabled: root.idleEnabled
        // Seconds (quickshell's IdleMonitor.timeout).
        timeout: root.firstIdleTimeoutSeconds
        // Honour idle inhibitors: a player holding one suspends the cycle.
        respectInhibitors: true
        onIsIdleChanged: root.handleIdleChanged()
    }

    readonly property Timer screensaverTimer: Timer {
        interval: root.screensaverDelaySeconds * 1000
        repeat: false
        onTriggered: {
            if (root.idleEnabled && root.idledThisCycle)
                root.launchScreensaver();
        }
    }

    // Launch through a Process, not execDetached: the exit code is the
    // fallback signal. screensaver-launch exits nonzero when the binary or
    // the quotes file is missing, and this stage then does what it always
    // did before the
    // screensaver existed — power the monitors off. Unless the blank stage is
    // configured, which already owns the panel on its own deadline: blanking
    // here too would drag that forward to the screensaver's time.
    readonly property Process screensaverProcess: Process {
        command: [Quickshell.env("HOME") + "/.dotfiles/bin/screensaver-launch"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 || !root.idledThisCycle)
                return;
            if (root.blankStageEnabled) {
                root.logEvent("screensaver", "unavailable — blank stage holds the panel");
                return;
            }
            root.logEvent("screensaver", "unavailable — monitors off");
            root.powerOffMonitors();
        }
    }

    readonly property Timer blankTimer: Timer {
        interval: root.blankDelaySeconds * 1000
        repeat: false
        onTriggered: {
            if (root.idleEnabled && root.idledThisCycle)
                root.powerOffMonitors();
        }
    }

    readonly property Timer lockTimer: Timer {
        interval: root.lockDelaySeconds * 1000
        repeat: false
        onTriggered: {
            if (root.idleEnabled && root.idledThisCycle)
                root.lockNow("lock-timeout");
        }
    }

    // The flag file IS the state. FileView watches both the file and its
    // directory, so creation and deletion both land here — `touch`/`rm` from
    // a terminal toggles stay-awake exactly like the bar indicator does.
    readonly property FileView stayAwakeFlag: FileView {
        path: root.stayAwakePath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyStayAwake(true, "state-file")
        onLoadFailed: root.applyStayAwake(false, "state-file")
        onFileChanged: reload()
        // Without an explicit read the view stays unloaded until something
        // asks for its contents, and neither signal above would ever fire.
        Component.onCompleted: reload()
    }

    // A FileView cannot arm its watch when the state dir itself is missing,
    // and nothing re-arms it later — reload() after a guaranteed mkdir is
    // the re-arm (same defence as Theme.qml; each service defends itself
    // because service construction order is undefined).
    readonly property Process stateDirProc: Process {
        command: ["bash", "-c", "mkdir -p \"$1\" && rm -f \"$1/idle\"", "qshell-idle-state", Quickshell.env("HOME") + "/.local/state/qshell"]
        onExited: root.stayAwakeFlag.reload()
        Component.onCompleted: running = true
    }

    readonly property Process stayAwakeWriter: Process {
        onExited: {
            if (root.hasPendingPersist) {
                const pending = root.pendingPersist;
                root.hasPendingPersist = false;
                root.persistStayAwake(pending);
            }
        }
    }

    readonly property IpcHandler ipc: IpcHandler {
        target: "idle"

        function status(): string {
            return root.statusJson();
        }

        // Upstream's verbs: enable/disable/toggle act on idle detection, i.e.
        // the inverse of stay-awake.
        function enable(): string {
            root.setStayAwake(false);
            return "idle on";
        }

        function disable(): string {
            root.setStayAwake(true);
            return "idle off";
        }

        function toggle(): string {
            return root.setStayAwake(root.idleEnabled) ? "idle off" : "idle on";
        }

        function stayAwake(): string {
            return root.stayAwake ? "on" : "off";
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Idle service, ported from omarchy's idle plugin (CREDITS.md).
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
//     "idle": { "screensaver": 150, "lock": 300 }
//
// Seconds, upstream's defaults. A missing/invalid value falls back to the
// default; 0 disables that stage; with both stages disabled the monitor
// itself never arms.
//
// Two deliberate adaptations of upstream's semantics:
//
//  * Their first stage launches a screensaver window (omarchy-launch-screensaver)
//    and their whole Hyprland openwindow/closewindow dance exists to know
//    whether that window is still up. We ship no screensaver, so our first
//    stage powers the monitors off via niri's DPMS action — there is no
//    window to track, and the launch-grace/dismiss bookkeeping goes with it.
//  * Because launching their screensaver itself reads as activity, upstream
//    ignores the wake signal while the screensaver is up and lets the lock
//    fire underneath it. Powering monitors off generates no input, so we take
//    the plain swayidle-style rule instead: any activity cancels every pending
//    stage and powers the monitors back on.
QtObject {
    id: root

    // The ShellRoot. Named `shellRoot`, not `shell`: a property named after
    // the outer id shadows it inside this object's own bindings.
    required property var shellRoot

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell"
    // Upstream keeps this flag at ~/.local/state/omarchy/indicators/stay-awake.
    // Presence is the whole state — the file's contents are never read.
    readonly property string stayAwakePath: stateDir + "/stay-awake"

    // Upstream's defaults (their Service.qml).
    readonly property int defaultScreensaverSeconds: 150
    readonly property int defaultLockSeconds: 300

    readonly property var idleConfig: shellRoot && shellRoot.config && shellRoot.config.idle && typeof shellRoot.config.idle === "object" ? shellRoot.config.idle : ({})
    readonly property int screensaverTimeoutSeconds: secondsFromConfig(idleConfig.screensaver, defaultScreensaverSeconds)
    readonly property int lockTimeoutSeconds: secondsFromConfig(idleConfig.lock, defaultLockSeconds)
    readonly property bool screensaverStageEnabled: screensaverTimeoutSeconds > 0
    readonly property bool lockStageEnabled: lockTimeoutSeconds > 0

    // The monitor waits for whichever stage comes first; the rest are that
    // stage's deadline plus the difference.
    readonly property int firstIdleTimeoutSeconds: {
        const stages = [];
        if (screensaverStageEnabled)
            stages.push(screensaverTimeoutSeconds);
        if (lockStageEnabled)
            stages.push(lockTimeoutSeconds);
        return stages.length > 0 ? Math.min.apply(Math, stages) : 0;
    }
    readonly property int screensaverDelaySeconds: Math.max(0, screensaverTimeoutSeconds - firstIdleTimeoutSeconds)
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
        logEvent("screensaver", "power-off-monitors");
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

    function lockNow(reason) {
        screensaverTimer.stop();
        lockTimer.stop();
        idledThisCycle = false;
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
        logEvent("idle-cycle-start", "screensaver=" + screensaverTimeoutSeconds + " lock=" + lockTimeoutSeconds);

        if (screensaverStageEnabled) {
            if (screensaverDelaySeconds === 0)
                powerOffMonitors();
            else
                screensaverTimer.restart();
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
        lockTimer.stop();
        if (idledThisCycle)
            logEvent("idle-cycle-cancel", reason || "requested");
        powerOnMonitors();
        idledThisCycle = false;
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
            lock: lockTimeoutSeconds,
            firstIdle: firstIdleTimeoutSeconds,
            screensaverDelay: screensaverDelaySeconds,
            lockDelay: lockDelaySeconds,
            timers: {
                screensaver: screensaverTimer.running,
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
        onTriggered: root.powerOffMonitors()
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
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/qshell"]
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

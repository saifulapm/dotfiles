import QtQuick
import Quickshell
import Quickshell.Io

// Night light service, ported from omarchy's nightlight plugin (CREDITS.md).
//
// Upstream's semantics are a two-state switch, not a schedule: night light is
// ON when the screen temperature sits below their 6000 K identity point, and
// their toggle only ever writes 4000 K (night) or 6500 K (day). There is no
// auto/sun-following state to port, so there is none here either — the same
// two temperatures, the same toggle.
//
// The mechanism differs because the daemon does. They shell out to
// `hyprctl hyprsunset temperature <k>` and read the current value back, so
// hyprsunset itself holds the state and the service is stateless between
// calls. wlsunset has no control channel at all: it is a long-lived client
// that grabs wlr-gamma-control for every output and holds it until it exits.
// So here the running daemon IS the "on" state, and:
//
//  * ON starts one `wlsunset -t 4000 -T 4001`. Pinning the high temperature
//    one kelvin above the low one is what turns a sun-following daemon into a
//    fixed one: wherever it thinks the sun is, the only temperatures it can
//    reach are 4000 and 4001 K. (Equal values are rejected outright — "high
//    temp must be higher than low temp" — which is why it is +1 and not the
//    same number.)
//  * OFF terminates it. The compositor restores the original gamma ramps when
//    a gamma-control client disconnects, so there is no day-temperature pass
//    to make: 6500 K is simply what the display already is.
//
// Only one client may hold gamma control per output, so the start command
// sweeps any stray `wlsunset` — from a crashed shell, or from the user's own
// terminal — before exec'ing its own. `setpriv --pdeathsig TERM` is
// load-bearing rather than decoration: quickshell does not signal a Process
// child when the shell exits, and a leaked wlsunset would leave the screen
// warm with nothing left to turn it off.
//
// State persists as a flag file at ~/.local/state/qshell/nightlight, watched
// like the stay-awake flag, so `touch`/`rm` from a terminal toggles night
// light exactly as the bar indicator does.
QtObject {
    id: root

    // Upstream's temperatures (their Service.qml), which are also wlsunset's
    // own defaults.
    readonly property int nightTemperature: 4000
    readonly property int dayTemperature: 6500
    // wlsunset refuses a high temperature that is not above the low one.
    readonly property int pinnedHighTemperature: nightTemperature + 1

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell"
    // Presence is the whole state — the contents are never read.
    readonly property string statePath: stateDir + "/nightlight"

    property bool enabled: false
    property bool stateLoaded: false
    readonly property int temperature: enabled ? nightTemperature : dayTemperature

    // False once the compositor has refused gamma control, which it does when
    // the display's CRTC reports no gamma table (this MacBook's Apple display
    // does exactly that: gamma_size 0, so wlsunset runs and changes nothing).
    // Hardware does not change under us, so this never flips back.
    property bool gammaSupported: true
    property string lastEvent: "starting"

    property bool hasPendingPersist: false
    property bool pendingPersist: false

    function logEvent(event, details) {
        lastEvent = details === undefined || details === "" ? event : event + ": " + details;
    }

    // ------------------------------------------------------------ the daemon
    function startDaemon() {
        if (daemon.running)
            return;
        logEvent("wlsunset", "start " + nightTemperature + "K");
        daemon.running = true;
    }

    function stopDaemon() {
        if (daemon.running) {
            // Terminates the exec'd wlsunset itself, so the compositor drops
            // its gamma control and restores the ramps.
            logEvent("wlsunset", "stop");
            daemon.running = false;
            return;
        }
        // Nothing of ours to stop, but a previous shell instance may have
        // leaked one and the screen would stay warm.
        if (!sweeper.running) {
            logEvent("wlsunset", "sweep");
            sweeper.running = true;
        }
    }

    function noteDaemonOutput(line) {
        const text = String(line || "");
        if (text.indexOf("gamma control") !== -1 && text.indexOf("failed") !== -1) {
            if (gammaSupported) {
                gammaSupported = false;
                console.warn("Nightlight: the compositor refused gamma control —", text.trim());
            }
            logEvent("gamma-failed", text.trim());
        }
    }

    // ------------------------------------------------------------- the state
    function applyNightlight(value, reason) {
        const on = !!value;
        const first = !stateLoaded;
        const changed = first || enabled !== on;
        enabled = on;
        stateLoaded = true;
        if (changed)
            logEvent("nightlight", (on ? "enabled" : "disabled") + (reason ? " " + reason : ""));
        if (on) {
            // Also covers the unchanged case: a restart adopting a flag file
            // that was already there, or a daemon that died under us.
            startDaemon();
            return;
        }
        // Nothing to stop on the first read of an absent flag file — that is
        // every cold start, and it must not cost a process.
        if (changed && !first)
            stopDaemon();
    }

    function persistNightlight(value) {
        if (stateWriter.running) {
            pendingPersist = !!value;
            hasPendingPersist = true;
            return;
        }
        stateWriter.command = ["bash", "-c", value ? "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"" : "rm -f \"$1\"", "qshell-nightlight", statePath];
        stateWriter.running = true;
    }

    // Flip in memory first so the bar reacts on the click; the flag file is
    // the durable copy and its watcher re-delivers the same value.
    function setNightlight(value) {
        const on = !!value;
        persistNightlight(on);
        applyNightlight(on, "requested");
        return on;
    }

    function toggle() {
        return setNightlight(!enabled);
    }

    function statusJson() {
        return JSON.stringify({
            enabled: enabled,
            stateLoaded: stateLoaded,
            temperature: temperature,
            nightTemperature: nightTemperature,
            dayTemperature: dayTemperature,
            statePath: statePath,
            running: daemon.running,
            gammaSupported: gammaSupported,
            lastEvent: lastEvent
        });
    }

    readonly property Process daemon: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", "pkill -x wlsunset; exec wlsunset -t " + root.nightTemperature + " -T " + root.pinnedHighTemperature]
        stdout: SplitParser {
            onRead: line => root.noteDaemonOutput(line)
        }
        stderr: SplitParser {
            onRead: line => root.noteDaemonOutput(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.enabled)
                root.logEvent("wlsunset", "exited unexpectedly (" + exitCode + ")");
        }
    }

    readonly property Process sweeper: Process {
        command: ["pkill", "-x", "wlsunset"]
    }

    readonly property Process stateWriter: Process {
        onExited: {
            if (root.hasPendingPersist) {
                const pending = root.pendingPersist;
                root.hasPendingPersist = false;
                root.persistNightlight(pending);
            }
        }
    }

    // The flag file IS the state. FileView watches the file and its directory,
    // so creation and deletion both land here.
    readonly property FileView stateFlag: FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyNightlight(true, "state-file")
        onLoadFailed: root.applyNightlight(false, "state-file")
        onFileChanged: reload()
        // Without an explicit read the view stays unloaded and neither signal
        // above ever fires.
        Component.onCompleted: reload()
    }

    // A FileView cannot arm its watch when the state dir itself is missing,
    // and nothing re-arms it later — reload() after a guaranteed mkdir is
    // the re-arm (same defence as Theme.qml and Idle.qml).
    readonly property Process stateDirProc: Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/qshell"]
        onExited: root.stateFlag.reload()
        Component.onCompleted: running = true
    }

    readonly property IpcHandler ipc: IpcHandler {
        target: "nightlight"

        // Upstream's verbs.
        function status(): string {
            return root.statusJson();
        }

        function enable(): string {
            root.setNightlight(true);
            return "enabled";
        }

        function disable(): string {
            root.setNightlight(false);
            return "disabled";
        }

        function toggle(): string {
            return root.toggle() ? "enabled" : "disabled";
        }
    }
}

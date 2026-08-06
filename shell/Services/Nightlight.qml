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
// light exactly as the bar indicator does. The file's CONTENT is the night
// temperature: a bare kelvin number (`echo 3500 > .../nightlight`, or the
// IPC `temperature` verb) restarts the daemon at that warmth, an empty file
// keeps upstream's 4000 K. The temperature lives in the same file as the
// on/off state because that file already survives shell restarts and is
// already watched — a second store would need a second watcher and could
// disagree with the first.
QtObject {
    id: root

    // Upstream's temperatures (their Service.qml), which are also wlsunset's
    // own defaults.
    readonly property int defaultNightTemperature: 4000
    property int nightTemperature: defaultNightTemperature
    readonly property int dayTemperature: 6500
    // wlsunset refuses a high temperature that is not above the low one.
    readonly property int pinnedHighTemperature: nightTemperature + 1

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell"
    // Presence is on/off; the content, when numeric, is the temperature.
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
    // wlsunset's own sanity bounds, roughly candlelight to past-daylight.
    function clampTemperature(value) {
        const parsed = parseInt(String(value).trim(), 10);
        if (!isFinite(parsed) || isNaN(parsed))
            return -1;
        return Math.max(1000, Math.min(10000, parsed));
    }

    // The flag file landed (created or rewritten): adopt its temperature,
    // bouncing a running daemon when the warmth changed — wlsunset has no
    // control channel, so a new temperature is a new process.
    function adoptStateFile(raw) {
        const text = String(raw || "").trim();
        const parsed = text === "" ? -1 : clampTemperature(text);
        const temp = parsed > 0 ? parsed : defaultNightTemperature;
        if (temp !== nightTemperature) {
            nightTemperature = temp;
            if (daemon.running) {
                logEvent("wlsunset", "retemperature " + temp + "K");
                restartPending = true;
                daemon.running = false;
            }
        }
        applyNightlight(true, "state-file");
    }

    // Write the temperature into the flag file; the watcher applies it. A
    // set while off turns night light on — the number only means anything
    // with the daemon running, and the file's existence IS the on state.
    function setTemperature(value) {
        const temp = clampTemperature(value);
        if (temp <= 0)
            return -1;
        tempWriter.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\n' \"$2\" > \"$1\"", "qshell-nightlight-temp", statePath, String(temp)];
        tempWriter.running = true;
        return temp;
    }

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
        // Re-enabling writes the remembered warmth back, so an off/on cycle
        // does not silently reset a custom temperature to the default.
        if (value && nightTemperature !== defaultNightTemperature)
            stateWriter.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\n' \"$2\" > \"$1\"", "qshell-nightlight", statePath, String(nightTemperature)];
        else
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
            // A temperature change bounced the process on purpose; bring it
            // back up at the new warmth once the old one is really gone.
            if (root.restartPending) {
                root.restartPending = false;
                if (root.enabled) {
                    daemon.running = true;
                    return;
                }
            }
            if (root.enabled)
                root.logEvent("wlsunset", "exited unexpectedly (" + exitCode + ")");
        }
    }

    // Set while a running daemon is being stopped only to pick up a new
    // temperature — the exit handler above restarts it.
    property bool restartPending: false

    readonly property Process tempWriter: Process {}

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
        onLoaded: root.adoptStateFile(text())
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

        // `nightlight temperature 3500` — writes the kelvin value into the
        // state file (which also turns night light on; the number is
        // meaningless with the daemon stopped). Bounds 1000-10000 K.
        function temperature(value: string): string {
            const applied = root.setTemperature(value);
            return applied > 0 ? String(applied) + "K" : "invalid: " + value;
        }
    }
}

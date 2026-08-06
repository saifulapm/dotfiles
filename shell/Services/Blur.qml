import QtQuick
import Quickshell
import Quickshell.Io

// Background-blur switch. Off by default; nothing anywhere requests blur
// until the flag file exists, so the disabled path costs one file watcher.
//
// Two consumers hang off the one state:
//
//  * The shell's own surfaces. Theme.blurActive turns their card fills into
//    glass, and each surface window publishes a BackgroundEffect.blurRegion
//    (ext-background-effect-v1) shaped exactly like its card, so niri blurs
//    only behind the card — never the fullscreen overlay around it. niri
//    grants protocol-requested blur with no compositor config at all.
//
//  * App windows. niri can only be told about those through its config, so
//    this service renders ~/.local/state/qshell/niri-blur.kdl — a window-rule
//    turning blur on behind every window plus slightly deeper opacities than
//    the base 0.985/0.96 so the frost actually reads. config.kdl includes the
//    fragment (optional=true) and niri live-reloads included files, so a
//    toggle needs no compositor restart.
//
// Both paths ride niri's xray blur: the wallpaper is blurred once into a
// cached texture and every blurred surface is then one textured quad, so the
// enabled steady state costs nothing per frame. The non-xray mode (blurring
// live window content) is experimental and re-blurs every frame — nothing
// here ever asks for it.
//
// State persists as a flag file at ~/.local/state/qshell/blur, watched like
// nightlight/stay-awake, so `touch`/`rm` from a terminal toggles blur exactly
// as the menu row does.
QtObject {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell"
    readonly property string statePath: stateDir + "/blur"
    readonly property string fragmentPath: stateDir + "/niri-blur.kdl"

    property bool enabled: false
    property bool stateLoaded: false
    property string lastEvent: "starting"

    // The app-window side of the switch. Opacity rules ride along because
    // blur behind a 98.5%-opaque window is invisible; these are the values
    // the frost was tuned at.
    readonly property string fragmentOn: "// Written by the qshell blur service (Services/Blur.qml) — do not edit.\n" + "// Frosted app windows over niri's cached xray wallpaper blur. Global\n" + "// blur tuning stays at niri's defaults (passes 3, offset 3).\n" + "window-rule {\n" + "    background-effect {\n" + "        blur true\n" + "    }\n" + "}\n" + "\n" + "window-rule {\n" + "    opacity 0.95\n" + "}\n" + "\n" + "window-rule {\n" + "    match is-active=false\n" + "    opacity 0.9\n" + "}\n"
    readonly property string fragmentOff: "// Written by the qshell blur service (Services/Blur.qml) — do not edit.\n" + "// Blur is disabled; config.kdl includes this file optionally.\n"

    function logEvent(event, details) {
        lastEvent = details === undefined || details === "" ? event : event + ": " + details;
    }

    function applyBlur(value, reason) {
        const on = !!value;
        const first = !stateLoaded;
        const changed = first || enabled !== on;
        enabled = on;
        stateLoaded = true;
        if (!changed)
            return;
        logEvent("blur", (on ? "enabled" : "disabled") + (reason ? " " + reason : ""));
        // The niri fragment follows every state change, including an external
        // touch/rm of the flag. A cold start re-renders it only when blur is
        // on: the off fragment is inert, and every boot rewriting it would
        // poke a niri config reload for nothing.
        if (!first || on)
            writeFragment(on);
    }

    // tmp+mv in the same directory: niri watches included files, and a
    // half-written include must never be what it reloads.
    function writeFragment(on) {
        fragmentQueue.push(on);
        drainFragmentQueue();
    }

    property var fragmentQueue: []

    function drainFragmentQueue() {
        if (fragmentWriter.running || fragmentQueue.length === 0)
            return;
        const on = fragmentQueue.shift();
        fragmentWriter.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"", "qshell-blur-fragment", fragmentPath, on ? fragmentOn : fragmentOff];
        fragmentWriter.running = true;
    }

    function persistBlur(value) {
        if (stateWriter.running) {
            pendingPersist = !!value;
            hasPendingPersist = true;
            return;
        }
        stateWriter.command = ["bash", "-c", value ? "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"" : "rm -f \"$1\"", "qshell-blur", statePath];
        stateWriter.running = true;
    }

    // Flip in memory first so the surfaces react on the click; the flag file
    // is the durable copy and its watcher re-delivers the same value.
    function setBlur(value) {
        const on = !!value;
        persistBlur(on);
        applyBlur(on, "requested");
        return on;
    }

    function toggle() {
        return setBlur(!enabled);
    }

    function statusJson() {
        return JSON.stringify({
            enabled: enabled,
            stateLoaded: stateLoaded,
            statePath: statePath,
            fragmentPath: fragmentPath,
            lastEvent: lastEvent
        });
    }

    property bool hasPendingPersist: false
    property bool pendingPersist: false

    readonly property Process fragmentWriter: Process {
        onExited: root.drainFragmentQueue()
    }

    readonly property Process stateWriter: Process {
        onExited: {
            if (root.hasPendingPersist) {
                const pending = root.pendingPersist;
                root.hasPendingPersist = false;
                root.persistBlur(pending);
            }
        }
    }

    // The flag file IS the state. FileView watches the file and its directory,
    // so creation and deletion both land here.
    readonly property FileView stateFlag: FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyBlur(true, "state-file")
        onLoadFailed: root.applyBlur(false, "state-file")
        onFileChanged: reload()
        // Without an explicit read the view stays unloaded and neither signal
        // above ever fires.
        Component.onCompleted: reload()
    }

    // A FileView cannot arm its watch when the state dir itself is missing —
    // reload() after a guaranteed mkdir is the re-arm (same defence as
    // Theme.qml, Idle.qml and Nightlight.qml).
    readonly property Process stateDirProc: Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/qshell"]
        onExited: root.stateFlag.reload()
        Component.onCompleted: running = true
    }

    readonly property IpcHandler ipc: IpcHandler {
        target: "blur"

        function status(): string {
            return root.statusJson();
        }

        function enable(): string {
            root.setBlur(true);
            return "enabled";
        }

        function disable(): string {
            root.setBlur(false);
            return "disabled";
        }

        function toggle(): string {
            return root.toggle() ? "enabled" : "disabled";
        }
    }
}

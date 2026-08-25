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
//  * foot terminals. A whole-window fade dims glyphs with the background, so
//    the foot family is excluded from the fragment's opacity pair (keeping
//    the base 0.985/0.96 focus cue) and its frost is foot's own background-
//    only alpha instead: bin/foot-frost, chained onto the fragment write,
//    flips the theme-apply-rendered alpha include for future windows and
//    re-specs live ones over OSC 11. Text stays crisp at any frost depth.
//
// Both paths ride niri's xray blur: the wallpaper is blurred once into a
// cached texture and every blurred surface is then one textured quad, so the
// enabled steady state costs nothing per frame. The non-xray mode (blurring
// live window content) is experimental and re-blurs every frame — nothing
// here ever asks for it.
//
// State: the theme carries the DEFAULT (`[blur] enabled`, usually via its
// preset) plus the fragment parameters (noise, saturation, frost opacities);
// the flag file at ~/.local/state/qshell/blur is the USER override. The file
// holds "on" or "off" and wins over any theme; absent means follow the
// theme. A legacy empty flag (the old existence-is-on contract) reads as
// "on". `echo on > blur` / `rm blur` from a terminal work exactly like the
// menu row and the IPC verbs.
QtObject {
    id: root

    // The active Theme service (wired in shell.qml): blur default + fragment
    // parameters are theme tokens, so a theme switch restyles the frost.
    property var theme: null

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell"
    readonly property string statePath: stateDir + "/blur"
    readonly property string fragmentPath: stateDir + "/niri-blur.kdl"

    // "", "on" or "off" — the flag file's content ("" = no override).
    property string override: ""
    readonly property bool themeDefault: theme ? theme.blurThemeDefault : false

    property bool enabled: false
    property bool stateLoaded: false
    property string lastEvent: "starting"

    // The app-window side of the switch. Opacity rules ride along because
    // blur behind a 98.5%-opaque window is invisible; the pair is the
    // theme's [opacity] blur-active/blur-inactive.
    // The excludes are the foot family (the same set as config.kdl's scroll
    // rule): those windows frost via their own background alpha, not a
    // whole-window fade — see the header comment.
    readonly property string footExcludes: "    exclude app-id=\"^foot$\"\n" + "    exclude app-id=\"^qshell-float$\"\n" + "    exclude app-id=\"^qshell-float-yazi$\"\n" + "    exclude app-id=\"^cliamp-main$\"\n" + "    exclude app-id=\"^tmux-main$\"\n" + "    exclude app-id=r#\"^TUI\\.(float|tile)$\"#\n"
    // THE SHELL IS NOT AN APP WINDOW. Every rule in this fragment is written
    // for the windows the shell sits above, and since 2026-08-20 the shell
    // itself has one toplevel among them — the dekho hub (Modules/Dekho),
    // app-id org.quickshell like any Quickshell window. It is deliberately
    // opaque (a cinema is a room with the lights off), so the frost pair
    // would make backdrop art fight the wallpaper through it, and blurring
    // the wallpaper behind a maximized opaque window is a pass with nothing
    // to show for it. The shell's other surfaces are layer-shell and are not
    // matched by window rules at all; this keeps its window on the same side
    // of the line as the rest of it. The media exemption re-stated at the
    // bottom mirrors the theme include's, for the same later-rule-wins
    // reason: a frosted mpv is a broken movie.
    readonly property string shellExclude: "    exclude app-id=r#\"^org\\.quickshell$\"#\n"
    readonly property string mediaExemption: "window-rule {\n" + "    match app-id=r#\"^(zoom|vlc|mpv|org\\.kde\\.kdenlive|com\\.obsproject\\.Studio|com\\.github\\.PintaProject\\.Pinta|imv)$\"#\n" + "    match app-id=r#\"^org\\.quickshell$\"#\n" + "    match title=r#\"Picture.?in.?[Pp]icture\"#\n" + "    opacity 1.0\n" + "}\n"

    // The theme's frost parameters, with the pre-theme constants as
    // fallbacks. noise/saturation are emitted only when they leave niri's
    // own defaults (0.02 / 1.5), so a default theme renders the proven
    // minimal fragment.
    readonly property real frostNoise: theme ? theme.blurNoise : 0.02
    readonly property real frostSaturation: theme ? theme.blurSaturation : 1.5
    readonly property real frostOpacityActive: theme ? theme.blurOpacityActive : 0.95
    readonly property real frostOpacityInactive: theme ? theme.blurOpacityInactive : 0.9

    function fragmentOnText() {
        let effect = "    background-effect {\n" + "        blur true\n";
        if (Math.abs(frostNoise - 0.02) > 0.0001)
            effect += "        noise " + frostNoise + "\n";
        if (Math.abs(frostSaturation - 1.5) > 0.0001)
            effect += "        saturation " + frostSaturation + "\n";
        effect += "    }\n";
        return "// Written by the qshell blur service (Services/Blur.qml) — do not edit.\n" + "// Frosted app windows over niri's cached xray wallpaper blur. Global\n" + "// blur tuning stays at niri's defaults (passes 3, offset 3).\n" + "window-rule {\n" + shellExclude + effect + "}\n" + "\n" + "window-rule {\n" + "    opacity " + frostOpacityActive + "\n" + footExcludes + shellExclude + "}\n" + "\n" + "window-rule {\n" + "    match is-active=false\n" + "    opacity " + frostOpacityInactive + "\n" + footExcludes + shellExclude + "}\n" + "\n" + mediaExemption;
    }
    readonly property string fragmentOff: "// Written by the qshell blur service (Services/Blur.qml) — do not edit.\n" + "// Blur is disabled; config.kdl includes this file optionally.\n"

    function logEvent(event, details) {
        lastEvent = details === undefined || details === "" ? event : event + ": " + details;
    }

    // Effective state from (override, themeDefault); rewrites the fragment
    // on every change. A cold start re-renders it only when blur is on: the
    // off fragment is inert, and every boot rewriting it would poke a niri
    // config reload for nothing.
    function applyState(reason) {
        const on = override === "" ? themeDefault : override === "on";
        const first = !stateLoaded;
        const changed = first || enabled !== on;
        enabled = on;
        stateLoaded = true;
        if (!changed)
            return;
        logEvent("blur", (on ? "enabled" : "disabled") + (reason ? " " + reason : ""));
        if (!first || on)
            writeFragment(on);
    }

    // A theme switch can flip the default (override absent) or restyle the
    // frost parameters (blur on): both re-render the fragment.
    onThemeDefaultChanged: if (stateLoaded)
        applyState("theme-default")
    readonly property string frostParamsKey: [frostNoise, frostSaturation, frostOpacityActive, frostOpacityInactive].join("|")
    onFrostParamsKeyChanged: if (stateLoaded && enabled)
        writeFragment(true)

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
        // foot-frost rides the same write: the niri fragment and the foot
        // alpha include must flip together or windows frost twice / not at
        // all. Semicolon, not &&: a failed fragment write must not strand
        // the foot side on the old state.
        fragmentWriter.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"; foot-frost \"$3\"", "qshell-blur-fragment", fragmentPath, on ? fragmentOnText() : fragmentOff, on ? "on" : "off"];
        fragmentWriter.running = true;
    }

    // value: "on" | "off" writes the override; "" removes the file (follow
    // the theme). The watcher re-delivers whatever lands.
    function persistOverride(value) {
        if (stateWriter.running) {
            pendingPersist = value;
            hasPendingPersist = true;
            return;
        }
        stateWriter.command = value === "" ? ["bash", "-c", "rm -f \"$1\"", "qshell-blur", statePath] : ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "qshell-blur", statePath, value];
        stateWriter.running = true;
    }

    // Flip in memory first so the surfaces react on the click; the flag file
    // is the durable copy and its watcher re-delivers the same value.
    function setBlur(value) {
        const on = !!value;
        override = on ? "on" : "off";
        persistOverride(override);
        applyState("requested");
        return on;
    }

    // Clear the override: blur follows the active theme again.
    function setAuto() {
        override = "";
        persistOverride("");
        applyState("auto");
        return enabled;
    }

    function toggle() {
        return setBlur(!enabled);
    }

    function statusJson() {
        return JSON.stringify({
            enabled: enabled,
            override: override,
            themeDefault: themeDefault,
            stateLoaded: stateLoaded,
            statePath: statePath,
            fragmentPath: fragmentPath,
            lastEvent: lastEvent
        });
    }

    property bool hasPendingPersist: false
    property string pendingPersist: ""

    readonly property Process fragmentWriter: Process {
        onExited: root.drainFragmentQueue()
    }

    readonly property Process stateWriter: Process {
        onExited: {
            if (root.hasPendingPersist) {
                const pending = root.pendingPersist;
                root.hasPendingPersist = false;
                root.persistOverride(pending);
            }
        }
    }

    // The flag file IS the override. FileView watches the file and its
    // directory, so creation, edits and deletion all land here. An empty
    // file is the legacy existence-is-on contract and still reads as "on".
    readonly property FileView stateFlag: FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.override = String(text()).trim() === "off" ? "off" : "on";
            root.applyState("state-file");
        }
        onLoadFailed: {
            root.override = "";
            root.applyState("state-file");
        }
        onFileChanged: reload()
        // Without an explicit read the view stays unloaded and neither signal
        // above ever fires.
        Component.onCompleted: reload()
    }

    // The wallpaper path, for the in-scene frost backdrops
    // (components/CardFrost.qml): niri's xray blur shows only the blurred
    // wallpaper, which the cards reproduce in-scene so the frost can ride
    // their entrance animations. Same state file Background and Lock watch.
    property string wallpaperPath: ""

    readonly property FileView backgroundFile: FileView {
        // Hardcoded $HOME, not stateDir's XDG_STATE_HOME fallback: every
        // writer of this file (Background.qml, ImagePicker.qml) and its
        // other reader (Lock.qml) spell the path this way, and a watcher
        // must watch where its writer writes.
        path: Quickshell.env("HOME") + "/.local/state/qshell/background"
        watchChanges: true
        printErrors: false
        onLoaded: root.wallpaperPath = String(text() || "").trim()
        onLoadFailed: root.wallpaperPath = ""
        onFileChanged: reload()
        Component.onCompleted: reload()
    }

    // A FileView cannot arm its watch when the state dir itself is missing —
    // reload() after a guaranteed mkdir is the re-arm (same defence as
    // Theme.qml and Idle.qml).
    readonly property Process stateDirProc: Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/qshell"]
        onExited: {
            root.stateFlag.reload();
            root.backgroundFile.reload();
        }
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

        // Drop the user override and follow the active theme's default.
        function auto(): string {
            return "auto (" + (root.setAuto() ? "enabled" : "disabled") + " by theme)";
        }
    }
}

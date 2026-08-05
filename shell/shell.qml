import QtQuick
import Quickshell
import Quickshell.Io

import qs.Services
import qs.Modules.Bar
import qs.Modules.Lock
import qs.Modules.Launcher
import qs.Modules.Notifications
import qs.Modules.Osd
import qs.Modules.Polkit

// Single long-running ShellRoot. One process: panels are summoned by IPC
// into this instance, never by spawning a second `qs`.
//
// Services are instantiated here once and passed down by property injection.
// Relative-path singleton imports do NOT share state (omarchy, CREDITS.md) —
// nothing in this tree may `pragma Singleton` a service.
ShellRoot {
    id: shell

    property Theme theme: Theme {}
    property Niri niri: Niri {}
    // Eager by necessity: must own org.freedesktop.Notifications from startup.
    // The popup UI below stays lazy.
    property Notifs notifs: Notifs {}
    property Audio audio: Audio {}

    // Hardcoded fallback: a broken or missing shell.json still renders this
    // usable bar. The on-disk shell.json fully replaces it when valid — no
    // deep merge.
    readonly property var fallbackConfig: ({
            version: 1,
            bar: {
                position: "top",
                left: ["workspaces", "window"],
                center: ["clock"],
                right: []
            }
        })
    property var config: fallbackConfig

    function applyConfig(raw) {
        const text = String(raw || "").trim();
        if (!text) {
            config = fallbackConfig;
            return;
        }
        try {
            const parsed = JSON.parse(text);
            if (parsed && typeof parsed === "object" && parsed.version === 1) {
                config = parsed;
            } else {
                console.warn("shell.json missing version: 1 — using fallback config");
                config = fallbackConfig;
            }
        } catch (e) {
            console.warn("shell.json parse failed — using fallback config:", e);
            config = fallbackConfig;
        }
    }

    FileView {
        path: Quickshell.shellDir + "/shell.json"
        watchChanges: true
        printErrors: false
        onLoaded: shell.applyConfig(text())
        onFileChanged: reload()
        onLoadFailed: shell.applyConfig("")
    }

    Bar {
        shell: shell
        theme: shell.theme
        niri: shell.niri
        config: shell.config.bar && typeof shell.config.bar === "object" ? shell.config.bar : shell.fallbackConfig.bar
    }

    // Lock is the only module allowed to stay loaded while active — it unloads
    // itself after unlock. Nothing below instantiates at startup.
    LazyLoader {
        id: lockLoader
        active: false
        component: Lock {
            theme: shell.theme
        }
    }

    Connections {
        target: lockLoader.active ? lockLoader.item : null
        function onLockedChanged() {
            if (!lockLoader.item.locked)
                Qt.callLater(() => lockLoader.active = false);
        }
    }

    // Popup UI loads on the first notification and stays; window is visible
    // only while toasts exist.
    Loader {
        active: shell.notifs.everNotified
        sourceComponent: Popups {
            theme: shell.theme
            notifs: shell.notifs
        }
    }

    IpcHandler {
        target: "notifs"

        function dnd(): string {
            shell.notifs.dnd = !shell.notifs.dnd;
            return shell.notifs.dnd ? "dnd on" : "dnd off";
        }

        function dismissAll(): string {
            shell.notifs.dismissAll();
            return "ok";
        }

        function count(): int {
            return shell.notifs.active.length;
        }
    }

    Osd {
        id: osd
        theme: shell.theme
        audio: shell.audio
    }

    Polkit {
        id: polkit
        theme: shell.theme
    }

    IpcHandler {
        target: "polkit"

        function status(): string {
            return JSON.stringify({
                registered: polkit.agent.isRegistered,
                active: polkit.active
            });
        }

        function cancel(): string {
            polkit.cancel();
            return "ok";
        }
    }

    IpcHandler {
        target: "osd"

        function brightnessUp(): string {
            osd.brightnessAdjust(1);
            return "ok";
        }

        function brightnessDown(): string {
            osd.brightnessAdjust(-1);
            return "ok";
        }

        function status(): string {
            return JSON.stringify({
                armed: osd.armed,
                showing: osd.showing,
                everShown: osd.everShown,
                kind: osd.kind,
                level: osd.level,
                audioReady: shell.audio.ready,
                sinkNull: shell.audio.sink === null,
                volume: shell.audio.volume,
                sourceNull: shell.audio.source === null,
                sourceAudioNull: shell.audio.source !== null && shell.audio.source.audio === null,
                micMuted: shell.audio.micMuted
            });
        }
    }

    LazyLoader {
        id: launcherLoader
        active: false
        component: Launcher {
            theme: shell.theme
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): string {
            launcherLoader.active = true;
            launcherLoader.item.toggle();
            return "ok";
        }

        function show(): string {
            launcherLoader.active = true;
            launcherLoader.item.show();
            return "ok";
        }

        function hide(): string {
            if (launcherLoader.active)
                launcherLoader.item.hide();
            return "ok";
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): string {
            lockLoader.active = true;
            lockLoader.item.lock();
            return "ok";
        }

        function status(): string {
            return lockLoader.active && lockLoader.item.locked ? "locked" : "unlocked";
        }

        // Escape hatch for the nested dev session ONLY. In a production session
        // (no QSHELL_DEV) unlocking requires PAM, full stop.
        function devUnlock(): string {
            if (Quickshell.env("QSHELL_DEV") !== "1")
                return "denied";
            if (lockLoader.active)
                lockLoader.item.forceUnlock();
            return "ok";
        }
    }

    IpcHandler {
        target: "shell"

        function ping(): string {
            return "ok";
        }

        function reloadConfig(): string {
            shell.applyConfig("");
            return "ok";
        }
    }
}

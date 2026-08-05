import QtQuick
import Quickshell
import Quickshell.Io

import qs.Services
import qs.Modules.Bar
import qs.Modules.Lock

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

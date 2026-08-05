import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

import qs.Services
import qs.Modules.Bar
import qs.Modules.Clipboard
import qs.Modules.Emojis
import qs.Modules.Lock
import qs.Modules.Launcher
import qs.Modules.Menu
import qs.Modules.Notifications
import qs.Modules.Osd
import qs.Modules.Polkit
import qs.Modules.Reminders
import qs.Modules.ThemeSwitcher
import qs.Modules.Background

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
    // Eager like Notifs, and for the same kind of reason: an idle monitor
    // that is not armed is not an idle monitor. It costs one wayland object
    // and one file watcher.
    property Idle idle: Idle {
        shellRoot: shell
    }

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
    // False while shell.json exists but is broken: settings writes must not
    // clobber a config the user could still fix by hand. A missing file is
    // fine to create.
    property bool configWritable: true

    function applyConfig(raw) {
        const text = String(raw || "").trim();
        if (!text) {
            config = fallbackConfig;
            configWritable = true;
            return;
        }
        try {
            const parsed = JSON.parse(text);
            if (parsed && typeof parsed === "object" && parsed.version === 1) {
                config = parsed;
                configWritable = true;
            } else {
                console.warn("shell.json missing version: 1 — using fallback config");
                config = fallbackConfig;
                configWritable = false;
            }
        } catch (e) {
            console.warn("shell.json parse failed — using fallback config:", e);
            config = fallbackConfig;
            configWritable = false;
        }
    }

    // Rewrite the layout entry (or entries) matching widgetId with the given
    // inline-settings object, and persist shell.json — omarchy's
    // updateEntryInline. All other config keys pass through untouched; an
    // entry whose only key is `id` collapses back to the plain string form.
    function updateEntryInline(widgetId, entry) {
        if (!configWritable) {
            console.warn("shell.json is broken on disk — refusing to overwrite it with widget settings");
            return false;
        }
        const copy = JSON.parse(JSON.stringify(config));
        if (!copy.bar || typeof copy.bar !== "object")
            return false;
        let dirty = false;
        for (const section of ["left", "center", "right"]) {
            const arr = copy.bar[section];
            if (!Array.isArray(arr))
                continue;
            for (let i = 0; i < arr.length; i++) {
                const id = typeof arr[i] === "string" ? arr[i] : (arr[i] && arr[i].id);
                if (id !== widgetId)
                    continue;
                const next = {
                    id: widgetId
                };
                for (const key in entry) {
                    if (key !== "id")
                        next[key] = entry[key];
                }
                const replacement = Object.keys(next).length === 1 ? widgetId : next;
                if (JSON.stringify(arr[i]) !== JSON.stringify(replacement)) {
                    arr[i] = replacement;
                    dirty = true;
                }
            }
        }
        if (!dirty)
            return false;
        copy.version = 1;
        // Applied in memory first so the UI reflects the write immediately;
        // the FileView round trip re-delivers the same content.
        config = copy;
        configFile.setText(JSON.stringify(copy, null, 2) + "\n");
        return true;
    }

    // Shared entry points for the bar's buttons, the command menu and the IPC
    // targets. Each one wakes its LazyLoader on first use.
    function toggleLauncher() {
        launcherLoader.active = true;
        launcherLoader.item.toggle();
    }

    function toggleMenu() {
        menuLoader.active = true;
        menuLoader.item.toggle();
    }

    function toggleThemes() {
        themesLoader.active = true;
        themesLoader.item.toggle();
    }

    function toggleWallpaper() {
        wallpaperLoader.active = true;
        wallpaperLoader.item.toggle();
    }

    function toggleEmojis() {
        emojisLoader.active = true;
        emojisLoader.item.toggle();
    }

    function toggleClipboard() {
        clipboard.toggle();
    }

    function toggleReminders() {
        remindersLoader.active = true;
        remindersLoader.item.toggle();
    }

    function lockSession() {
        lockLoader.active = true;
        lockLoader.item.lock();
    }

    // For anything that must not re-lock an already locked session (the idle
    // service's lock stage).
    readonly property bool locked: lockLoader.active && lockLoader.item !== null && lockLoader.item.locked

    FileView {
        id: configFile
        path: Quickshell.shellDir + "/shell.json"
        watchChanges: true
        // Writes go through a temp file + rename, so the inotify watcher
        // (and any external reader) never sees a half-written config.
        atomicWrites: true
        printErrors: false
        onLoaded: shell.applyConfig(text())
        onFileChanged: reload()
        onLoadFailed: shell.applyConfig("")
        onSaveFailed: error => console.warn("shell.json write failed:", error)
    }

    Background {
        theme: shell.theme
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
            shell.toggleLauncher();
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

    LazyLoader {
        id: menuLoader
        active: false
        component: Menu {
            theme: shell.theme
            shellRoot: shell
        }
    }

    IpcHandler {
        target: "menu"

        function toggle(): string {
            shell.toggleMenu();
            return "ok";
        }

        function show(): string {
            menuLoader.active = true;
            menuLoader.item.show();
            return "ok";
        }

        function hide(): string {
            if (menuLoader.active)
                menuLoader.item.hide();
            return "ok";
        }

        // Jump straight to a submenu (or fire a leaf) by id or alias:
        // `qs ipc call menu open system`, `… open screenshot`.
        function open(route: string): string {
            menuLoader.active = true;
            return menuLoader.item.openRoute(route);
        }
    }

    LazyLoader {
        id: emojisLoader
        active: false
        component: Emojis {
            theme: shell.theme
        }
    }

    IpcHandler {
        target: "emojis"

        function toggle(): string {
            shell.toggleEmojis();
            return "ok";
        }

        function show(): string {
            emojisLoader.active = true;
            emojisLoader.item.show();
            return "ok";
        }

        function hide(): string {
            if (emojisLoader.active)
                emojisLoader.item.hide();
            return "ok";
        }
    }

    // Eager by necessity, like Notifs: the capture watcher has to be running
    // before anything is copied, or there is no history to pick from. Its
    // picker window stays lazy inside the module.
    Clipboard {
        id: clipboard
        theme: shell.theme
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): string {
            shell.toggleClipboard();
            return "ok";
        }

        function show(): string {
            clipboard.show();
            return "ok";
        }

        function hide(): string {
            clipboard.hide();
            return "ok";
        }
    }

    LazyLoader {
        id: remindersLoader
        active: false
        component: ReminderFlow {
            theme: shell.theme
        }
    }

    IpcHandler {
        target: "reminders"

        function toggle(): string {
            shell.toggleReminders();
            return "ok";
        }

        function show(): string {
            remindersLoader.active = true;
            remindersLoader.item.show();
            return "ok";
        }

        function hide(): string {
            if (remindersLoader.active)
                remindersLoader.item.hide();
            return "ok";
        }
    }

    LazyLoader {
        id: themesLoader
        active: false
        component: ThemeSwitcher {
            theme: shell.theme
        }
    }

    IpcHandler {
        target: "theme"

        function toggle(): string {
            shell.toggleThemes();
            return "ok";
        }

        function show(): string {
            themesLoader.active = true;
            themesLoader.item.show();
            return "ok";
        }

        function hide(): string {
            if (themesLoader.active)
                themesLoader.item.hide();
            return "ok";
        }
    }

    LazyLoader {
        id: wallpaperLoader
        active: false
        component: ImagePicker {
            theme: shell.theme
        }
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): string {
            shell.toggleWallpaper();
            return "ok";
        }

        function show(): string {
            wallpaperLoader.active = true;
            wallpaperLoader.item.show();
            return "ok";
        }

        function hide(): string {
            if (wallpaperLoader.active)
                wallpaperLoader.item.hide();
            return "ok";
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): string {
            shell.lockSession();
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

    // Media keys land here (niri binds spawn `qs ipc call media …`). The
    // Mpris singleton is lazy — it only touches D-Bus on the first call.
    IpcHandler {
        target: "media"

        function activePlayer(): var {
            const all = Mpris.players.values;
            return all.find(p => p.isPlaying) || all[0] || null;
        }

        function playPause(): string {
            const p = activePlayer();
            if (p && p.canTogglePlaying)
                p.togglePlaying();
            return p ? "ok" : "no player";
        }

        function stop(): string {
            const p = activePlayer();
            if (p)
                p.stop();
            return p ? "ok" : "no player";
        }

        function next(): string {
            const p = activePlayer();
            if (p && p.canGoNext)
                p.next();
            return p ? "ok" : "no player";
        }

        function previous(): string {
            const p = activePlayer();
            if (p && p.canGoPrevious)
                p.previous();
            return p ? "ok" : "no player";
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

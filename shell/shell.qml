import QtQuick
import Quickshell
import Quickshell.Io

import qs.Services
import qs.Modules.Bar
import qs.Modules.Clipboard
import qs.Modules.Emojis
import qs.Modules.FilePicker
import qs.Modules.Lock
import qs.Modules.Launcher
import qs.Modules.Menu
import qs.Modules.Notifications
import qs.Modules.Osd
import qs.Modules.Polkit
import qs.Modules.Reminders
import qs.Modules.ThemeSwitcher
import qs.Modules.Background
import "Modules/Bar/BarModel.js" as BarModel

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
    // The popup UI below stays lazy. `niri` is what click-to-focus resolves a
    // notification's sender against.
    property Notifs notifs: Notifs {
        niri: shell.niri
    }
    property Audio audio: Audio {}
    // Eager like Notifs, and for the same kind of reason: an idle monitor
    // that is not armed is not an idle monitor. It costs one wayland object
    // and one file watcher.
    property Idle idle: Idle {
        shellRoot: shell
    }
    // Eager, but only as a flag-file watcher: it starts wlsunset when the
    // persisted state says night light was left on, and costs one file watch
    // otherwise.
    property Nightlight nightlight: Nightlight {}
    property Battery batteryService: Battery {}
    // MPRIS media layer (omarchy's media service plugin): sticky preferred
    // player, playing-order ledger, PipeWire stream correlation, source
    // cycling with playback transfer, media OSDs, and the `media` IPC target
    // niri's XF86 keys call. Eager like upstream's keepLoaded service — the
    // keybinds and the bar widget both need it standing; PipeWire is already
    // resident (Audio), so the cost is one MPRIS D-Bus subscription.
    property Media media: Media {
        osd: osd
    }
    // Cross-machine snapshot sync. Inert until shell.json's root `sync` block
    // points it at a shared directory, so it costs one /etc/hostname read
    // until then.
    property Sync sync: Sync {
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
        return writeConfig(copy);
    }

    // Persist a patch onto shell.json's `bar` block — the bar's own gestures
    // write `position` (drag the bar to another screen edge) and `transparent`
    // (double-click the empty center). Same guarantees as updateEntryInline:
    // a config broken on disk is never overwritten, the change lands in memory
    // first, and the file write is atomic.
    function updateBarConfig(patch) {
        if (!configWritable) {
            console.warn("shell.json is broken on disk — refusing to overwrite it with bar settings");
            return false;
        }
        const copy = JSON.parse(JSON.stringify(config));
        if (!copy.bar || typeof copy.bar !== "object")
            copy.bar = {};
        let dirty = false;
        for (const key in patch) {
            if (JSON.stringify(copy.bar[key]) === JSON.stringify(patch[key]))
                continue;
            copy.bar[key] = patch[key];
            dirty = true;
        }
        if (!dirty)
            return false;
        return writeConfig(copy);
    }

    // Move a bar layout entry between (or within) sections and persist —
    // omarchy's moveModuleInConfig, driven by the bar's drag-to-reorder.
    // `beforeId` names the entry the moved one lands in front of; an empty or
    // unknown one appends to the target section.
    function moveBarEntry(fromSection, widgetId, toSection, beforeId) {
        if (!configWritable) {
            console.warn("shell.json is broken on disk — refusing to overwrite it with a bar layout move");
            return false;
        }
        const copy = JSON.parse(JSON.stringify(config));
        if (!copy.bar || typeof copy.bar !== "object")
            return false;
        if (!BarModel.moveEntry(copy.bar, fromSection, widgetId, toSection, beforeId))
            return false;
        return writeConfig(copy);
    }

    // Applied in memory first so the UI reflects the write immediately; the
    // FileView round trip re-delivers the same content.
    function writeConfig(copy) {
        copy.version = 1;
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

    // Open the menu straight at a submenu (or fire a leaf) by id or alias —
    // what the IPC `menu open <route>` does, for callers already inside the
    // shell (the screen-recording indicator opens `capture.screenrecord`).
    function openMenu(route) {
        menuLoader.active = true;
        return menuLoader.item.openRoute(route);
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

    // Returns false when the lock refused to arm (its PAM config is missing) —
    // the loader is dropped again rather than left holding a module that will
    // never lock.
    function lockSession() {
        lockLoader.active = true;
        if (lockLoader.item.lock())
            return true;
        releaseLockIfIdle();
        return false;
    }

    // Draw the lock screen without locking anything. Click or Escape dismisses
    // it, and the module unloads again straight after.
    function previewLock() {
        lockLoader.active = true;
        lockLoader.item.showPreview();
    }

    // The lock unloads itself after unlock (see the Connections below); this is
    // the same release for the paths that wake it without locking — a preview
    // that has been dismissed.
    function releaseLockIfIdle() {
        if (!lockLoader.active)
            return;
        const item = lockLoader.item;
        if (item !== null && (item.locked || item.previewVisible))
            return;
        Qt.callLater(() => lockLoader.active = false);
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
                shell.releaseLockIfIdle();
        }
        function onPreviewVisibleChanged() {
            if (!lockLoader.item.previewVisible)
                shell.releaseLockIfIdle();
        }
    }

    // Popup UI loads on the first notification and stays; window is visible
    // only while toasts exist. The `notifs` IPC target lives with the service
    // itself (Services/Notifs.qml), next to the models it drives.
    Loader {
        active: shell.notifs.everNotified
        sourceComponent: Popups {
            theme: shell.theme
            notifs: shell.notifs
            barPosition: shell.config.bar && shell.config.bar.position ? String(shell.config.bar.position) : "top"
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
            return shell.openMenu(route);
        }
    }

    LazyLoader {
        id: emojisLoader
        active: false
        component: Emojis {
            theme: shell.theme
        }
    }

    // The shell's file chooser. Lazy: nothing exists until something asks for
    // a file — which, thanks to bin/qshell-portal registering it as the
    // xdg-desktop-portal FileChooser backend, is any app on the desktop and
    // not just our own scripts.
    LazyLoader {
        id: filePickerLoader
        active: false
        component: FilePicker {
            theme: shell.theme
        }
    }

    IpcHandler {
        target: "filepicker"

        // Called by bin/qshell-portal with the flattened portal request; the
        // answer goes back over the FIFO named in it, not through this reply.
        function pick(request: string): string {
            filePickerLoader.active = true;
            return filePickerLoader.item.pick(request);
        }

        // The portal withdrew a request (its app went away).
        function cancelToken(token: string): string {
            if (!filePickerLoader.active)
                return "unknown";
            return filePickerLoader.item.cancelToken(token);
        }

        function status(): string {
            if (!filePickerLoader.active)
                return "idle";
            return filePickerLoader.item.opened ? "open:" + filePickerLoader.item.queue.length : "idle";
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
            return shell.lockSession() ? "ok" : "missing-pam";
        }

        function status(): string {
            return lockLoader.active && lockLoader.item.locked ? "locked" : "unlocked";
        }

        function isLocked(): string {
            return shell.locked ? "true" : "false";
        }

        // Everything the lock knows about itself, for diagnosing a lock that
        // did not arm (omarchy's `status`; ours keeps the older string verb).
        function state(): string {
            if (!lockLoader.active)
                return JSON.stringify({
                    loaded: false,
                    locked: false
                });
            const l = lockLoader.item;
            return JSON.stringify({
                loaded: true,
                locked: l.locked,
                requested: l.lockRequested,
                pending: l.pendingSessionLock,
                secure: l.secure,
                realScreens: l.realScreenCount(),
                passwordPam: l.passwordPamConfigured,
                fingerprint: l.fingerprintConfigured,
                authenticating: l.authenticating,
                blanked: l.blanked,
                failedAttempts: l.failedAttempts,
                failureMessage: l.failureMessage,
                background: l.backgroundPath,
                preview: l.previewVisible,
                lastEvent: l.lastEvent,
                lastEventAt: l.lastEventAt
            });
        }

        // Draws the lock screen without locking anything, so the design can be
        // looked at (and a theme judged) without a password between the user
        // and their session. Click or Escape dismisses it.
        function preview(): string {
            shell.previewLock();
            return "ok";
        }

        function hidePreview(): string {
            if (lockLoader.active)
                lockLoader.item.hidePreview();
            return "ok";
        }

        // Undo the lock screen's own 5 s blank. Ours, not omarchy's: on a live
        // session a mouse move does this, but nothing can move the mouse
        // headlessly in the nested dev session.
        function wake(): string {
            if (!lockLoader.active)
                return "idle";
            lockLoader.item.runWake();
            return "ok";
        }

        // Type into the lock's password field from outside it, and submit what
        // is there. Nested dev session ONLY, same gate as devUnlock: this is
        // how the failure path is verified on a box with no key-injection tool
        // — submitting a wrong password still has to go through PAM, so it
        // grants nothing that typing would not.
        function devPassword(text: string): string {
            if (Quickshell.env("QSHELL_DEV") !== "1")
                return "denied";
            if (!lockLoader.active)
                return "idle";
            lockLoader.item.enteredPassword = text;
            return "ok";
        }

        function devSubmit(): string {
            if (Quickshell.env("QSHELL_DEV") !== "1")
                return "denied";
            if (!lockLoader.active)
                return "idle";
            lockLoader.item.submitPassword(lockLoader.item.enteredPassword);
            return "ok";
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

    // The `media` IPC target (niri's XF86 media keys) lives inside
    // Services/Media.qml, beside the player selection it drives.

    IpcHandler {
        target: "shell"

        function ping(): string {
            return "ok";
        }

        function reloadConfig(): string {
            // Re-read shell.json from disk. This must NOT be applyConfig(""):
            // that took the empty-text fallback branch, replacing the live
            // config with the hardcoded fallback AND leaving configWritable
            // true — the next widget-settings write would then have clobbered
            // the user's shell.json with the fallback layout.
            configFile.reload();
            return "ok";
        }
    }
}

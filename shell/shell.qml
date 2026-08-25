import QtQuick
import Quickshell
import Quickshell.Io

import qs.Services
import qs.Modules.Bar
import "Modules/Bar/BarModel.js" as BarModel

// Single long-running ShellRoot. One process: panels are summoned by IPC
// into this instance, never by spawning a second `qs`.
//
// Services are instantiated here once and passed down by property injection.
// Relative-path singleton imports do NOT share state (omarchy) —
// nothing in this tree may `pragma Singleton` a service.
//
// Everything that is not the bar or a service loads through a SurfaceLoader
// below: the module is named only by URL, so its QML tree compiles when the
// surface is first woken instead of before quickshell registers the first
// IpcHandler. Only the Bar (the product's first paint) and the services it
// depends on stay in the synchronous startup path.
ShellRoot {
    id: shell

    property Theme theme: Theme {
        blurActive: shell.blur.enabled
        wallpaperPath: shell.blur.wallpaperPath
    }
    // Eager, but only as a flag-file watcher: with no override and a
    // flat-preset theme the disabled path costs nothing but the watch.
    // Mutual wiring with Theme is deliberate: the theme carries the blur
    // DEFAULT + fragment parameters, the flag file carries the user
    // override, and Theme.blurActive reads back the effective state.
    property Blur blur: Blur {
        theme: shell.theme
    }
    property Niri niri: Niri {}
    // Eager by necessity: must own org.freedesktop.Notifications from startup.
    // The popup UI below stays lazy. `niri` is what click-to-focus resolves a
    // notification's sender against.
    property Notifs notifs: Notifs {
        niri: shell.niri
        shellRoot: shell
    }
    property Audio audio: Audio {}
    // Eager like Notifs, and for the same kind of reason: an idle monitor
    // that is not armed is not an idle monitor. It costs one wayland object
    // and one file watcher.
    property Idle idle: Idle {
        shellRoot: shell
    }
    property Battery batteryService: Battery {}
    // Ambient auto-brightness (MacBook only in practice: it parks itself
    // where there is no ambient-light sensor, which is every other machine
    // here). Eager, but it costs one file read at startup to discover it has
    // no sensor, and its sampler is gated on the screen actually being on.
    property AutoBrightness autoBrightness: AutoBrightness {
        shellRoot: shell
        idle: shell.idle
    }
    // MPRIS media layer (omarchy's media service plugin): sticky preferred
    // player, playing-order ledger, PipeWire stream correlation, source
    // cycling with playback transfer, media OSDs, and the `media` IPC target
    // niri's XF86 keys call. Eager like upstream's keepLoaded service — the
    // keybinds need it standing whether or not anything is playing; PipeWire
    // is already resident (Audio), so the cost is one MPRIS D-Bus
    // subscription. It OUTLIVED the bar's media widget, removed 2026-08-18
    // with the rest of the homegrown music stack: this layer is what the
    // XF86Audio* binds, the track-change OSD and the audio panel's active-
    // stream picker all read, and it does not care whether the player
    // answering is cliamp, a browser tab or mpv.
    // `osd` stays null until the OSD surface resolves (~a beat after start);
    // Media null-guards every use.
    property Media media: Media {
        osd: osdLoader.item
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

    readonly property string barPositionName: config.bar && config.bar.position ? String(config.bar.position) : "top"

    // Surface URLs must be plain file:// — shell.qml itself loads through
    // quickshell's URL interceptor, and a relative source resolved against
    // that scheme breaks implicit same-directory type resolution inside the
    // loaded file (Popups.qml could not see NotificationCard). The warm list
    // below must use the same strings: the engine's compile cache is keyed
    // by URL.
    readonly property string moduleRoot: "file://" + Quickshell.shellDir

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

    // A surface that loads entirely off the startup critical path. `wake()`
    // starts resolving the URL; `summon()` wakes it and calls a method on it
    // now or — the omarchy pendingPayloads pattern (their shell.qml)
    // — queues the call and replays it in arrival order once the
    // tree lands, so IPC that races the load is never dropped. `deliver()`
    // is for hide/cancel verbs: they reach a live or in-flight surface but
    // never wake one that was not summoned.
    component SurfaceLoader: Loader {
        id: sl
        property url surfaceSource
        property var surfaceProps: ({})
        property var pending: []
        // Residency policy: an evictable surface releases its whole tree —
        // and with it its QQuickPixmapCache references — once it has stayed
        // closed for the grace period. The grace window keeps browse flows
        // warm (close → reopen inside it costs nothing); after teardown a
        // summon is a cold instantiation again, which is fine because the
        // engine's compile cache is URL-keyed and survives the instance.
        // Only the heavyweight, rarely-used surfaces opt in — the launcher
        // and the bar panels stay warm for latency.
        //
        // Released is not returned: glibc keeps freed pages unless the
        // MALLOC_*_THRESHOLD_ pins in qshell.service are in effect (measured
        // 2026-08-09: destroying 109 MiB of picker pixmaps returned 0.6 MiB
        // without them). Eviction alone caps growth — the arena is reused on
        // the next summon — but only the malloc tuning makes RSS shrink.
        property bool evictable: false
        // 45 s: comparing themes or walking wallpapers closes and reopens
        // within seconds to tens of seconds — well inside this — while a
        // surface idle for 45 s is a finished session. Also orders of
        // magnitude past any close animation, so teardown never clips one.
        property int graceInterval: 45000
        // Every evictable surface exposes its window state as `open` or
        // `opened`; a surface that is gone counts as closed.
        readonly property bool surfaceOpen: item !== null && (item.open === true || item.opened === true)
        asynchronous: true

        // One-shot, armed only by a close, cancelled by a reopen — it never
        // runs while nothing is loaded and never repeats.
        Timer {
            id: evictTimer
            interval: sl.graceInterval
            repeat: false
            onTriggered: {
                if (!sl.surfaceOpen && sl.item !== null)
                    sl.release();
            }
        }

        onSurfaceOpenChanged: {
            if (!evictable)
                return;
            if (surfaceOpen)
                evictTimer.stop();
            else if (item !== null)
                evictTimer.restart();
        }

        function wake() {
            if (status === Loader.Null || status === Loader.Error)
                setSource(surfaceSource, surfaceProps);
        }

        function summon(method, args) {
            wake();
            if (item !== null)
                item[method].apply(item, args || []);
            else
                pending.push({
                    method: method,
                    args: args || []
                });
        }

        function deliver(method, args) {
            if (item !== null)
                item[method].apply(item, args || []);
            else if (status === Loader.Loading)
                pending.push({
                    method: method,
                    args: args || []
                });
        }

        function release() {
            pending = [];
            setSource("", {});
        }

        onLoaded: {
            const queue = pending;
            pending = [];
            for (let i = 0; i < queue.length; i++) {
                try {
                    item[queue[i].method].apply(item, queue[i].args);
                } catch (e) {
                    console.warn("surface", surfaceSource, "replay of", queue[i].method, "failed:", e);
                }
            }
            // A load that settles CLOSED — a background `notes add`, a
            // queued hide — must still start the eviction clock:
            // surfaceOpen never transitions in that case, so the
            // onSurfaceOpenChanged arming alone would leave the tree
            // resident forever (review 2026-08-13).
            if (evictable && !surfaceOpen)
                evictTimer.restart();
        }

        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("surface failed to load:", surfaceSource);
        }
    }

    // Startup staging: the always-on surfaces resolve asynchronously right
    // after the root lands, in priority order — the clipboard capture watcher
    // first (it must not miss early selections for long), then the wallpaper,
    // OSD and polkit agent. None of them holds back IPC registration.
    // Startup staging. The clipboard capture watcher resolves as soon as the
    // root lands — it must not miss early selections (wl-paste re-fires on
    // watch start, so only a selection made AND replaced inside this first
    // beat could ever slip by). The other always-on surfaces wait one beat
    // more so their incubation doesn't contend with the first IPC answers
    // and the bar's first frames.
    Component.onCompleted: {
        clipboardLoader.wake();
        recoverLockIfStranded();
    }

    // A lock marker left behind by a shell that died while the session was
    // locked (see Modules/Lock/Lock.qml). niri is still holding the session
    // locked for a client that no longer exists, and will hand the lock to
    // this instance instead — but nothing else can, so if this does not run
    // the session cannot be authenticated at all. Deliberately the very first
    // thing after the root lands: every beat before the lock surface maps is
    // a beat of a blanked, unauthenticatable screen.
    function recoverLockIfStranded() {
        const marker = String(lockMarkerFile.text() || "").trim();
        if (!marker)
            return;
        // The marker names the compositor it was written for, so a killed
        // nested dev shell can never make the real session lock itself.
        if (marker !== String(Quickshell.env("WAYLAND_DISPLAY") || ""))
            return;
        console.warn("shell: lock marker found — re-arming the lock the previous instance died holding");
        lockSession();
    }

    // Blocking read (no watcher, no reload): recoverLockIfStranded needs the
    // answer in the same tick the root completes.
    FileView {
        id: lockMarkerFile
        path: Quickshell.env("HOME") + "/.local/state/qshell/locked"
        blockLoading: true
        printErrors: false
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            backgroundLoader.wake();
            osdLoader.wake();
            polkitLoader.wake();
            notesEdgeLoader.wake();
            if (shell.notifs.everNotified)
                popupsLoader.wake();
        }
    }

    // Once startup has settled, pre-compile the surfaces most likely to be
    // summoned so their first open doesn't pay the type compilation that used
    // to happen before the shell was even reachable. Compile only — nothing
    // instantiates, so idle memory stays where it was.
    property var warmedComponents: []
    Timer {
        interval: 3000
        running: true
        onTriggered: shell.warmedComponents = [shell.moduleRoot + "/Modules/Launcher/Launcher.qml", shell.moduleRoot + "/Modules/Menu/Menu.qml", shell.moduleRoot + "/Modules/Lock/Lock.qml", shell.moduleRoot + "/Modules/Notes/Notes.qml"].map(url => Qt.createComponent(url, Component.Asynchronous))
    }

    // An open bar widget panel holds an Exclusive keyboard grab, and niri
    // keeps the grab with the earlier surface — a typeable overlay mapped on
    // top of one would render but never see a key. So every overlay entry
    // point below drops the panels before its window maps.
    function dismissBarPanels() {
        bar.closeAllPanels();
    }

    // Shared entry points for the bar's buttons, the command menu and the IPC
    // targets. Each one wakes its surface on first use.
    function toggleLauncher() {
        dismissBarPanels();
        launcherLoader.summon("toggle");
    }

    function toggleMenu() {
        dismissBarPanels();
        menuLoader.summon("toggle");
    }

    // Open the menu straight at a submenu (or fire a leaf) by id or alias —
    // what the IPC `menu open <route>` does, for callers already inside the
    // shell (the screen-recording indicator opens `capture.screenrecord`).
    // While the menu is still resolving the route is queued and this reports
    // "ok" — the route outcome lands when the tree does.
    function openMenu(route) {
        dismissBarPanels();
        if (menuLoader.item !== null)
            return menuLoader.item.openRoute(route);
        menuLoader.summon("openRoute", [route]);
        return "ok";
    }

    // The notification history center lives in the bar (a bell indicator's
    // BarPanel), so these route through it; the `notifs` IPC verbs call them
    // via the service's injected shellRoot.
    function toggleNotifCenter() {
        if (bar.closeNotifCenter())
            return "closed";
        return bar.summonNotifCenter() ? "ok" : "none";
    }

    function showNotifCenter() {
        if (bar.notifCenterOpen())
            return "ok";
        return bar.summonNotifCenter() ? "ok" : "none";
    }

    function hideNotifCenter() {
        return bar.closeNotifCenter() ? "ok" : "none";
    }

    function toggleThemes() {
        dismissBarPanels();
        themesLoader.summon("toggle");
    }

    function toggleWallpaper() {
        dismissBarPanels();
        wallpaperLoader.summon("toggle");
    }

    function toggleWallhaven() {
        dismissBarPanels();
        wallhavenLoader.summon("toggle");
    }

    function toggleEmojis() {
        dismissBarPanels();
        emojisLoader.summon("toggle");
    }

    function toggleClipboard() {
        dismissBarPanels();
        clipboardLoader.summon("toggle");
    }

    function toggleReminders() {
        dismissBarPanels();
        remindersLoader.summon("toggle");
    }

    function toggleNotes() {
        dismissBarPanels();
        notesLoader.summon("toggle");
    }

    function toggleDekho() {
        dismissBarPanels();
        dekhoLoader.summon("toggle");
    }

    // What the hot-edge strip calls on a right-edge hover. The strip stays
    // reachable past the card's 10 px niri gap while the panel is open, so the
    // same gesture that summoned it dismisses it: move away from the edge and
    // back. The dwell timer behind this is what keeps a fling that merely
    // grazes the strip from closing a panel mid-read.
    function toggleNotesFromEdge() {
        dismissBarPanels();
        notesLoader.summon("toggle");
    }

    // Show, never toggle: a drag arriving at the edge must open the panel to
    // be dropped on, and a drag that grazes the strip with the panel already
    // open must not pull it out from under the drop.
    function summonNotes() {
        dismissBarPanels();
        notesLoader.summon("show");
    }

    // A drop released on the hot strip itself (instead of on the panel it
    // just summoned) stages like a drop on the panel would: first file into
    // the capture input, extras committed directly, text into the input.
    function notesDropPayload(urls, text) {
        dismissBarPanels();
        if (urls.length > 0) {
            notesLoader.summon("stageAttachmentUrl", [urls[0]]);
            for (let i = 1; i < urls.length; i++)
                notesLoader.summon("addFileUrl", [urls[i]]);
        } else if (text) {
            notesLoader.summon("stageText", [text]);
        }
        notesLoader.summon("show");
    }

    // Returns false when the lock refused to arm (its PAM config is missing) —
    // the loader is dropped again rather than left holding a module that will
    // never lock. The lock loader is synchronous: lockSession() must answer
    // truthfully, so it blocks for the (first-use-only) load.
    function lockSession() {
        lockLoader.wake();
        if (lockLoader.item.lock())
            return true;
        releaseLockIfIdle();
        return false;
    }

    // Draw the lock screen without locking anything. Click or Escape dismisses
    // it, and the module unloads again straight after.
    function previewLock() {
        dismissBarPanels();
        lockLoader.wake();
        lockLoader.item.showPreview();
    }

    // The lock unloads itself after unlock (see the Connections below); this is
    // the same release for the paths that wake it without locking — a preview
    // that has been dismissed.
    function releaseLockIfIdle() {
        const item = lockLoader.item;
        if (item === null)
            return;
        if (item.locked || item.previewVisible)
            return;
        Qt.callLater(() => lockLoader.release());
    }

    // For anything that must not re-lock an already locked session (the idle
    // service's lock stage).
    readonly property bool locked: lockLoader.item !== null && lockLoader.item.locked

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

    SurfaceLoader {
        id: backgroundLoader
        surfaceSource: shell.moduleRoot + "/Modules/Background/Background.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    Bar {
        id: bar
        shell: shell
        theme: shell.theme
        niri: shell.niri
        config: shell.config.bar && typeof shell.config.bar === "object" ? shell.config.bar : shell.fallbackConfig.bar
    }

    // Lock is the only module allowed to stay loaded while active — it
    // releases itself after unlock. Synchronous (see lockSession); still off
    // the startup path because nothing wakes it until a lock.
    SurfaceLoader {
        id: lockLoader
        asynchronous: false
        surfaceSource: shell.moduleRoot + "/Modules/Lock/Lock.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    Connections {
        target: lockLoader.item
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
    SurfaceLoader {
        id: popupsLoader
        surfaceSource: shell.moduleRoot + "/Modules/Notifications/Popups.qml"
        surfaceProps: ({
                theme: shell.theme,
                notifs: shell.notifs,
                barPosition: shell.barPositionName
            })
    }

    Connections {
        target: shell.notifs
        function onEverNotifiedChanged() {
            popupsLoader.wake();
        }
    }

    // setSource props are set-once; the bar can move edges at runtime, so the
    // popup surface's copy is kept live by this binding.
    Binding {
        target: popupsLoader.item
        property: "barPosition"
        value: shell.barPositionName
        when: popupsLoader.item !== null
    }

    SurfaceLoader {
        id: osdLoader
        surfaceSource: shell.moduleRoot + "/Modules/Osd/Osd.qml"
        surfaceProps: ({
                theme: shell.theme,
                audio: shell.audio
            })
    }

    SurfaceLoader {
        id: polkitLoader
        surfaceSource: shell.moduleRoot + "/Modules/Polkit/Polkit.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "polkit"

        function status(): string {
            const p = polkitLoader.item;
            return JSON.stringify({
                registered: p !== null && p.agent.isRegistered,
                active: p !== null && p.active
            });
        }

        function cancel(): string {
            polkitLoader.deliver("cancel");
            return "ok";
        }
    }

    SurfaceLoader {
        id: launcherLoader
        surfaceSource: shell.moduleRoot + "/Modules/Launcher/Launcher.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "launcher"

        function toggle(): string {
            shell.toggleLauncher();
            return "ok";
        }

        function show(): string {
            shell.dismissBarPanels();
            launcherLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            launcherLoader.deliver("hide");
            return "ok";
        }
    }

    SurfaceLoader {
        id: menuLoader
        evictable: true
        surfaceSource: shell.moduleRoot + "/Modules/Menu/Menu.qml"
        surfaceProps: ({
                theme: shell.theme,
                shellRoot: shell
            })
    }

    IpcHandler {
        target: "menu"

        function toggle(): string {
            shell.toggleMenu();
            return "ok";
        }

        function show(): string {
            shell.dismissBarPanels();
            menuLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            menuLoader.deliver("hide");
            return "ok";
        }

        // Jump straight to a submenu (or fire a leaf) by id or alias:
        // `qs ipc call menu open system`, `… open screenshot`.
        function open(route: string): string {
            return shell.openMenu(route);
        }

        // Generic picker/prompt for scripts (omarchy's dmenu modes; built by
        // bin/menu-select and bin/menu-input): payload JSON carries
        // mode/prompt/options/selectionFile/doneFile, the caller polls for
        // the done file.
        function prompt(payload: string): string {
            shell.dismissBarPanels();
            menuLoader.summon("promptOpen", [payload]);
            return "ok";
        }
    }

    SurfaceLoader {
        id: emojisLoader
        evictable: true
        surfaceSource: shell.moduleRoot + "/Modules/Emojis/Emojis.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    // The shell's file chooser. Lazy: nothing exists until something asks for
    // a file — which, thanks to bin/qshell-portal registering it as the
    // xdg-desktop-portal FileChooser backend, is any app on the desktop and
    // not just our own scripts. Synchronous: pick() answers the portal with
    // the real result of queueing the request.
    SurfaceLoader {
        id: filePickerLoader
        asynchronous: false
        surfaceSource: shell.moduleRoot + "/Modules/FilePicker/FilePicker.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "filepicker"

        // Called by bin/qshell-portal with the flattened portal request; the
        // answer goes back over the FIFO named in it, not through this reply.
        function pick(request: string): string {
            shell.dismissBarPanels();
            filePickerLoader.wake();
            return filePickerLoader.item.pick(request);
        }

        // The portal withdrew a request (its app went away).
        function cancelToken(token: string): string {
            if (filePickerLoader.item === null)
                return "unknown";
            return filePickerLoader.item.cancelToken(token);
        }

        function status(): string {
            if (filePickerLoader.item === null)
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
            shell.dismissBarPanels();
            emojisLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            emojisLoader.deliver("hide");
            return "ok";
        }
    }

    // The capture watcher must be running before anything is copied, or there
    // is no history to pick from — so this surface wakes first in the startup
    // staging above; the async load defers its wl-paste spawn by a beat, no
    // more. Its picker window stays lazy inside the module.
    SurfaceLoader {
        id: clipboardLoader
        surfaceSource: shell.moduleRoot + "/Modules/Clipboard/Clipboard.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): string {
            shell.toggleClipboard();
            return "ok";
        }

        function show(): string {
            shell.dismissBarPanels();
            clipboardLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            clipboardLoader.deliver("hide");
            return "ok";
        }
    }

    SurfaceLoader {
        id: remindersLoader
        surfaceSource: shell.moduleRoot + "/Modules/Reminders/ReminderFlow.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "reminders"

        function toggle(): string {
            shell.toggleReminders();
            return "ok";
        }

        function show(): string {
            shell.dismissBarPanels();
            remindersLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            remindersLoader.deliver("hide");
            return "ok";
        }
    }

    // Quick-capture notes (our Copper): a full-height panel over the right
    // sixth of the screen, summoned by the hot-edge strip below, the `notes`
    // IPC, or nothing at all — evictable, so between uses it costs zero. The
    // strip is the only always-on part, staged with the other 400 ms wakes.
    SurfaceLoader {
        id: notesLoader
        evictable: true
        surfaceSource: shell.moduleRoot + "/Modules/Notes/Notes.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    SurfaceLoader {
        id: notesEdgeLoader
        surfaceSource: shell.moduleRoot + "/Modules/Notes/NotesEdge.qml"
        surfaceProps: ({
                shellRoot: shell
            })
    }

    IpcHandler {
        target: "notes"

        function toggle(): string {
            shell.toggleNotes();
            return "ok";
        }

        function show(): string {
            shell.summonNotes();
            return "ok";
        }

        function hide(): string {
            notesLoader.deliver("hide");
            return "ok";
        }

        // Append without opening the panel: `qs ipc call notes add "text"` —
        // for scripts and keybinds that capture without stealing the screen.
        function add(text: string): string {
            notesLoader.summon("addText", [text]);
            return "ok";
        }
    }

    // The movie hub (github.com/saifulapm/dekho): browse, resume and play into
    // mpv. Evictable for the same reason the filmstrip pickers are — a hub
    // holds sixty decoded posters while it is open and nothing at all when it
    // is not. It re-fetches on every summon rather than caching in this
    // process; the poster files are already on disk in dekho's own cache, so a
    // reopen paints from disk and the TMDB calls only refresh what is on
    // screen. Playback itself is NOT a child of this process — see the module
    // header and bin/dekho-play.
    //
    // THE ONLY SURFACE HERE THAT IS A REAL WINDOW rather than a layer-shell
    // one (2026-08-20), so that the mpv it starts is drawn above it instead of
    // behind it. That does not change this loader's contract: the module's
    // `opened` is its window's own visibility, so a close from the compositor
    // (Mod+Q) satisfies `surfaceOpen`'s "closed" exactly as its own hide()
    // does and the grace timer starts either way. `toggle` is no longer a
    // two-state verb — a window can be open and not in front of you — see the
    // module's toggle().
    SurfaceLoader {
        id: dekhoLoader
        evictable: true
        surfaceSource: shell.moduleRoot + "/Modules/Dekho/Dekho.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "dekho"

        function toggle(): string {
            shell.toggleDekho();
            return "ok";
        }

        function show(): string {
            shell.dismissBarPanels();
            dekhoLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            dekhoLoader.deliver("hide");
            return "ok";
        }

        // `qs ipc call dekho search "the wire"` — open straight onto a query,
        // for a keybind or a script that already knows what you want.
        function search(query: string): string {
            shell.dismissBarPanels();
            dekhoLoader.summon("searchFor", [query]);
            return "ok";
        }
    }

    // The disk speed test, reached from the menu (System > Disk Speed Test).
    // Evictable: a run is a deliberate, occasional errand, and between them
    // the surface is dead weight. show() starts a measurement, so `hide` uses
    // deliver — it must never wake the surface just to stop nothing.
    SurfaceLoader {
        id: diskSpeedTestLoader
        evictable: true
        surfaceSource: shell.moduleRoot + "/Modules/DiskSpeedTest/DiskSpeedTest.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "diskspeedtest"

        function show(): string {
            shell.dismissBarPanels();
            diskSpeedTestLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            diskSpeedTestLoader.deliver("hide");
            return "ok";
        }
    }

    // The two filmstrip pickers are the heaviest surfaces in the shell —
    // a browse latches ~30 MiB of 768 px tile decodes (bin/wallpaper-thumbs
    // keeps that from being ~110 MiB of raw 4K decode) — and the
    // rarest-used, so both evict after the grace period.
    SurfaceLoader {
        id: themesLoader
        evictable: true
        surfaceSource: shell.moduleRoot + "/Modules/ThemeSwitcher/ThemeSwitcher.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "theme"

        function toggle(): string {
            shell.toggleThemes();
            return "ok";
        }

        function show(): string {
            shell.dismissBarPanels();
            themesLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            themesLoader.deliver("hide");
            return "ok";
        }
    }

    SurfaceLoader {
        id: wallpaperLoader
        evictable: true
        surfaceSource: shell.moduleRoot + "/Modules/Background/ImagePicker.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): string {
            shell.toggleWallpaper();
            return "ok";
        }

        function show(): string {
            shell.dismissBarPanels();
            wallpaperLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            wallpaperLoader.deliver("hide");
            return "ok";
        }
    }

    SurfaceLoader {
        id: wallhavenLoader
        evictable: true
        surfaceSource: shell.moduleRoot + "/Modules/Background/WallhavenPicker.qml"
        surfaceProps: ({
                theme: shell.theme
            })
    }

    IpcHandler {
        target: "wallhaven"

        function toggle(): string {
            shell.toggleWallhaven();
            return "ok";
        }

        function show(): string {
            shell.dismissBarPanels();
            wallhavenLoader.summon("show");
            return "ok";
        }

        function hide(): string {
            wallhavenLoader.deliver("hide");
            return "ok";
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): string {
            return shell.lockSession() ? "ok" : "missing-pam";
        }

        function status(): string {
            return shell.locked ? "locked" : "unlocked";
        }

        function isLocked(): string {
            return shell.locked ? "true" : "false";
        }

        // Everything the lock knows about itself, for diagnosing a lock that
        // did not arm (omarchy's `status`; ours keeps the older string verb).
        function state(): string {
            if (lockLoader.item === null)
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
            if (lockLoader.item !== null)
                lockLoader.item.hidePreview();
            return "ok";
        }

        // Undo the lock screen's own 5 s blank. Ours, not omarchy's: on a live
        // session a mouse move does this, but nothing can move the mouse
        // headlessly in the nested dev session.
        function wake(): string {
            if (lockLoader.item === null)
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
            if (lockLoader.item === null)
                return "idle";
            lockLoader.item.enteredPassword = text;
            return "ok";
        }

        function devSubmit(): string {
            if (Quickshell.env("QSHELL_DEV") !== "1")
                return "denied";
            if (lockLoader.item === null)
                return "idle";
            lockLoader.item.submitPassword(lockLoader.item.enteredPassword);
            return "ok";
        }

        // Escape hatch for the nested dev session ONLY. In a production session
        // (no QSHELL_DEV) unlocking requires PAM, full stop.
        function devUnlock(): string {
            if (Quickshell.env("QSHELL_DEV") !== "1")
                return "denied";
            if (lockLoader.item !== null)
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

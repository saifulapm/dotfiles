import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "services" as Services
import "lib/status.mjs" as Status

ShellRoot {
    id: root

    // Process start to the first paper frame; set once, by the first paper to swap.
    property var firstFrameMs: null
    // A hot reload rebuilds this tree in the old process, so its first frame is timed from here instead.
    readonly property real builtAt: Date.now()
    property bool reloaded: false

    // qs emits this only after a hot reload, before the new tree draws its first frame.
    Connections {
        target: Quickshell
        function onReloadCompleted() {
            root.reloaded = true;
        }
    }

    Services.Theme {
        id: themeService
    }

    Variants {
        model: Quickshell.screens

        Root.Paper {
            required property var modelData
            screen: modelData
            theme: themeService
            onFirstFrame: {
                if (root.firstFrameMs !== null)
                    return;
                if (root.reloaded) {
                    root.firstFrameMs = Date.now() - root.builtAt;
                    return;
                }
                uptime.reload();
                root.firstFrameMs = Status.processAgeMs(uptime.text(), selfStat.text());
            }
        }
    }

    // blockAllReads, so text() after reload() is the uptime of that moment, not the last one.
    FileView {
        id: uptime
        path: "/proc/uptime"
        blockAllReads: true
    }

    FileView {
        id: selfStat
        path: "/proc/self/stat"
        blockLoading: true
    }

    // Read at call time; blockAllReads, or text() after reload() is the previous call's RSS.
    FileView {
        id: procStatus
        path: "/proc/self/status"
        blockAllReads: true
    }

    IpcHandler {
        target: "shell"

        function status(): string {
            procStatus.reload();
            return Status.statusJson({
                theme: themeService.name,
                outputs: Quickshell.screens.map(s => s.name),
                loaded: Root.State.loaded,
                sync: deskLoader.item ? deskLoader.item.sync.units : {},
                rssKiB: Status.rssKiB(procStatus.text()),
                timers: Root.State.timers(),
                firstFrameMs: root.firstFrameMs
            });
        }
    }

    // The notification server starts with the shell, since a notification sent before it registers is lost.
    Services.Notifs {
        id: notifsService
    }

    // Everything else but the paper loads after its first frame, so the services and the island never hold that frame back.
    LazyLoader {
        id: deskLoader
        active: root.firstFrameMs !== null

        Root.Desk {
            theme: themeService
            notifs: notifsService
        }
    }

    IpcHandler {
        target: "notifs"

        function dnd(on: bool): void {
            notifsService.setDnd(on);
        }

        // t0 is taken before the first load, so a cold open's time includes loading.
        function open(): void {
            const t0 = Date.now();
            surfacesLoader.active = true;
            surfacesLoader.item.openNotifs(t0);
        }

        function close(): void {
            surfacesLoader.item?.notifications?.close();
        }

        function toggle(): void {
            if (surfacesLoader.item?.notifications?.shown)
                close();
            else
                open();
        }

        function state(): string {
            const h = notifsService.history;
            const centre = surfacesLoader.item?.notifications?.state() ?? { open: false, query: "", selected: 0, groups: [], hint: false, openMs: null, opens: 0 };
            return JSON.stringify(Object.assign(centre, { dnd: notifsService.dnd, count: h.length, summaries: h.map(e => e.summary) }));
        }
    }


    // The desktop entry scan starts with the shell, so the launcher's first open does not wait on it.
    readonly property int appCount: DesktopEntries.applications.values.length

    IpcHandler {
        target: "launcher"

        // t0 is taken before the first load, so a cold open's time includes loading.
        function open(): void {
            const t0 = Date.now();
            surfacesLoader.active = true;
            surfacesLoader.item.openLauncher(t0);
        }

        function close(): void {
            surfacesLoader.item?.launcher?.close();
        }

        function toggle(): void {
            if (surfacesLoader.item?.launcher?.shown)
                close();
            else
                open();
        }

        // Opens straight into a mode, like clipboard for Mod+V or emoji for Mod+.
        function mode(name: string): void {
            const t0 = Date.now();
            surfacesLoader.active = true;
            surfacesLoader.item.openLauncher(t0, name);
        }

        function state(): string {
            if (surfacesLoader.item?.launcher)
                return surfacesLoader.item.launcher.state();
            return JSON.stringify({ open: false, mode: "apps", query: "", results: [], selected: 0, openMs: null, opens: 0 });
        }
    }

    // The theme list is read with the shell, so the switcher's first open does not wait on it.
    property var themeList: []

    FileView {
        path: themeService.dir + "/theme-out/themes.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.themeList = JSON.parse(text());
            } catch (e) {
                console.warn("themes: keeping the last good list: " + e.message);
            }
        }
    }

    LazyLoader {
        id: surfacesLoader

        Root.Surfaces {
            theme: themeService
            themeList: root.themeList
            notifs: notifsService
            goals: deskLoader.item ? deskLoader.item.goals : null
            sync: deskLoader.item ? deskLoader.item.sync : null
        }
    }

    IpcHandler {
        target: "goals"

        // The store lives in the Desk, so Goals opens only once the Desk has loaded.
        function open(): void {
            const t0 = Date.now();
            if (!deskLoader.item)
                return;
            surfacesLoader.active = true;
            surfacesLoader.item.openGoals(t0);
        }

        function close(): void {
            surfacesLoader.item?.goalsView?.close();
        }

        function toggle(): void {
            if (surfacesLoader.item?.goalsView?.shown)
                close();
            else
                open();
        }

        function state(): string {
            if (surfacesLoader.item?.goalsView)
                return surfacesLoader.item.goalsView.state();
            return JSON.stringify({ open: false, selected: 0, rows: [], active: [], done: [], count: 0, hint: "", prompt: null, confirm: false, openMs: null, opens: 0 });
        }
    }

    IpcHandler {
        target: "themes"

        // t0 is taken before the first load, so a cold open's time includes loading.
        function open(): void {
            const t0 = Date.now();
            surfacesLoader.active = true;
            surfacesLoader.item.openThemes(t0);
        }

        function close(): void {
            surfacesLoader.item?.themes?.close();
        }

        function toggle(): void {
            if (surfacesLoader.item?.themes?.shown)
                close();
            else
                open();
        }

        function state(): string {
            if (surfacesLoader.item?.themes)
                return surfacesLoader.item.themes.state();
            return JSON.stringify({ open: false, themes: root.themeList.map(t => t.name), selected: themeService.name, current: themeService.name, openMs: null, opens: 0 });
        }
    }

    IpcHandler {
        target: "cheatsheet"

        // t0 is taken before the first load, so a cold open's time includes loading.
        function open(): void {
            const t0 = Date.now();
            surfacesLoader.active = true;
            surfacesLoader.item.openCheatsheet(t0);
        }

        function close(): void {
            surfacesLoader.item?.cheatsheet?.close();
        }

        function toggle(): void {
            if (surfacesLoader.item?.cheatsheet?.shown)
                close();
            else
                open();
        }

        function state(): string {
            if (surfacesLoader.item?.cheatsheet)
                return surfacesLoader.item.cheatsheet.state();
            return JSON.stringify({ open: false, rows: 0, groups: [], query: "", openMs: null, opens: 0 });
        }
    }

    IpcHandler {
        target: "control"

        // t0 is taken before the first load, so a cold open's time includes loading.
        function open(): void {
            const t0 = Date.now();
            surfacesLoader.active = true;
            surfacesLoader.item.openControl(t0);
        }

        function close(): void {
            surfacesLoader.item?.control?.close();
        }

        function toggle(): void {
            if (surfacesLoader.item?.control?.shown)
                close();
            else
                open();
        }

        function state(): string {
            if (surfacesLoader.item?.control)
                return surfacesLoader.item.control.state();
            return JSON.stringify({ open: false, openMs: null, opens: 0 });
        }
    }

    IpcHandler {
        target: "record"

        // Opens the picker, or stops a recording that is running.
        function toggle(): void {
            surfacesLoader.active = true;
            surfacesLoader.item.toggleRecorder();
        }

        function state(): string {
            if (surfacesLoader.item?.recorder)
                return surfacesLoader.item.recorder.state();
            return JSON.stringify({ picking: false, recording: false });
        }
    }

    Root.Lock {
        id: lockScope
        theme: themeService
    }

    Root.Polkit {
        surfaces: surfacesLoader
    }

    Root.Idle {
        lock: lockScope
        surfaces: surfacesLoader
    }
}

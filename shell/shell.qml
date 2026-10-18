import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "services" as Services
import "lib/status.mjs" as Status
import "lib/margins.mjs" as MarginsLib

ShellRoot {
    id: root

    // Process start to the first paper frame; set once, by the first paper to swap.
    property var firstFrameMs: null

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
                sync: {},
                rssKiB: Status.rssKiB(procStatus.text()),
                timers: Root.State.timers(),
                firstFrameMs: root.firstFrameMs
            });
        }
    }

    Services.Niri {
        id: niriService
    }

    Services.Clock {
        id: clockService
    }

    Services.Notifs {
        id: notifsService
    }

    IpcHandler {
        target: "notifs"

        function dnd(on: bool): void {
            notifsService.setDnd(on);
        }

        function state(): string {
            const h = notifsService.history;
            return JSON.stringify({ dnd: notifsService.dnd, count: h.length, summaries: h.map(e => e.summary) });
        }
    }

    Services.Questions {
        id: questionsService
    }

    Root.Island {
        id: island
        theme: themeService
        niri: niriService
        clock: clockService
        notifs: notifsService
        questions: questionsService
    }

    Variants {
        model: Quickshell.screens

        Root.Margins {
            required property var modelData
            screen: modelData
            theme: themeService
            niri: niriService
            clock: clockService
            islandWidth: island.boxWidth
        }
    }

    IpcHandler {
        target: "margins"

        // The margins of the output with the focused workspace.
        function state(): string {
            const view = niriService.view(niriService.focusedOutput) ?? { idx: 0, app: null, title: null };
            return JSON.stringify(MarginsLib.marginState(view, clockService.now));
        }
    }

    IpcHandler {
        target: "island"

        function state(): string {
            const calendar = island.mode === "calendar" ? { title: island.grid.title, today: island.today || null, weeks: island.grid.weeks } : null;
            return JSON.stringify({ mode: island.mode, text: island.text, width: island.boxWidth, since: island.modeSince, focused: island.focused, calendar });
        }

        function focus(): void {
            island.focusIsland();
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
}

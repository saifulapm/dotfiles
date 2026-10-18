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

    Root.Island {
        id: island
        theme: themeService
        niri: niriService
        clock: clockService
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
            return JSON.stringify({ mode: "rest", text: island.text });
        }
    }

    LazyLoader {
        id: launcherLoader

        Root.Launcher {
            theme: themeService
        }
    }

    IpcHandler {
        target: "launcher"

        // t0 is taken before the first load, so a cold open's time includes loading.
        function open(): void {
            const t0 = Date.now();
            launcherLoader.active = true;
            launcherLoader.item.open(t0);
        }

        function close(): void {
            if (launcherLoader.item)
                launcherLoader.item.close();
        }

        function toggle(): void {
            if (launcherLoader.item?.shown)
                close();
            else
                open();
        }

        function state(): string {
            if (launcherLoader.item)
                return launcherLoader.item.state();
            return JSON.stringify({ open: false, mode: "apps", query: "", results: [], selected: 0, openMs: null, opens: 0 });
        }
    }
}

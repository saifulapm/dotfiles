import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "services" as Services
import "lib/margins.mjs" as MarginsLib

// The island, the margins and the services behind them; shell.qml loads this after the paper's first frame.
Scope {
    id: desk

    required property var theme
    required property var notifs

    Services.Niri {
        id: niriService
    }

    Services.Clock {
        id: clockService
    }

    Services.Power {
        id: powerService
    }

    Services.Network {
        id: networkService
    }

    Services.Osd {
        id: osdService
    }

    IpcHandler {
        target: "osd"

        // The brightness keys call this; the step is like 5%+ or 5%-.
        function brightness(step: string): void {
            osdService.brightness(step);
        }
    }

    Services.Questions {
        id: questionsService
    }

    Services.Media {
        id: mediaService
    }

    Services.Notes {
        id: notesService
        onToast: text => island.showToast(text)
    }

    IpcHandler {
        target: "notes"

        // The double-Shift watcher calls this; it never opens Notes or touches the clipboard.
        function capture(): void {
            notesService.capture();
        }

        function toggle(): void {
            notesLoader.active = true;
            notesLoader.item.toggle();
        }

        function pin(): void {
            notesLoader.active = true;
            notesLoader.item.pin();
        }

        function state(): string {
            const s = notesService.store;
            const view = notesLoader.item?.state() ?? { open: false, focused: false, pinned: false };
            return JSON.stringify(Object.assign(view, { path: notesService.path, activeSection: s.activeSection, sections: s.sections.map(x => x.name), count: s.notes.filter(n => !n.deleted).length, notes: s.notes }));
        }
    }

    // The window loads on the first Mod+N, so the shell's start and idle memory never pay for it.
    LazyLoader {
        id: notesLoader

        Root.Notes {
            theme: desk.theme
            notes: notesService
            niri: niriService
        }
    }

    Root.Island {
        id: island
        theme: desk.theme
        niri: niriService
        clock: clockService
        notifs: desk.notifs
        questions: questionsService
        osd: osdService.current
        playing: mediaService.playing
    }

    Variants {
        model: Quickshell.screens

        Root.Margins {
            required property var modelData
            screen: modelData
            theme: desk.theme
            niri: niriService
            clock: clockService
            power: powerService
            network: networkService
            islandWidth: island.boxWidth
        }
    }

    IpcHandler {
        target: "margins"

        // The margins of the output with the focused workspace.
        function state(): string {
            const view = niriService.view(niriService.focusedOutput) ?? { idx: 0, app: null, title: null };
            return JSON.stringify(MarginsLib.marginState(view, clockService.now, { wifi: networkService.wifi, battery: powerService.battery }));
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
}

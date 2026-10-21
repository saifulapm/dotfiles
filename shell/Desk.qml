import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "services" as Services
import "lib/margins.mjs" as MarginsLib
import "lib/goals.mjs" as GoalsLib

// The island, the margins and the services behind them; shell.qml loads this after the paper's first frame.
Scope {
    id: desk

    required property var theme
    required property var notifs
    // The session lock, whose agent lease the island shows.
    required property var lock
    // The Goals window reaches the store through this.
    readonly property alias goals: goalsService
    // Control's Route section and the shell's status read the last sync round through this.
    readonly property alias sync: syncService
    // The launcher's r mode sets and deletes through this.
    readonly property alias reminders: remindersService

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

    Root.Ipc {
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

    Services.Goals {
        id: goalsService
        onToast: text => island.showToast(text)
    }

    Services.Sync {
        id: syncService
    }

    Services.Reminders {
        id: remindersService
        now: clockService.now
    }

    Root.Ipc {
        target: "notes"

        // The double-Shift watcher calls this; it never opens Notes or touches the clipboard.
        function capture(): void {
            notesService.capture();
        }

        function open(): void {
            notesLoader.active = true;
            if (!notesLoader.item.shown)
                notesLoader.item.show();
        }

        function toggle(): void {
            notesLoader.active = true;
            notesLoader.item.toggle();
        }

        function pin(): void {
            notesLoader.active = true;
            notesLoader.item.pin();
        }

        // Mod+S.
        function shelf(): void {
            notesLoader.active = true;
            notesLoader.item.shelf();
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
        lock: desk.lock
        osd: osdService.current
        playing: mediaService.playing
    }

    Variants {
        id: marginsVariants
        model: Quickshell.screens

        Root.Margins {
            required property var modelData
            screen: modelData
            theme: desk.theme
            niri: niriService
            clock: clockService
            power: powerService
            network: networkService
            goals: goalsService
            sync: syncService
            islandWidth: island.boxWidth
        }
    }

    Root.Ipc {
        target: "margins"

        // The margins of the output with the focused workspace.
        function state(): string {
            const view = niriService.view(niriService.focusedOutput) ?? { idx: 0, app: null, title: null };
            const shown = marginsVariants.instances.find(m => m.screen.name === niriService.focusedOutput);
            return JSON.stringify(Object.assign(MarginsLib.marginState(view, clockService.now, { sync: syncService.failing ? "sync !" : "", goal: GoalsLib.marginGoal(goalsService.store, clockService.now), wifi: networkService.wifi, battery: powerService.battery }), { drawn: shown ? shown.drawnState() : null }));
        }
    }

    Root.Ipc {
        target: "island"

        function state(): string {
            const calendar = island.mode === "calendar" ? { title: island.grid.title, today: island.today || null, weeks: island.grid.weeks } : null;
            return JSON.stringify({ mode: island.mode, text: island.text, width: island.boxWidth, height: island.targetHeight, since: island.modeSince, focused: island.focused, animating: island.animating, drawn: island.drawnWidth, calendar, note: island.noteState(), osd: island.osdState(), warning: island.leaseWarning, lease: island.leaseState(), sending: island.sendingState(), swatch: island.swatchState() });
        }

        function focus(): void {
            island.focusIsland();
        }

        // dots-capture's pill: its text, and a #RRGGBB swatch or "" for none.
        function capture(text: string, hex: string): void {
            island.showCapture(text, hex);
        }
    }

    // dots-taildrop-send reports a send here: start, the whole send's percent, then done.
    Root.Ipc {
        target: "sending"

        function start(count: string, to: string): void {
            island.sendStart(count, to);
        }

        function progress(pct: string): void {
            island.sendProgress(pct);
        }

        function done(): void {
            island.sendDone();
        }
    }
}

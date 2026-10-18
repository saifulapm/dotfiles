import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "services" as Services
import "lib/status.mjs" as Status

ShellRoot {
    Services.Theme {
        id: themeService
    }

    Variants {
        model: Quickshell.screens

        Root.Paper {
            required property var modelData
            screen: modelData
            theme: themeService
        }
    }

    // Read at call time, so status reports the RSS of that moment.
    FileView {
        id: procStatus
        path: "/proc/self/status"
        blockLoading: true
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
                timers: Root.State.timers
            });
        }
    }
}

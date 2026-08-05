import QtQuick
import Quickshell
import Quickshell.Io
import "../components"

// Screen recording, ported from omarchy's ScreenRecording indicator
// (CREDITS.md): their glyph 󰻂, their two tooltip strings, their click rule
// (recording → stop, idle → open the capture menu's Screenrecord submenu), and
// their state contract — the indicator is active exactly while a recorder
// process is alive.
//
// One deviation, in the refresh path. Theirs re-runs `pgrep` on
// Component.onCompleted and again on every `refreshRequested` broadcast the
// container relays, and `bin/omarchy-capture-screenrecording` fires that
// broadcast over IPC after each start and stop. Ours reads the state file
// `bin/screenrecord` writes instead: a FileView on it means the file appearing
// or disappearing IS the event, so there is no broadcast to relay and nothing
// polls. That also covers the case their poke cannot — a recorder that dies on
// its own, since the script's supervisor clears the file when wf-recorder
// exits for any reason.
//
// The pgrep check is still theirs and still runs: `screenrecord status --json`
// reconciles the file against the live process on every read (including the
// one at Component.onCompleted), so a state file left behind by a SIGKILL is
// dropped rather than lighting the bar forever.
BarIndicator {
    id: rootItem

    required property var shell

    property bool recording: false
    // The recording's path, shown as the tooltip's second half while active.
    property string outputFile: ""

    readonly property string binPath: Quickshell.env("HOME") + "/.dotfiles/bin/screenrecord"

    active: recording
    activeGlyph: "󰻂" // md-record_circle
    inactiveGlyph: "󰻂"
    activeTooltip: "Stop recording"
    inactiveTooltip: "Screen Recording"

    function refresh() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function update(raw) {
        let data = ({});
        try {
            data = JSON.parse(String(raw || "{}"));
        } catch (e) {
            data = ({});
        }
        recording = data.recording === true;
        outputFile = String(data.file || "");
    }

    // Upstream's click rule exactly: stop while recording, otherwise hand over
    // to the menu — theirs shells out to `omarchy-menu toggle
    // trigger.capture.screenrecord`, ours opens the same submenu in-process.
    onTapped: {
        if (rootItem.recording)
            Quickshell.execDetached([rootItem.binPath, "stop"]);
        else
            rootItem.shell.openMenu("capture.screenrecord");
    }

    Component.onCompleted: refresh()

    // The state file is the event source: `bin/screenrecord` writes it when a
    // recording starts and its supervisor removes it when wf-recorder exits.
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell/screenrecording"
        watchChanges: true
        printErrors: false
        // The view stays unloaded until something reads it, and with a file
        // that usually does not exist neither loaded nor loadFailed would ever
        // fire without this first reload.
        Component.onCompleted: reload()
        onLoaded: rootItem.refresh()
        onFileChanged: reload()
        onLoadFailed: rootItem.refresh()
    }

    // The CLI owns the reconciliation and the tooltip wording, as upstream's
    // does; the indicator only renders what it reports.
    Process {
        id: statusProc
        command: [rootItem.binPath, "status", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: rootItem.update(text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                rootItem.recording = false;
                rootItem.outputFile = "";
            }
        }
    }
}

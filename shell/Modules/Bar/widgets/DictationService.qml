import QtQuick
import Quickshell
import Quickshell.Io

// Voice dictation state, split out of the Dictation widget so ONE voxtype
// follower serves every screen (S2). The follower is the whole state source —
// `bin/voxtype-status` is our copy of omarchy-voxtype-status,
// i.e. `voxtype status --follow --format json` parsed line by line, one line
// per transition. Nothing polls and there is no cadence to gate, so the
// process runs for the life of the shell; it outlives a voxtype daemon
// restart (the state file does), and it exits only if voxtype is missing, in
// which case the helper has already printed one idle record.
QtObject {
    id: root

    // "stopped" (no daemon) | "idle" | "recording" | "transcribing".
    property string dictationState: "idle"
    // voxtype's own first tooltip line ("Recording...", "Transcribing...").
    property string statusTooltip: ""

    readonly property string binPath: Quickshell.env("HOME") + "/.dotfiles/bin/voxtype-status"

    // Upstream reads `alt` first and falls back to `class`; voxtype sets both.
    function update(raw) {
        let data = ({});
        try {
            data = JSON.parse(String(raw || "{}"));
        } catch (e) {
            return;
        }
        dictationState = String(data.alt || data.class || "idle");
        // The extended tooltip is several lines (model, device, backend); the
        // bar shows one, and the first line is the state in words.
        statusTooltip = String(data.tooltip || "").split("\n")[0];
    }

    readonly property Process follower: Process {
        command: [root.binPath]
        running: true
        stdout: SplitParser {
            onRead: data => root.update(data)
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "../components"

// Voice dictation, ported from omarchy's Dictation indicator (CREDITS.md):
// their three voxtype states (idle hidden, recording lit, transcribing), their
// glyphs, and their streaming status process — `bin/voxtype-status` is our copy
// of omarchy-voxtype-status, i.e. `voxtype status --follow --format json`
// parsed line by line. Nothing polls: voxtype emits one line per transition.
//
// Two deviations, both deliberate:
//   * Upstream computes a transcribing glyph and then never renders it — their
//     indicator is active only while `recording`, and an inactive indicator
//     draws its INACTIVE glyph, so 󰔟 is dead code there. Ours is active for
//     both working states, so the hourglass actually shows while a transcript
//     is being produced (which is the state worth seeing: recording ends when
//     you let go, transcribing is the wait).
//   * Their click opens voxtype's config TUI and restarts their shell. Ours
//     toggles recording, which is what a bar affordance for dictation should
//     do — their config opener moved to right-click, minus the restart (this
//     indicator follows a stream and needs no reload to notice a config
//     change).
BarIndicator {
    id: rootItem

    // "stopped" (no daemon) | "idle" | "recording" | "transcribing".
    // Not named `state`: that is Item's own property.
    property string dictationState: "idle"
    // voxtype's own first tooltip line ("Recording...", "Transcribing...").
    property string statusTooltip: ""

    readonly property string binPath: Quickshell.env("HOME") + "/.dotfiles/bin/voxtype-status"

    active: dictationState === "recording" || dictationState === "transcribing"
    // md-microphone, swapped for md-timer_sand while the transcript is made.
    activeGlyph: dictationState === "transcribing" ? "󰔟" : "󰍬"
    inactiveGlyph: "󰍬"
    activeTooltip: statusTooltip !== "" ? statusTooltip : dictationState
    inactiveTooltip: "Dictate"

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

    onTapped: button => {
        if (button === Qt.RightButton)
            Quickshell.execDetached(["foot", "--app-id=qshell-float", "-e", "voxtype", "configure"]);
        else
            Quickshell.execDetached(["voxtype", "record", "toggle"]);
    }

    // The follower is the whole state source. It outlives a voxtype daemon
    // restart (the state file does), and it exits only if voxtype is missing,
    // in which case the helper has already printed one idle record.
    Process {
        command: [rootItem.binPath]
        running: true
        stdout: SplitParser {
            onRead: data => rootItem.update(data)
        }
    }
}

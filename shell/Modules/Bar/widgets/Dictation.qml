import QtQuick
import Quickshell
import "../components"

// Voice dictation, ported from omarchy's Dictation indicator (CREDITS.md):
// their three voxtype states (idle hidden, recording lit, transcribing) and
// their glyphs. The streaming status process lives in DictationService — ONE
// follower at the bar root, shared by every screen's copy of this widget
// (S2).
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
//     do — their config opener moved to right-click, minus the restart (the
//     service follows a stream and needs no reload to notice a config
//     change).
BarIndicator {
    id: rootItem

    // The shared voxtype follower, injected by the bar's registry.
    required property DictationService dictation

    active: dictation.dictationState === "recording" || dictation.dictationState === "transcribing"
    // md-microphone, swapped for md-timer_sand while the transcript is made.
    activeGlyph: dictation.dictationState === "transcribing" ? "󰔟" : "󰍬"
    inactiveGlyph: "󰍬"
    activeTooltip: dictation.statusTooltip !== "" ? dictation.statusTooltip : dictation.dictationState
    inactiveTooltip: "Dictate"

    onTapped: button => {
        if (button === Qt.RightButton)
            Quickshell.execDetached(["foot", "--app-id=qshell-float", "-e", "voxtype", "configure"]);
        else
            Quickshell.execDetached(["voxtype", "record", "toggle"]);
    }
}

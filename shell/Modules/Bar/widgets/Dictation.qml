import QtQuick
import Quickshell
import "../components"

// Voice dictation, ported from omarchy's Dictation indicator:
// their three voxtype states (idle hidden, recording lit, transcribing) and
// their glyphs. The streaming status process lives in DictationService — ONE
// follower at the bar root, shared by every screen's copy of this widget
// (S2).
//
// Two deviations from upstream's rendering, both deliberate:
//   * Upstream computes a transcribing glyph and then never renders it — their
//     indicator is active only while `recording`, and an inactive indicator
//     draws its INACTIVE glyph, so 󰔟 is dead code there. Ours is active for
//     both working states, so the hourglass actually shows while a transcript
//     is being produced (which is the state worth seeing: recording ends when
//     you let go, transcribing is the wait).
//   * Their click opens voxtype's config TUI and restarts their shell. Ours
//     opens the dictation panel.
//
// THE BUTTONS MOVED (2026-09-04), when the panel arrived. Left-click used to
// toggle recording; it now opens the panel, which is what left-click does on
// every other widget in this bar, and recording moved to right-click so it is
// still one click from the bar. Nothing lost a binding: the primary way to
// dictate is a double-tap of Alt (packages/src/qshell-dshift.c), which is
// untouched, and the panel has its own Record button. The config TUI kept its
// place under middle-click.
//
// Recording goes through bin/voxtype-toggle rather than `voxtype record
// toggle`: the daemon is stopped when idle, the microphone is muted at rest,
// and the take has to be stamped for the log. The wrapper does all three; a
// bare toggle would fail on the first and silently record silence on the
// second.
BarIndicator {
    id: rootItem

    // The shared voxtype follower, injected by the bar's registry.
    required property DictationService dictation

    // A meeting counts as active too, and that is the point of it being here:
    // meeting mode records for an hour with nothing else on screen to say so,
    // and an indicator that stayed dark through it would be the shell keeping
    // a secret about an open microphone.
    active: dictation.busy || dictation.meetingActive
    // md-microphone, md-timer_sand while the transcript is made,
    // md-record-rec while a meeting is running.
    activeGlyph: dictation.meetingActive ? "󰑊" : (dictation.dictationState === "transcribing" ? "󰔟" : "󰍬")
    inactiveGlyph: "󰍬"
    activeTooltip: dictation.meetingActive ? (dictation.meetingRecording ? "Meeting recording" : "Meeting paused") : (dictation.statusTooltip !== "" ? dictation.statusTooltip : dictation.dictationState)
    inactiveTooltip: "Dictate"

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("DictationPanel.qml", {
                theme: rootItem.theme,
                dictation: rootItem.dictation
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            rootItem.dictation.toggleRecording();
        else if (button === Qt.MiddleButton)
            rootItem.dictation.openConfigurator();
        else
            openPanel();
    }

    PanelLoader {
        id: panelLoader
    }

    // The indicator is hidden until the container reveals it, and opening a
    // panel suppresses the bar's centre hover reveal — so the glyph this card
    // is anchored to would collapse the moment the pointer left it. Holding
    // the reveal for as long as the panel is open keeps the anchor real.
    Connections {
        target: panelLoader.item
        ignoreUnknownSignals: true

        function onPanelOpened() {
            if (rootItem.indicatorHost)
                rootItem.indicatorHost.setIndicatorPanelHeld(true);
        }

        function onPanelClosed() {
            if (rootItem.indicatorHost)
                rootItem.indicatorHost.setIndicatorPanelHeld(false);
        }
    }
}

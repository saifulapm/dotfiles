import QtQuick
import Quickshell
import "../components"
import "../../../components"

// Display — omarchy's monitor plugin on niri IPC, carrying night light too
// (they were two widgets and two panels until they weren't; see MonitorPanel
// for why). Wheel adjusts brightness, right click flips the night-light hold,
// left click opens the one panel that answers both.
//
// The mark is the night-light state, not a monitor: md-white_balance_sunny
// while the display is its normal colour and md-weather_night while it is
// warmed. A screen icon would name the hardware, which is never the question
// — "is my display warmed right now, and did I pin it that way" is, and it is
// the only thing here that changes on its own.
//
// A HELD preset — the schedule suspended by hand — draws in the accent rather
// than the foreground. That distinction is the one the icon exists to make:
// "warm because it is 9pm" and "warm because I pinned it" look identical on
// the glass and are entirely different facts about the machine.
//
// With no sunsetr on the machine there is no night-light state to draw, so
// the mark falls back to the plain sun at full foreground and the panel drops
// its night-light sections. The widget itself never hides: brightness, scale
// and the output rows are always worth a click.
BarIcon {
    id: rootItem

    readonly property bool hasNightLight: !!nightlight && nightlight.probed && nightlight.available
    readonly property bool lit: hasNightLight && nightlight.warm
    readonly property bool held: hasNightLight && nightlight.forced

    glyph: rootItem.lit ? "󰖔" // md-weather_night
    : "󰖙" // md-white_balance_sunny
    glyphScale: 1.0

    // Held is the only case worth painting; undefined lets BarIcon's own
    // contentColor keep the hover and active behaviour every other icon has.
    glyphColor: rootItem.held && rootItem.nightlight.running ? rootItem.theme.accent : undefined

    tooltipText: {
        const displays = Quickshell.screens.length + " display" + (Quickshell.screens.length === 1 ? "" : "s");
        if (!rootItem.hasNightLight)
            return displays;
        return displays + " · " + rootItem.nightlight.tooltip;
    }

    // The shell's AutoBrightness service, handed on to the panel so its
    // BRIGHTNESS section can carry the auto row.
    property var autoBrightness: null

    // The shared NightLightService, injected by the bar's registry — ONE
    // instance (and one follower) however many screens carry this widget (S2).
    property var nightlight: null

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("MonitorPanel.qml", {
                theme: rootItem.theme,
                autoBrightness: rootItem.autoBrightness,
                nightlight: rootItem.nightlight
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        // Right click flips hold ⇄ schedule without opening anything — the
        // night-light widget's gesture, kept because it is the one thing here
        // worth doing without looking. Only where there is a daemon to flip.
        if (button === Qt.RightButton) {
            if (rootItem.hasNightLight)
                rootItem.nightlight.toggle();
            return;
        }
        openPanel();
    }

    onWheelMoved: delta => {
        Quickshell.execDetached(["qs", "ipc", "call", "osd", delta > 0 ? "brightnessUp" : "brightnessDown"]);
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    PanelLoader {
        id: panelLoader
    }
}

import QtQuick
import Quickshell
import "../components"
import "../../../components"
import "NightLightModel.js" as Model

// Night light — sunsetr's state as a bar button, in the shape the warp and
// devservices widgets share.
//
// The mark is md-weather_night while the display is warmed and
// md-white_balance_sunny while it is not, because those are the two things a
// glance is asking about. It carries state the way the dropbox mark does:
// full bar foreground when the filter is doing something, dimmed and
// darkened when it is not.
//
// A HELD preset — the schedule suspended by hand — is drawn with the accent
// rather than the foreground. That distinction is the one the icon exists to
// make: "warm because it is 9pm" and "warm because I pinned it" look
// identical on the glass and are entirely different facts about the machine,
// and the second one is the one that will still be true at noon tomorrow.
//
// Left click opens the panel, right click toggles (hold ⇄ schedule, the same
// policy bin/nightlight owns), middle click re-probes.
//
// With no sunsetr on the machine the widget takes no width, draws nothing and
// starts nothing after its one presence probe — this bar's contract for an
// optional CLI, and the same one Warp keeps. A daemon that is merely stopped
// is a different case and stays visible: it is one click from running, and
// the panel is where that click is.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind a real binary, and never before the presence
    // probe has answered.
    visible: nightlight.probed && nightlight.available

    // The shared service, injected by the bar's registry — ONE instance (and
    // one follower) however many screens carry this widget (S2).
    required property NightLightService nightlight

    readonly property bool lit: nightlight.warm
    readonly property bool held: nightlight.forced

    tooltipText: nightlight.tooltip

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("NightLightPanel.qml", {
                theme: rootItem.theme,
                nightlight: rootItem.nightlight
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            nightlight.toggle();
        else if (button === Qt.MiddleButton)
            nightlight.refresh();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    OpticalGlyph {
        id: mark

        text: rootItem.lit ? "󰖔" // md-weather_night
        : "󰖙" // md-white_balance_sunny
        pixelSize: 13
        verticalInkCenter: true
        // Held reads as accent, scheduled as plain foreground, off as
        // neither. The dim/darken pair is the dropbox mark's, so an inactive
        // night light sits at the same weight as every other idle widget on
        // the bar rather than shouting.
        color: {
            if (!rootItem.nightlight.running)
                return Qt.darker(rootItem.barFg, 1.55);
            if (rootItem.held)
                return rootItem.theme.accent;
            return rootItem.lit ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55);
        }
        opacity: rootItem.nightlight.running && (rootItem.lit || rootItem.held) ? 1.0 : 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true

        // Mid-fade the mark breathes, so a transition that takes 45 minutes
        // is visible as one rather than reading as a stuck icon. sunsetr's
        // own `state` field is what says so; a settled display never
        // animates.
        SequentialAnimation on opacity {
            running: rootItem.nightlight.transitioning
            loops: Animation.Infinite

            NumberAnimation {
                to: 0.45
                duration: rootItem.theme.time(3)
                easing.type: rootItem.theme.easing
            }

            NumberAnimation {
                to: 1.0
                duration: rootItem.theme.time(3)
                easing.type: rootItem.theme.easing
            }
        }

        onOpacityChanged: if (!rootItem.nightlight.transitioning) {
            const settled = rootItem.nightlight.running && (rootItem.lit || rootItem.held) ? 1.0 : 0.6;
            if (opacity !== settled)
                opacity = settled;
        }
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

import QtQuick
import Quickshell
import "../components"
import "../../../components"
import "TimezonesModel.js" as Model

// Timezones — a globe on the bar, the world clock behind it.
//
// The mark carries exactly one bit: peak or not. It sits at the bar's idle
// weight through the off-peak hours and warms to the accent inside a peak
// window, so "am I in the window" is answered by glancing at the bar. The
// tooltip does the rest of the talking — every configured zone, one line each,
// plus the word for the colour — which is the whole answer most of the time
// and costs no click.
//
// Left click opens the grid panel, right click re-reads the offsets.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    visible: timezones.probed && timezones.available

    required property TimezonesService timezones

    tooltipText: timezones.tooltip

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("TimezonesPanel.qml", {
                theme: rootItem.theme,
                timezones: rootItem.timezones
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            timezones.refresh();
        else
            openPanel();
    }

    OpticalGlyph {
        text: "󰖟" // md-web
        pixelSize: 13
        verticalInkCenter: true
        // Warms to the accent inside a peak window and drops back to the bar's
        // idle weight outside one — the same gesture the prayer mark makes
        // when a prayer is imminent, so the bar has one vocabulary for "now is
        // the moment" rather than a new one per widget.
        color: rootItem.timezones.peak ? rootItem.theme.accent : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.timezones.peak ? 1.0 : 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true

        Behavior on opacity {
            NumberAnimation {
                duration: rootItem.theme.motion.standard
                easing.type: rootItem.theme.motion.easing
            }
        }
    }

    PanelLoader {
        id: panelLoader
    }
}

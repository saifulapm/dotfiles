import QtQuick
import Quickshell
import "../components"
import "../../../components"
import "TimezonesModel.js" as Model

// Timezones — a globe on the bar, the world clock behind it.
//
// The mark is constant: unlike its neighbours this widget has no state to
// carry, only information to hold. It sits at the bar's idle weight and the
// tooltip does the talking — every configured zone, one line each, which is
// the whole answer most of the time and costs no click.
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
        color: Qt.darker(rootItem.barFg, 1.55)
        opacity: 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    PanelLoader {
        id: panelLoader
    }
}

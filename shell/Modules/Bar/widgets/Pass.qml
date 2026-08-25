import QtQuick
import Quickshell
import "../components"
import "../../../components"

// Passwords — the store as a bar button.
//
// The mark is a key at the bar's idle weight and it never changes: there is
// no state here worth signalling, and a password widget that lit up would be
// advertising something. The tooltip says how many entries there are and
// deliberately nothing about what they are — it is visible without any
// interaction at all.
//
// Left click opens the panel, right click re-reads the store.
//
// With no store on the machine the widget takes no width and draws nothing
// after its one probe, the same contract Warp and DevServices keep.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    visible: pass.probed && pass.available

    required property PassService pass

    tooltipText: pass.tooltip

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("PassPanel.qml", {
                theme: rootItem.theme,
                pass: rootItem.pass
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            pass.refresh();
        else
            openPanel();
    }

    OpticalGlyph {
        text: "󰌆" // md-key_variant
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

import QtQuick
import Quickshell
import "../components"
import "../../../components"

// Removable drives — a bar button that only exists while a drive does.
//
// That is the whole visual contract, and it is different from every other
// optional widget on this bar: Warp and DevServices hide when the TOOL is
// absent and then stay put, because their subject is a permanent fact about
// the machine. A USB stick is not. Plug one in and the icon appears; pull it
// out and the bar closes up behind it, so the widget is never a control for
// something that is not there.
//
// The mark goes to the warning colour while the kernel still has requests in
// flight. That is the one thing this widget exists to say — a copy dialog at
// 100% is the application finishing, not the device — and it is worth the
// bar's attention for the few seconds it lasts.
//
// Left click opens the panel, right click re-probes.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    visible: drives.probed && drives.driveCount > 0

    required property DrivesService drives

    tooltipText: drives.tooltip

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("DrivesPanel.qml", {
                theme: rootItem.theme,
                drives: rootItem.drives
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            drives.refresh();
        else
            openPanel();
    }

    OpticalGlyph {
        id: mark

        text: "󰋊" // md-harddisk
        pixelSize: 13
        verticalInkCenter: true
        color: rootItem.drives.busy ? rootItem.theme.warn : rootItem.barFg
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true

        // Breathing while busy, so "wait" is legible without reading the
        // tooltip. It stops the instant the queue drains, which is also the
        // moment it becomes safe to pull the drive out.
        SequentialAnimation on opacity {
            running: rootItem.drives.busy
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

        onOpacityChanged: if (!rootItem.drives.busy && opacity !== 1.0)
            opacity = 1.0
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

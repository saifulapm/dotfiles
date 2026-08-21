import QtQuick
import Quickshell
import "../components"
import "../../../components"

// SSH — the hosts in ~/.ssh/config as a bar button, in the shape the
// devservices and warp widgets share.
//
// The mark is the md-server glyph at a constant weight: unlike the widgets
// either side of it this one has no on/off state to carry. A host list is
// either there or it isn't, and "there" is the only case that draws anything.
// It therefore sits permanently at the dimmed weight the rest of the bar's
// idle widgets use, rather than claiming the full foreground for a control
// that is never active.
//
// Left click opens the panel, right click re-reads the config.
//
// With no ssh config — or one that declares only `Host *` — the widget takes
// no width and draws nothing after its one probe. That is this bar's contract
// for an optional surface, the same one Warp and DevServices keep.
BarButton {
    id: rootItem

    // The icon slot, on whichever axis runs along the bar.
    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // Only ever visible behind a real host list, and never before the probe
    // has answered.
    visible: ssh.probed && ssh.available

    // The shared service, injected by the bar's registry — ONE instance
    // however many screens carry this widget (S2).
    required property SshService ssh

    tooltipText: ssh.tooltip

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("SshPanel.qml", {
                theme: rootItem.theme,
                ssh: rootItem.ssh
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            ssh.refresh();
        else
            openPanel();
    }

    // Sole child of BarButton's centered content row, so it needs no anchors
    // of its own (and a Row forbids the horizontal ones anyway).
    OpticalGlyph {
        text: "󰣀" // md-shield_key / terminal-adjacent server mark
        pixelSize: 13
        verticalInkCenter: true
        color: Qt.darker(rootItem.barFg, 1.55)
        opacity: 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

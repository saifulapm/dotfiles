import Quickshell
import Quickshell.Wayland
import QtQuick

// The flat primitive is a plain fill, so the paper never redraws unless the theme changes.
PanelWindow {
    id: paper

    required property var theme
    property bool swapped: false

    // Emitted once, when this window's first frame reaches the compositor.
    signal firstFrame

    Connections {
        target: paper.swapped ? null : paper.contentItem.Window.window
        function onFrameSwapped() {
            paper.swapped = true;
            paper.firstFrame();
        }
    }

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "dots-paper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: theme.color.paper ?? "transparent"
    }
}

import Quickshell
import Quickshell.Wayland
import QtQuick

// The paper behind every window on one output. The flat primitive is a plain fill, so it
// never redraws unless the theme changes.
PanelWindow {
    required property var theme

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

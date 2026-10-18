import Quickshell
import Quickshell.Wayland
import QtQuick
import "lib/margins.mjs" as M

// At rest the island is the clock: an ink box with a hard accent shadow 3 px down and right.
PanelWindow {
    id: island

    required property var theme
    required property var niri
    required property var clock
    readonly property string text: M.clockText(clock.now)
    readonly property real boxWidth: box.width

    screen: Quickshell.screens.find(s => s.name === niri.focusedOutput) ?? Quickshell.screens[0]
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "dots-island"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    margins.top: 10
    implicitWidth: box.width + 3
    implicitHeight: box.height + 3
    color: "transparent"

    Rectangle {
        x: 3
        y: 3
        width: box.width
        height: box.height
        color: island.theme.color.accent ?? "transparent"
    }

    Rectangle {
        id: box
        width: label.implicitWidth + 28
        height: 34
        color: island.theme.color.ink ?? "transparent"

        Text {
            id: label
            anchors.centerIn: parent
            text: island.text
            color: island.theme.color.paper ?? "white"
            font.family: island.theme.tokens?.type.mono ?? ""
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }
}

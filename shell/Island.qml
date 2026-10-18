import Quickshell
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/margins.mjs" as M

// At rest the island is the clock, a Surface box 10 px below the top edge; the window pads for its shadow.
PanelWindow {
    id: island

    required property var theme
    required property var niri
    required property var clock
    // A theme switch's failure, shown in place of the clock for 5 s.
    property string notice: ""
    readonly property string text: notice || M.clockText(clock.now)
    readonly property real boxWidth: box.width
    // Room for the widest shadow, Artboard's soft one, beside and below the box.
    readonly property int padSide: 32
    readonly property int padBelow: 44

    screen: Quickshell.screens.find(s => s.name === niri.focusedOutput) ?? Quickshell.screens[0]
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "dots-island"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    implicitWidth: box.width + 2 * padSide
    implicitHeight: box.y + box.height + padBelow
    color: "transparent"
    // Only the box takes clicks, not the shadow around it.
    mask: Region {
        item: box
    }

    Connections {
        target: island.theme
        function onNotice(text) {
            island.notice = text;
            noticeTick.restart();
        }
    }

    Tick {
        id: noticeTick
        interval: 5000
        onTriggered: island.notice = ""
    }

    Root.Surface {
        id: box
        x: island.padSide
        y: 10
        width: Math.ceil(label.implicitWidth) + 28
        height: 34
        tokens: island.theme.tokens
        role: "island"

        Text {
            id: label
            anchors.centerIn: parent
            text: island.text
            color: box.style.text
            font.family: island.theme.tokens?.type.mono ?? ""
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }
}

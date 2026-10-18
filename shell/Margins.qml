import Quickshell
import Quickshell.Wayland
import QtQuick
import "lib/margins.mjs" as M

// Each margin sits over an ink hairline that stops 8 px short of the island.
PanelWindow {
    id: root

    required property var theme
    required property var niri
    required property var clock
    required property real islandWidth
    readonly property var view: niri.view(screen.name) ?? { idx: 0, app: null, title: null }
    readonly property var marginState: M.marginState(view, clock.now)
    readonly property real lineEnd: width / 2 - islandWidth / 2 - 8

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "dots-margins"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 41
    color: "transparent"
    // An empty mask lets clicks through to the windows under the margins.
    mask: Region {}

    component Label: Text {
        color: root.theme.color.muted ?? "black"
        font.family: root.theme.tokens?.type.mono ?? ""
        font.pixelSize: 11
        font.letterSpacing: 11 * 0.12
        font.capitalization: Font.AllUppercase
    }

    Row {
        x: 32
        y: 17

        Label {
            id: number
            text: root.marginState.left.workspace
            color: root.theme.color.ink ?? "black"
            font.bold: true
        }

        Label {
            text: M.screenTail(root.view)
            width: Math.max(0, root.lineEnd - 32 - number.width)
            elide: Text.ElideRight
        }
    }

    Label {
        anchors.right: parent.right
        anchors.rightMargin: 32
        y: 17
        text: root.marginState.right.text
    }

    Rectangle {
        x: 32
        y: 40
        width: Math.max(0, root.lineEnd - 32)
        height: 1
        color: root.theme.color.ink ?? "black"
    }

    Rectangle {
        x: root.width - 32 - width
        y: 40
        width: Math.max(0, root.lineEnd - 32)
        height: 1
        color: root.theme.color.ink ?? "black"
    }
}

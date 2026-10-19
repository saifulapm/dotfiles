import Quickshell
import Quickshell.Wayland
import QtQuick
import "lib/margins.mjs" as M
import "lib/goals.mjs" as G
import "lib/surface.mjs" as S

// Each margin sits over an ink hairline that stops 8 px short of the island, when the theme's frame is drawn in ink.
PanelWindow {
    id: root

    required property var theme
    required property var niri
    required property var clock
    required property var power
    required property var network
    required property var goals
    required property real islandWidth
    readonly property var view: niri.view(screen.name) ?? { idx: 0, app: null, title: null }
    readonly property var marginState: M.marginState(view, clock.now, { goal: G.marginGoal(goals.store, clock.now), wifi: network.wifi, battery: power.battery })
    readonly property real lineEnd: width / 2 - islandWidth / 2 - 8
    readonly property var look: S.marginStyle(theme.tokens)

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
        textFormat: Text.PlainText
        color: root.theme.color.muted ?? "black"
        font.family: root.look.font
        font.pixelSize: root.look.size
        font.letterSpacing: root.look.tracking
        font.capitalization: root.look.caps ? Font.AllUppercase : Font.MixedCase
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

    // A Row skips invisible Labels, so an absent word leaves no gap.
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 32
        y: 17
        spacing: 20

        // Paper's accent bold, Artboard's ink medium, Blueprint's amber (its danger token); the voice tells the themes apart.
        Label {
            readonly property bool bracket: root.theme.tokens?.type.display === root.theme.tokens?.type.mono
            readonly property bool caps: root.theme.tokens?.type.ui === root.theme.tokens?.type.mono
            text: root.marginState.right.goal
            visible: text !== ""
            color: (bracket ? root.theme.color.danger : caps ? root.theme.color.accent : root.theme.color.ink) ?? "black"
            font.weight: bracket ? Font.Normal : caps ? Font.Bold : Font.Medium
        }

        Label {
            text: root.marginState.right.wifi
            visible: text !== ""
        }

        Label {
            text: root.marginState.right.battery
            visible: text !== ""
        }

        Label {
            text: root.marginState.right.date
        }
    }

    Rectangle {
        x: 32
        y: 40
        visible: root.look.rules
        width: Math.max(0, root.lineEnd - 32)
        height: 1
        color: root.theme.color.ink ?? "black"
    }

    Rectangle {
        x: root.width - 32 - width
        y: 40
        visible: root.look.rules
        width: Math.max(0, root.lineEnd - 32)
        height: 1
        color: root.theme.color.ink ?? "black"
    }
}

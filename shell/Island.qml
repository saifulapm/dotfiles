import Quickshell
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/island.mjs" as I

// At rest the island is the clock, a Surface box 10 px below the top edge; the window pads for its shadow.
PanelWindow {
    id: island

    required property var theme
    required property var niri
    required property var clock
    required property var notifs
    // A theme switch's failure, shown in place of the clock for 5 s.
    property string notice: ""
    // What the island may show; each is null while it has nothing to show.
    property var question: null
    property bool calendar: false
    readonly property var notification: notifs.current
    property var recording: null
    property var osd: null
    property var toast: null
    property var playing: null
    readonly property var slots: ({
            question,
            calendar,
            notification,
            recording,
            osd,
            toast,
            playing,
            notice
        })
    readonly property string mode: I.pick(slots)
    // When the current mode began, in ms since the epoch, so a check can time a mode without polling error.
    property real modeSince: Date.now()
    onModeChanged: modeSince = Date.now()
    readonly property string text: I.islandText(mode, slots, clock.now)
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
        // A notification is a 440 px card, as drawn; every other mode is one line as wide as its text.
        width: island.mode === "notification" ? 440 : I.boxWidth(Math.ceil(label.implicitWidth) + 28)
        height: island.mode === "notification" ? card.implicitHeight + 28 : 34
        tokens: island.theme.tokens
        role: "island"

        Text {
            id: label
            visible: island.mode !== "notification"
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 28)
            elide: Text.ElideRight
            text: island.text
            color: box.style.text
            font.family: island.theme.tokens?.type.mono ?? ""
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Column {
            id: card
            visible: island.mode === "notification"
            x: 18
            y: 14
            width: box.width - 36
            spacing: 2

            Text {
                width: parent.width
                text: island.notification?.app ?? ""
                elide: Text.ElideRight
                color: Qt.alpha(box.style.text, 0.65)
                font.family: island.theme.tokens?.type.ui ?? ""
                font.pixelSize: 12
            }

            Text {
                width: parent.width
                text: island.notification?.summary ?? ""
                elide: Text.ElideRight
                color: box.style.text
                font.family: island.theme.tokens?.type.ui ?? ""
                font.pixelSize: 14
                font.weight: Font.Medium
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: island.notification?.body ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: Qt.alpha(box.style.text, 0.85)
                font.family: island.theme.tokens?.type.ui ?? ""
                font.pixelSize: 13
            }
        }
    }
}

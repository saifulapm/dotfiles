import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/margins.mjs" as M
import "lib/goals.mjs" as G
import "lib/idle.mjs" as Idle
import "lib/surface.mjs" as S
import "lib/voice.mjs" as V

// Each margin sits over an ink hairline that stops 8 px short of the island, when the theme's frame is drawn in ink.
PanelWindow {
    id: root

    required property var theme
    required property var niri
    required property var clock
    required property var power
    required property var network
    required property var goals
    required property var sync
    required property real islandWidth
    readonly property var view: niri.view(screen.name) ?? { idx: 0, app: null, title: null }
    // The Imbox unread count kak-mail writes; 0 hides the item.
    property int mail: 0
    readonly property var marginState: M.marginState(view, clock.now, { awake: Idle.awakeWord(Root.State.awakeUntil), sync: sync.failing ? "sync !" : "", goal: G.marginGoal(goals.store, clock.now), mail: mail, wifi: network.wifi, battery: power.battery })
    readonly property var goal: G.marginGoalParts(goals.store, clock.now)
    readonly property var voice: V.marginLook(theme.tokens)
    readonly property real lineEnd: width / 2 - islandWidth / 2 - 8
    readonly property var look: S.marginStyle(theme.tokens)

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "dots-margins"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // The margins hide while the shown window runs edge to edge, so they need no zone and a Mod+M window fills the output.
    exclusionMode: ExclusionMode.Ignore
    visible: !niri.edgeToEdge(screen.name, screen.width)
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 41
    color: "transparent"
    // Only the Notes corner takes the pointer; clicks anywhere else go through to the windows under the margins.
    mask: Region {
        item: notesCorner
    }

    // The pointer pushed into the top-right corner opens Notes, as niri's bottom-left corner opens the overview.
    signal notesCornerReached

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots"

    // The watch needs the folder, which nothing may have made yet.
    Process {
        running: true
        command: ["mkdir", "-p", root.stateDir]
        onExited: mailFile.path = root.stateDir + "/mail-unread"
    }

    // kak-mail renames a new file over the old one, and the watch follows the path.
    FileView {
        id: mailFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.mail = M.mailCount(text())
        onLoadFailed: root.mail = 0
    }

    component Label: Text {
        textFormat: Text.PlainText
        color: root.theme.color.muted ?? "black"
        font.family: root.look.font
        font.pixelSize: root.look.size
        font.letterSpacing: root.look.tracking
        font.capitalization: root.look.caps ? Font.AllUppercase : Font.MixedCase
    }

    // Paper's dash and Blueprint's dot between the right margin's words; Artboard has none.
    component Sep: Label {
        property bool shown: true
        text: root.voice.sep
        visible: shown && text !== ""
    }

    // The words as drawn, read back from the labels, for `qs ipc call margins state`.
    function drawnState() {
        const right = [awakeLabel, syncLabel, goalLabel, mailLabel, wifiLabel, batteryLabel, dateLabel].filter(l => l.visible).map(l => l.text).join(voice.sep ? " " + voice.sep + " " : " ");
        return {
            left: number.text + column.text + tail.text,
            marks: Array.from(marks.children).filter(l => l.text !== undefined).map(l => l.text).join("").trim(),
            markColors: Array.from(marks.children).filter(l => l.text !== undefined).map(l => String(l.color)),
            right: right,
            leftEnd: marks.mapToItem(null, marks.width, 0).x,
            leftElided: tail.truncated,
            goalElided: goalLabel.truncated,
            rightStart: rightRow.mapToItem(null, 0, 0).x,
            lineEnd: lineEnd,
            width: width
        };
    }

    Row {
        x: 32
        y: 17

        Label {
            id: number
            text: root.voice.number(root.view.idx)
            color: root.voice.numberColor ?? "black"
            font.weight: root.voice.numberWeight
        }

        // Which of the shown workspace's columns has the focus, read from niri's column numbers since niri reports no scroll position.
        Label {
            id: column
            text: root.voice.column(root.niri.column(root.screen.name))
        }

        Label {
            id: tail
            text: root.voice.tail(root.view)
            width: Math.min(implicitWidth, Math.max(0, root.lineEnd - 32 - number.width - column.width - marks.width))
            elide: Text.ElideRight
        }

        // The workspaces holding a window that asked for attention; the title gives up their room.
        Row {
            id: marks

            Repeater {
                model: root.voice.marks(root.niri.urgent(root.screen.name))

                Label {
                    required property var modelData
                    text: modelData.text
                    color: modelData.color ?? "black"
                }
            }
        }
    }

    // A Row skips invisible items, so an absent word leaves no gap; each word but the date is followed by the theme's separator.
    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: 32
        y: 17
        spacing: root.voice.spacing

        // Stay awake's end, so a hold left on is never forgotten.
        Label {
            id: awakeLabel
            text: root.marginState.right.awake ? root.voice.word(root.marginState.right.awake) : ""
            visible: text !== ""
        }
        Sep {
            id: awakeSep
            shown: awakeLabel.visible
        }

        // The danger token reads as a warning in every theme.
        Label {
            id: syncLabel
            text: root.marginState.right.sync ? root.voice.word(root.marginState.right.sync) : ""
            visible: text !== ""
            color: root.theme.color.danger ?? "black"
        }
        Sep {
            id: syncSep
            shown: syncLabel.visible
        }

        Row {
            id: goalItem
            visible: goalLabel.text !== ""
            spacing: 6

            Rectangle {
                visible: root.voice.dot
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: root.voice.dotColor ?? "black"
            }

            Label {
                id: goalLabel
                text: root.voice.goal(root.goal)
                // A title can arrive by sync at any length, so it takes only the room the other words leave before the island.
                readonly property real room: root.lineEnd - 32 - [awakeLabel, syncLabel, mailLabel, wifiLabel, batteryLabel, dateLabel].filter(l => l.visible).reduce((w, l) => w + l.width + rightRow.spacing, 0) - [awakeSep, syncSep, goalSep, mailSep, wifiSep, batterySep].filter(l => l.visible).reduce((w, l) => w + l.width + rightRow.spacing, 0) - (root.voice.dot ? 12 : 0)
                width: Math.min(implicitWidth, Math.max(0, room))
                elide: Text.ElideRight
                color: root.voice.goalColor ?? "black"
                font.weight: root.voice.goalWeight
            }
        }
        Sep {
            id: goalSep
            shown: goalItem.visible
        }

        Label {
            id: mailLabel
            text: root.voice.mail(root.mail)
            visible: text !== ""
            color: root.voice.mailColor ?? "black"
            font.weight: root.voice.mailWeight
        }
        Sep {
            id: mailSep
            shown: mailLabel.visible
        }

        Label {
            id: wifiLabel
            text: root.marginState.right.wifi ? root.voice.word(root.marginState.right.wifi) : ""
            visible: text !== ""
        }
        Sep {
            id: wifiSep
            shown: wifiLabel.visible
        }

        Label {
            id: batteryLabel
            text: root.marginState.right.battery ? root.voice.word(root.marginState.right.battery) : ""
            visible: text !== ""
        }
        Sep {
            id: batterySep
            shown: batteryLabel.visible
        }

        Label {
            id: dateLabel
            text: root.voice.date(root.clock.now)
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

    Item {
        id: notesCorner
        anchors.top: parent.top
        anchors.right: parent.right
        width: 2
        height: 2

        HoverHandler {
            onHoveredChanged: if (hovered)
                root.notesCornerReached()
        }
    }
}

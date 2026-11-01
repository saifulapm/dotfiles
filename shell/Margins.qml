import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/margins.mjs" as M
import "lib/goals.mjs" as G
import "lib/hifi.mjs" as H
import "lib/idle.mjs" as Idle
import "lib/niri.mjs" as N
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
    readonly property var engraving: V.engraving(theme.tokens)
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
    // Hi-Fi's groove draws its second line at y 41, one row below the other themes' rule.
    implicitHeight: voice.engraved ? 42 : 41
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
        style: root.engraving.on ? Text.Raised : Text.Normal
        styleColor: root.engraving.color
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
        const box = item => (p => ({ x: p.x, y: p.y, w: item.width, h: item.height }))(item.mapToItem(null, 0, 0));
        const lamps = Array.from({ length: lampList.count }, (_, i) => lampList.itemAt(i)).filter(l => l);
        const numbers = lamps.map(l => l.modelData.text).join(" ");
        const lit = lamps.find(l => l.modelData.light === "lit");
        return {
            left: (voice.engraved ? numbers : number.text) + column.text + tail.text + pathLabel.text,
            raised: number.style === Text.Raised,
            // In Hi-Fi the workspace number drawn amber is the lit lamp's.
            numberBox: box(lit ? lit.label : number),
            lamps: lamps.map(l => ({ idx: l.modelData.idx, lit: l.modelData.light === "lit", light: l.modelData.light, box: box(l.lamp) })),
            numbers: numbers,
            goalLamp: goalLamp.visible ? { light: goalLamp.light, box: box(goalLamp) } : null,
            islandLeft: width / 2 - islandWidth / 2,
            marks: Array.from(marks.children).filter(l => l.text !== undefined).map(l => l.text).join(voice.engraved ? " " : "").trim(),
            markLamps: Array.from({ length: markList.count }, (_, i) => markList.itemAt(i)?.modelData.lamp ?? "").filter(l => l),
            markColors: Array.from(marks.children).filter(l => l.text !== undefined).map(l => String(l.color)),
            right: right,
            leftEnd: marks.mapToItem(null, marks.width, 0).x,
            leftElided: tail.truncated || pathLabel.truncated,
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
            visible: !root.voice.engraved
            text: root.voice.number(root.view.idx)
            color: root.voice.numberColor ?? "black"
            font.weight: root.voice.numberWeight
        }

        // Hi-Fi's shown workspace, its number after a lit pilot lamp.
        Row {
            id: lampRow
            spacing: 18

            Repeater {
                id: lampList
                model: root.voice.lamps(N.outputWorkspaces(root.niri.state, root.screen.name))

                Row {
                    required property var modelData
                    readonly property Item lamp: lampDot
                    readonly property Item label: lampNumber
                    spacing: 7

                    Root.Lamp {
                        id: lampDot
                        anchors.verticalCenter: parent.verticalCenter
                        tokens: root.theme.tokens
                        light: parent.modelData.light
                        warmth: Root.State.warmth
                    }

                    Label {
                        id: lampNumber
                        text: parent.modelData.text
                        color: parent.modelData.color ?? "black"
                    }
                }
            }
        }

        // Which of the shown workspace's columns has the focus, read from niri's column numbers since niri reports no scroll position.
        Label {
            id: column
            text: root.voice.column(root.niri.column(root.screen.name))
        }

        Label {
            id: tail
            // The room before the island, less what the number or the lamps, the column and the marks take.
            readonly property real room: root.lineEnd - 32 - (number.visible ? number.width : 0) - lampRow.width - column.width - marks.width
            text: root.voice.tail(root.view)
            width: Math.min(implicitWidth, Math.max(0, room))
            elide: Text.ElideRight
            color: root.voice.tailColor ?? "black"
        }

        Label {
            id: pathLabel
            text: root.voice.path(root.view)
            width: Math.min(implicitWidth, Math.max(0, tail.room - tail.width))
            elide: Text.ElideRight
        }

        // The workspaces holding a window that asked for attention; the title gives up their room. Hi-Fi draws each after a red lamp, 18 px apart like its lamp row.
        Row {
            id: marks
            leftPadding: root.voice.engraved && markList.count > 0 ? 18 : 0
            spacing: root.voice.engraved ? 12 : 0

            Repeater {
                id: markList
                model: root.voice.marks(root.niri.urgent(root.screen.name))

                Row {
                    required property var modelData
                    readonly property alias text: markLabel.text
                    readonly property alias color: markLabel.color
                    spacing: 7

                    Root.Lamp {
                        visible: (parent.modelData.lamp ?? "") !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        tokens: root.theme.tokens
                        light: parent.modelData.lamp || "unlit"
                        warmth: Root.State.warmth
                    }

                    Label {
                        id: markLabel
                        text: parent.modelData.text
                        color: parent.modelData.color ?? "black"
                    }
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

            Root.Lamp {
                id: goalLamp
                visible: root.voice.goalLamp !== ""
                anchors.verticalCenter: parent.verticalCenter
                tokens: root.theme.tokens
                light: root.voice.goalLamp || "unlit"
                warmth: Root.State.warmth
            }

            Label {
                id: goalLabel
                text: root.voice.goal(root.goal)
                // A title can arrive by sync at any length, so it takes only the room the other words leave before the island.
                readonly property real room: root.lineEnd - 32 - [awakeLabel, syncLabel, mailLabel, wifiLabel, batteryLabel, dateLabel].filter(l => l.visible).reduce((w, l) => w + l.width + rightRow.spacing, 0) - [awakeSep, syncSep, goalSep, mailSep, wifiSep, batterySep].filter(l => l.visible).reduce((w, l) => w + l.width + rightRow.spacing, 0) - (root.voice.dot || root.voice.goalLamp ? 12 : 0)
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
            color: root.voice.dateColor ?? "black"
        }
    }

    // Hi-Fi's engraved groove in place of the rule: a dark line over a line of ink at 6 %, from the edge to 8 px short of the island.
    component Groove: Item {
        visible: root.voice.engraved
        y: 40
        width: Math.max(0, root.lineEnd)
        height: 2

        Rectangle {
            width: parent.width
            height: 1
            color: H.HIFI.groove
        }

        Rectangle {
            y: 1
            width: parent.width
            height: 1
            color: Qt.alpha(root.theme.color.ink ?? "black", 0.06)
        }
    }

    Groove {}

    Groove {
        x: root.width - width
    }

    Rectangle {
        x: 32
        y: 40
        visible: root.look.rules && !root.voice.engraved
        width: Math.max(0, root.lineEnd - 32)
        height: 1
        color: root.theme.color.ink ?? "black"
    }

    Rectangle {
        x: root.width - 32 - width
        y: 40
        visible: root.look.rules && !root.voice.engraved
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

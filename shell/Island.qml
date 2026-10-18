import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "." as Root
import "lib/island.mjs" as I
import "lib/questions.mjs" as Q
import "lib/margins.mjs" as M

// At rest the island is the clock, a Surface box 10 px below the top edge; the window pads for its shadow.
PanelWindow {
    id: island

    required property var theme
    required property var niri
    required property var clock
    required property var notifs
    required property var questions
    // A theme switch's failure, shown in place of the clock for 5 s.
    property string notice: ""
    // What the island may show; each is null while it has nothing to show.
    readonly property var question: questions.current
    // The month the calendar shows, {year, month}, while Mod+I has it open.
    property var calendar: null
    readonly property var grid: calendar ? I.monthGrid(calendar.year, calendar.month) : null
    readonly property int today: calendar && calendar.year === clock.now.getFullYear() && calendar.month === clock.now.getMonth() ? clock.now.getDate() : 0
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
    // Mod+I gives the island the keyboard to act on what it shows; anything but a question gives it back.
    property bool focused: false
    property bool replying: false

    function focusIsland() {
        if (mode === "rest" || mode === "playing")
            calendar = {
                year: clock.now.getFullYear(),
                month: clock.now.getMonth()
            };
        else if (mode !== "question")
            return;
        focused = true;
        keys.forceActiveFocus();
    }

    function release() {
        focused = false;
        calendar = null;
        replying = false;
        reply.text = "";
    }

    // The hub rewrites the file on any change, so only a different question takes the keyboard back.
    readonly property string questionId: question?.id ?? ""
    onQuestionIdChanged: release()

    screen: Quickshell.screens.find(s => s.name === niri.focusedOutput) ?? Quickshell.screens[0]
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "dots-island"
    WlrLayershell.keyboardFocus: focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
        // As drawn: a 440 px notification card, a 560 px question, a 320 px calendar and a 280 px OSD bar; any other mode is one line as wide as its text.
        width: ({ notification: 440, question: I.MAX_WIDTH, calendar: 320, osd: 280 })[island.mode] ?? I.boxWidth(Math.ceil(label.implicitWidth) + 28)
        height: island.mode === "notification" ? card.implicitHeight + 28 : island.mode === "question" ? ask.implicitHeight + 32 : island.mode === "calendar" ? month.implicitHeight + 32 : island.mode === "osd" ? 36 : 34
        tokens: island.theme.tokens
        role: "island"

        Text {
            textFormat: Text.PlainText
            id: label
            visible: ["notification", "question", "calendar", "osd"].indexOf(island.mode) < 0
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 28)
            elide: Text.ElideRight
            text: island.text
            color: box.style.text
            font.family: island.theme.tokens?.type.mono ?? ""
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Row {
            visible: island.mode === "osd"
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            // A speaker for volume, a sun for brightness, drawn as 16 px strokes in the text colour.
            Shape {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                ShapePath {
                    strokeColor: box.style.text
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathSvg {
                        path: island.osd?.kind === "brightness"
                            ? "M 11 8 A 3 3 0 1 1 5 8 A 3 3 0 1 1 11 8 M 8 1 L 8 2.5 M 8 13.5 L 8 15 M 1 8 L 2.5 8 M 13.5 8 L 15 8 M 3 3 L 4 4 M 12 12 L 13 13 M 3 13 L 4 12 M 12 4 L 13 3"
                            : "M 2 6 L 5 6 L 9 2.5 L 9 13.5 L 5 10 L 2 10 Z M 11.5 5.5 Q 13 8 11.5 10.5 M 13.5 3.5 Q 16 8 13.5 12.5"
                    }
                }
            }

            Rectangle {
                width: 180
                height: 4
                radius: 2
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.alpha(box.style.text, 0.2)

                Rectangle {
                    width: parent.width * Math.min(island.osd?.value ?? 0, 100) / 100
                    height: parent.height
                    radius: parent.radius
                    color: box.style.text
                }
            }

            Text {
                textFormat: Text.PlainText
                width: 36
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: island.osd?.value ?? ""
                color: box.style.text
                font.family: island.theme.tokens?.type.mono ?? ""
                font.pixelSize: 12
            }
        }

        Column {
            id: card
            visible: island.mode === "notification"
            x: 18
            y: 14
            width: box.width - 36
            spacing: 2

            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: island.notification?.app ?? ""
                elide: Text.ElideRight
                color: Qt.alpha(box.style.text, 0.65)
                font.family: island.theme.tokens?.type.ui ?? ""
                font.pixelSize: 12
            }

            Text {
                textFormat: Text.PlainText
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

        Item {
            id: keys
            focus: island.focused
            Keys.onPressed: event => {
                event.accepted = true;
                if (island.mode === "calendar") {
                    if (event.key === Qt.Key_Escape)
                        island.release();
                    else if (event.key === Qt.Key_H || event.key === Qt.Key_L)
                        island.calendar = I.shiftMonth(island.calendar.year, island.calendar.month, event.key === Qt.Key_H ? -1 : 1);
                    return;
                }
                const q = island.question;
                if (!q)
                    return;
                if (event.key === Qt.Key_Escape) {
                    island.questions.putAway(q.id);
                } else if (event.key === Qt.Key_R) {
                    island.replying = true;
                    reply.forceActiveFocus();
                } else {
                    const option = Q.optionFor(q, event.text);
                    if (option !== null)
                        island.questions.answer(q.id, option);
                }
            }
        }

        Column {
            id: month
            visible: island.mode === "calendar"
            x: 18
            y: 16
            width: box.width - 36
            spacing: 10

            Item {
                width: parent.width
                height: monthTitle.implicitHeight

                Text {
                    textFormat: Text.PlainText
                    id: monthTitle
                    text: island.grid?.title ?? ""
                    color: box.style.text
                    font.family: island.theme.tokens?.type.ui ?? ""
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    text: M.clockText(island.clock.now)
                    color: Qt.alpha(box.style.text, 0.65)
                    font.family: island.theme.tokens?.type.mono ?? ""
                    font.pixelSize: 12
                }
            }

            Grid {
                columns: 7
                rowSpacing: 6
                width: parent.width

                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"].concat(island.grid?.cells ?? [])

                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isToday: index >= 7 && modelData === island.today
                        width: month.width / 7
                        height: 18
                        radius: 4
                        color: isToday ? box.style.text : "transparent"

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: parent.modelData ?? ""
                            color: parent.isToday ? box.style.fill : Qt.alpha(box.style.text, parent.index < 7 ? 0.55 : 0.85)
                            font.family: island.theme.tokens?.type.mono ?? ""
                            font.pixelSize: 11
                            font.weight: parent.isToday ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                text: "h/l month · Esc"
                color: Qt.alpha(box.style.text, 0.55)
                font.family: island.theme.tokens?.type.mono ?? ""
                font.pixelSize: 11
            }
        }

        Column {
            id: ask
            visible: island.mode === "question"
            x: 20
            y: 16
            width: box.width - 40
            spacing: 12

            Item {
                width: parent.width
                height: where.implicitHeight

                Text {
                    textFormat: Text.PlainText
                    id: where
                    text: [island.question?.project, island.question?.machine].filter(p => p).join(" · ")
                    color: Qt.alpha(box.style.text, 0.65)
                    font.family: island.theme.tokens?.type.mono ?? ""
                    font.pixelSize: 11
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    text: island.focused ? "1-9 pick · r reply · Esc" : "Mod+I to answer"
                    color: Qt.alpha(box.style.text, 0.65)
                    font.family: island.theme.tokens?.type.mono ?? ""
                    font.pixelSize: 11
                }
            }

            Text {
                width: parent.width
                text: island.question?.text ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                lineHeight: 1.3
                color: box.style.text
                font.family: island.theme.tokens?.type.ui ?? ""
                font.pixelSize: 15
            }

            Flow {
                width: parent.width
                spacing: 8
                visible: !island.replying

                Repeater {
                    model: (island.question?.options ?? []).slice(0, 9).concat(["Reply…"])

                    Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool isReply: index === Math.min(island.question?.options.length ?? 0, 9)
                        width: chip.implicitWidth + 24
                        height: chip.implicitHeight + 12
                        radius: 8
                        color: index === 0 && !isReply ? box.style.text : "transparent"
                        border.width: index === 0 && !isReply ? 0 : 1
                        border.color: Qt.alpha(box.style.text, 0.35)

                        Text {
                            textFormat: Text.PlainText
                            id: chip
                            anchors.centerIn: parent
                            text: (parent.isReply ? "r" : parent.index + 1) + " · " + parent.modelData
                            color: parent.index === 0 && !parent.isReply ? box.style.fill : box.style.text
                            font.family: island.theme.tokens?.type.ui ?? ""
                            font.pixelSize: 13
                        }
                    }
                }
            }

            Rectangle {
                visible: island.replying
                width: parent.width
                height: 32
                radius: 8
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(box.style.text, 0.5)

                TextInput {
                    id: reply
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: box.style.text
                    font.family: island.theme.tokens?.type.ui ?? ""
                    font.pixelSize: 13
                    Keys.onReturnPressed: {
                        if (text.trim() !== "" && island.question)
                            island.questions.answer(island.question.id, text);
                    }
                    Keys.onEscapePressed: {
                        island.replying = false;
                        text = "";
                        keys.forceActiveFocus();
                    }
                }
            }
        }
    }
}

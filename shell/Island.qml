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
    readonly property var grid: heldCalendar ? I.monthGrid(heldCalendar.year, heldCalendar.month) : null
    readonly property int today: heldCalendar && heldCalendar.year === clock.now.getFullYear() && heldCalendar.month === clock.now.getMonth() ? clock.now.getDate() : 0
    readonly property var notification: notifs.current
    readonly property real recordingSince: Root.State.recordingSince
    // Bumped each second while a recording runs, so its counter moves.
    property real recordingNow: 0
    readonly property var recording: recordingSince > 0 ? I.recordingText(recordingSince, Math.max(recordingNow, recordingSince)) : null
    property var osd: null
    property var toast: null
    property var playing: null
    // What each part last showed, so a part can leave with its content after its slot has emptied.
    property var heldCalendar: null
    property var heldNotification: null
    property var heldQuestion: null
    property var heldOsd: null
    property string heldText: ""
    onCalendarChanged: if (calendar)
        heldCalendar = calendar
    onNotificationChanged: if (notification)
        heldNotification = notification
    onQuestionChanged: if (question)
        heldQuestion = question
    onOsdChanged: if (osd)
        heldOsd = osd
    onTextChanged: if (I.isCompact(mode))
        heldText = text
    Component.onCompleted: heldText = text
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
    onModeChanged: {
        modeSince = Date.now();
        // The keyboard goes back once what it was given for is gone, such as a notification whose 5 s ran out.
        if (focused && ["calendar", "question", "notification"].indexOf(mode) < 0)
            release();
    }
    readonly property string text: I.islandText(mode, slots, clock.now)
    // As drawn: a 440 px notification card, a 560 px question, a 320 px calendar and a 280 px OSD bar; any other mode is one line as wide as its text.
    readonly property var sizes: ({
            label: [I.boxWidth(Math.ceil(label.implicitWidth) + 28), 34],
            notification: [440, card.implicitHeight + 28],
            question: [I.MAX_WIDTH, ask.implicitHeight + 32],
            calendar: [320, month.implicitHeight + 32],
            osd: [280, 36]
        })
    readonly property string part: ["notification", "question", "calendar", "osd"].indexOf(mode) < 0 ? "label" : mode
    // The box's size once a morph settles; the margins and `island state` read this, never a size mid-morph.
    readonly property real targetWidth: sizes[part][0]
    readonly property real targetHeight: sizes[part][1]
    readonly property real boxWidth: targetWidth
    readonly property real drawnWidth: box.width
    readonly property var motion: I.islandMotion(theme.tokens?.primitive.motion)
    readonly property bool animating: morphing.running || [labelPart, osdPart, notePart, monthPart, askPart].some(p => p.busy)
    // The box morphs from where it is drawn to its target on one clock, so width and height land together.
    property real fromWidth: 0
    property real fromHeight: 0
    property real toWidth: targetWidth
    property real toHeight: targetHeight
    property real progress: 1
    // Picked when a morph starts, since the mode that picks it changes in the same instant as the target.
    property var curve: null
    // The taller of the old and new box while it morphs, so the window resizes twice per morph rather than every frame.
    property real heldHeight: 0
    // What the box last morphed for; a size change with the same content, such as a font loading or a theme switch, snaps instead.
    property string morphedFor: ""
    onTargetWidthChanged: morph()
    onTargetHeightChanged: morph()

    function morph() {
        const content = part + ":" + (notification?.key ?? question?.id ?? "");
        const fresh = morphedFor !== "" && content !== morphedFor;
        morphedFor = content;
        // Width and height each call this; the second lands on the morph the first started.
        if (!fresh && morphing.running) {
            toWidth = targetWidth;
            toHeight = targetHeight;
            return;
        }
        if (!motion || !fresh) {
            morphing.stop();
            heldHeight = 0;
            toWidth = targetWidth;
            toHeight = targetHeight;
            progress = 1;
            return;
        }
        fromWidth = box.width;
        fromHeight = box.height;
        heldHeight = Math.max(heldHeight, box.height);
        toWidth = targetWidth;
        toHeight = targetHeight;
        curve = I.isCompact(mode) ? motion.close : motion.open;
        morphing.duration = curve.ms;
        progress = 0;
        morphing.restart();
    }
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
        else if (mode !== "question" && mode !== "notification")
            return;
        focused = true;
        keys.forceActiveFocus();
    }

    // Runs the notification's default action when it has one; either way it leaves the island.
    function openNotification() {
        if (notification)
            notifs.act(notification.key);
        putAway();
    }

    // Leaves the island only: the notification stays in the Mod+A history.
    function putAway() {
        if (notification)
            notifs.gone(notification.key);
        release();
    }

    // A capture's Captured or a refusal shows for 1.5 s.
    function showToast(text) {
        toast = text;
        toastTick.restart();
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
    implicitWidth: I.MAX_WIDTH + 2 * padSide
    implicitHeight: box.y + Math.max(targetHeight, heldHeight) + padBelow
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
        interval: 1000
        repeat: true
        running: island.recordingSince > 0
        onTriggered: island.recordingNow = Date.now()
    }

    NumberAnimation {
        id: morphing
        target: island
        property: "progress"
        from: 0
        to: 1
        onRunningChanged: if (!running)
            island.heldHeight = 0
    }

    Tick {
        id: toastTick
        interval: 1500
        onTriggered: island.toast = null
    }

    Tick {
        id: noticeTick
        interval: 5000
        onTriggered: island.notice = ""
    }

    Root.Surface {
        id: box
        // Centred in a window as wide as the widest card, so the box morphs without the window resizing.
        x: Math.round((island.implicitWidth - width) / 2)
        y: 10
        width: island.progress >= 1 || !island.curve ? island.toWidth : island.fromWidth + (island.toWidth - island.fromWidth) * I.ease(island.curve.points, island.progress)
        height: island.progress >= 1 || !island.curve ? island.toHeight : island.fromHeight + (island.toHeight - island.fromHeight) * I.ease(island.curve.points, island.progress)
        tokens: island.theme.tokens
        role: "island"

        // Each part is drawn at its own size and clipped to the box as it morphs.
        Item {
            anchors.fill: parent
            clip: true

            IslandPart {
                id: labelPart
                shown: island.part === "label"
                key: island.mode
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.label[0]
                height: island.sizes.label[1]

                Text {
                    id: label
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 28)
                    elide: Text.ElideRight
                    text: I.isCompact(island.mode) ? island.text : island.heldText
                    color: box.style.text
                    font.family: island.theme.tokens?.type.mono ?? ""
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            IslandPart {
                id: osdPart
                shown: island.part === "osd"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.osd[0]
                height: island.sizes.osd[1]

                Row {
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
                                path: island.heldOsd?.kind === "brightness"
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
                            width: parent.width * Math.min(island.heldOsd?.value ?? 0, 100) / 100
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
                        text: island.heldOsd?.value ?? ""
                        color: box.style.text
                        font.family: island.theme.tokens?.type.mono ?? ""
                        font.pixelSize: 12
                    }
                }
            }

            IslandPart {
                id: notePart
                shown: island.part === "notification"
                key: island.notification?.key ?? ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.notification[0]
                height: island.sizes.notification[1]

                Column {
                    id: card
                    x: 18
                    y: 14
                    width: parent.width - 36
                    spacing: 2

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: island.heldNotification?.app ?? ""
                        elide: Text.ElideRight
                        color: Qt.alpha(box.style.text, 0.65)
                        font.family: island.theme.tokens?.type.ui ?? ""
                        font.pixelSize: 12
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: island.heldNotification?.summary ?? ""
                        elide: Text.ElideRight
                        color: box.style.text
                        font.family: island.theme.tokens?.type.ui ?? ""
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: island.heldNotification?.body ?? ""
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

            IslandPart {
                id: monthPart
                shown: island.part === "calendar"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.calendar[0]
                height: island.sizes.calendar[1]

                Column {
                    id: month
                    x: 18
                    y: 16
                    width: parent.width - 36
                    spacing: 10

                    Item {
                        width: parent.width
                        height: monthTitle.implicitHeight

                        Text {
                            id: monthTitle
                            textFormat: Text.PlainText
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
            }

            IslandPart {
                id: askPart
                shown: island.part === "question"
                key: island.question?.id ?? ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.question[0]
                height: island.sizes.question[1]

                Column {
                    id: ask
                    x: 20
                    y: 16
                    width: parent.width - 40
                    spacing: 12

                    Item {
                        width: parent.width
                        height: where.implicitHeight

                        Text {
                            id: where
                            textFormat: Text.PlainText
                            width: parent.width - hint.implicitWidth - 12
                            elide: Text.ElideRight
                            text: [island.heldQuestion?.project, island.heldQuestion?.machine].filter(p => p).join(" · ")
                            color: Qt.alpha(box.style.text, 0.65)
                            font.family: island.theme.tokens?.type.mono ?? ""
                            font.pixelSize: 11
                        }

                        Text {
                            id: hint
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
                        text: island.heldQuestion?.text ?? ""
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
                            model: (island.heldQuestion?.options ?? []).slice(0, 9).concat(["Reply…"])

                            Rectangle {
                                required property string modelData
                                required property int index
                                readonly property bool isReply: index === Math.min(island.heldQuestion?.options.length ?? 0, 9)
                                width: Math.min(chip.implicitWidth + 24, ask.width)
                                height: chip.implicitHeight + 12
                                radius: 8
                                color: index === 0 && !isReply ? box.style.text : "transparent"
                                border.width: index === 0 && !isReply ? 0 : 1
                                border.color: Qt.alpha(box.style.text, 0.35)

                                Text {
                                    id: chip
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, parent.width - 24)
                                    elide: Text.ElideRight
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

        // A click opens a notification and a right click puts it away; the keyboard does the same through Mod+I.
        MouseArea {
            anchors.fill: parent
            enabled: island.mode === "notification"
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => mouse.button === Qt.RightButton ? island.putAway() : island.openNotification()
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
                if (island.mode === "notification") {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        island.openNotification();
                    else if (event.key === Qt.Key_D || event.key === Qt.Key_Escape)
                        island.putAway();
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
    }
}

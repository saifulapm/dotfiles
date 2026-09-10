import QtQuick
import "../components"
import "../../../components"
import "GoalsModel.js" as Model

// Goals panel — the editing surface for the one active goal, in the family's
// visual language: a hero of the mark over the goal and what is left of its
// deadline, the tasks as a tickable list, and the ledger of what has already
// shipped underneath.
//
// The deadline is set by DURATION, not by a date picker. Goals here are
// stated as "publish SplitRoute within 24 hours" and "Pawsome within 2 days",
// so the panel offers 24h / 2d / 1w and does the arithmetic. A calendar
// widget would be more general and strictly worse at the only job this has.
//
// Keys: s ships the active goal, e extends it by a day, n focuses the new
// goal field.
//
// Ship is deliberately NOT on Enter. It was, for about an hour on 2026-09-10,
// and it shipped two real goals inside 34 seconds the first time the panel was
// opened — Enter is the key you press reflexively in any panel, and this is
// the one action that clears the active goal out of the bar. A destructive-
// feeling action does not get the reflex key.
BarPanel {
    id: panel

    required property GoalsService goals

    panelTitle: ""
    cardWidth: theme.space(90)

    readonly property var active: goals.active
    readonly property bool hasActive: goals.hasActive

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_S:
            panel.goals.ship();
            break;
        case Qt.Key_E:
            panel.goals.extend(24 * 60 * 60 * 1000);
            break;
        case Qt.Key_N:
            newGoalField.takeFocus();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // -------------------------------------------------------------- the goal
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: panel.hasActive ? panel.active.name : "No active goal"
        meta: {
            if (!panel.hasActive)
                return panel.goals.shippedCount > 0 ? panel.goals.shippedCount + " shipped so far — start the next one below" : "Name one below and give it a deadline";
            const bits = [];
            if (panel.goals.totalCount > 0)
                bits.push(panel.goals.doneCount + " of " + panel.goals.totalCount + " done");
            if (panel.goals.timeLeftText !== "")
                bits.push(panel.goals.overdue ? panel.goals.timeLeftText.replace("-", "") + " overdue" : panel.goals.timeLeftText + " left");
            return bits.join(" · ");
        }
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0

        icon: OpticalGlyph {
            text: "󰣉" // md-bullseye-arrow
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.hasActive ? (panel.goals.overdue ? panel.theme.warn : panel.theme.textPrimary) : panel.theme.textMuted
            opacity: panel.hasActive ? 1.0 : 0.6
        }

        trailing: [
            // Shipping is not gated on every task being ticked — see the
            // service. The point of the button is to record the win.
            GlyphButton {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰄭" // md-check-all
                enabled: panel.hasActive
                hint: "Ship it — count the win"
                onActivated: panel.goals.ship()
            }
        ]
    }

    // The one piece of chrome that earns its pixels: a ratio is a number you
    // read, a bar is a thing you glance at.
    Rectangle {
        visible: panel.hasActive && panel.goals.totalCount > 0
        width: parent.width
        height: panel.theme.space(1)
        radius: height / 2
        color: panel.theme.surface2

        Rectangle {
            width: parent.width * panel.goals.ratio
            height: parent.height
            radius: parent.radius
            color: panel.goals.ratio >= 1 ? panel.theme.okColor : panel.theme.accent

            Behavior on width {
                NumberAnimation {
                    duration: panel.theme.motion.standard
                    easing.type: panel.theme.motion.easing
                }
            }
        }
    }

    // ------------------------------------------------------------- the tasks
    Column {
        visible: panel.hasActive
        width: parent.width
        spacing: panel.theme.space(0.5)

        Repeater {
            model: panel.hasActive ? panel.goals.rowsForActive() : []
            delegate: TaskRow {
                required property var modelData
                width: parent.width
                row: modelData
            }
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Small
            muted: true
            visible: panel.goals.totalCount === 0
            width: parent.width
            text: "No tasks yet. Break it into the smallest steps you can tick off — that is where the wins come from."
            wrapMode: Text.WordWrap
        }
    }

    PanelTextField {
        id: addTaskField
        visible: panel.hasActive
        theme: panel.theme
        width: parent.width
        placeholder: "Add a task…"
        onAccepted: {
            panel.goals.addTask(text);
            text = "";
        }
    }

    // Missing a deadline has to cost one click, not a rebuild. See the
    // model's extendDue for why this is deliberately frictionless.
    Row {
        visible: panel.hasActive
        width: parent.width
        spacing: panel.theme.space(1)

        StyledText {
            theme: panel.theme
            role: StyledText.Caption
            muted: true
            anchors.verticalCenter: parent.verticalCenter
            // A goal started from the queue can have no deadline yet, and
            // "Need longer" is the wrong question to ask about one that never
            // had a clock.
            text: !panel.goals.hasDeadline ? "No deadline — give it:" : (panel.goals.overdue ? "Ran over — give it:" : "Need longer:")
        }

        PanelButton {
            theme: panel.theme
            label: "+1h"
            onClicked: panel.goals.extend(60 * 60 * 1000)
        }

        PanelButton {
            theme: panel.theme
            label: "+1d"
            onClicked: panel.goals.extend(24 * 60 * 60 * 1000)
        }

        PanelButton {
            theme: panel.theme
            label: "+3d"
            onClicked: panel.goals.extend(3 * 24 * 60 * 60 * 1000)
        }

        // The same custom box as the new-goal row, aimed at the goal already
        // running. This is the one that matters most: a goal started from the
        // queue arrives with no clock, and picking its deadline is otherwise
        // limited to whatever the three presets happen to add up to.
        PanelTextField {
            id: extendHoursField
            theme: panel.theme
            anchors.verticalCenter: parent.verticalCenter
            width: panel.theme.space(14)
            implicitHeight: panel.theme.space(7)
            inputMargin: panel.theme.space(1.5)
            placeholder: "36"
            onAccepted: panel.extendByHours(extendHoursField.text)
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Caption
            muted: true
            anchors.verticalCenter: parent.verticalCenter
            text: "h"
        }
    }

    // Same tested parse as the new-goal box. On a goal that already has a
    // live deadline this ADDS to it (extendDue's rule), and on one with no
    // deadline it starts the clock from now — which is what "give it 36h"
    // means in both cases.
    function extendByHours(raw) {
        const ms = Model.parseHours(raw);
        if (ms <= 0)
            return;
        panel.goals.extend(ms);
        extendHoursField.text = "";
    }

    Separator {
        theme: panel.theme
    }

    // ------------------------------------------------------------- the queue
    Column {
        visible: panel.goals.queued.length > 0
        width: parent.width
        spacing: panel.theme.space(1)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "NEXT UP"
            value: panel.goals.queued.length + " WAITING"
        }

        Repeater {
            model: panel.goals.queued
            delegate: QueuedRow {
                required property var modelData
                width: parent.width
                goal: modelData
            }
        }
    }

    // ----------------------------------------------------------- a new goal
    Column {
        width: parent.width
        spacing: panel.theme.space(1)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "NEW GOAL"
            value: ""
        }

        PanelTextField {
            id: newGoalField
            theme: panel.theme
            width: parent.width
            placeholder: "What are you shipping?"
        }

        // The duration IS the deadline. A goal with no clock is a wish.
        Row {
            width: parent.width
            spacing: panel.theme.space(1)

            StyledText {
                theme: panel.theme
                role: StyledText.Caption
                muted: true
                anchors.verticalCenter: parent.verticalCenter
                text: "Due in:"
            }

            PanelButton {
                theme: panel.theme
                label: "24h"
                enabled: newGoalField.text.trim() !== ""
                onClicked: panel.createGoal(24 * 60 * 60 * 1000)
            }

            PanelButton {
                theme: panel.theme
                label: "2 days"
                enabled: newGoalField.text.trim() !== ""
                onClicked: panel.createGoal(2 * 24 * 60 * 60 * 1000)
            }

            PanelButton {
                theme: panel.theme
                label: "1 week"
                enabled: newGoalField.text.trim() !== ""
                onClicked: panel.createGoal(7 * 24 * 60 * 60 * 1000)
            }

            // Anything the presets do not cover, in hours — "36", "8", "72".
            // Hours rather than a date picker for the same reason the presets
            // are durations: a deadline here is always stated as "within N",
            // and the number is already in your head. Enter commits it.
            PanelTextField {
                id: customHoursField
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(14)
                implicitHeight: panel.theme.space(7)
                inputMargin: panel.theme.space(1.5)
                placeholder: "36"
                onAccepted: panel.createGoalFromHours(customHoursField.text)
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Caption
                muted: true
                anchors.verticalCenter: parent.verticalCenter
                text: "h"
            }
        }
    }

    // A new goal starts immediately only when nothing else is running —
    // otherwise it queues, because the one-at-a-time rule is the entire
    // reason this widget exists rather than a todo list.
    function createGoal(ms) {
        const name = newGoalField.text.trim();
        if (name === "")
            return false;
        const due = new Date(panel.goals.nowMs + ms).toISOString();
        panel.goals.addGoal(name, due, !panel.hasActive);
        newGoalField.text = "";
        return true;
    }

    // The parse lives in GoalsModel.parseHours, where it is tested — what
    // counts as a typed duration is a semantic, not a layout decision. 0 means
    // the box held nothing usable, and nothing happening beats creating a goal
    // with a deadline invented out of typing noise.
    function createGoalFromHours(raw) {
        const ms = Model.parseHours(raw);
        if (ms > 0 && panel.createGoal(ms))
            customHoursField.text = "";
    }

    // ------------------------------------------------------------ the ledger
    Separator {
        theme: panel.theme
        visible: panel.goals.shippedCount > 0
    }

    // The count is the headline and stays one — a growing number of wins is
    // the thing that makes the next deadline worth starting. The names below
    // it are rows rather than a joined string so a goal shipped by mistake
    // (or one worth running again) is one click from being active.
    Column {
        visible: panel.goals.shippedCount > 0
        width: parent.width
        spacing: panel.theme.space(1)

        Row {
            width: parent.width
            spacing: panel.theme.space(1)

            OpticalGlyph {
                text: "󰆥" // md-crown
                pixelSize: panel.theme.fontPx(1.083)
                verticalInkCenter: true
                anchors.verticalCenter: parent.verticalCenter
                color: panel.theme.okColor
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Small
                anchors.verticalCenter: parent.verticalCenter
                color: panel.theme.textPrimary
                text: "Shipped " + panel.goals.shippedCount
            }
        }

        // Capped: the ledger is a reminder of momentum, not an archive, and
        // an uncapped list would eventually own the whole panel.
        Repeater {
            model: panel.goals.shipped.slice(0, 5)
            delegate: ShippedRow {
                required property var modelData
                width: parent.width
                goal: modelData
            }
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true
        width: parent.width
        text: "One goal at a time. Right-click the bar icon to tick the next task without opening this."
        wrapMode: Text.WordWrap
    }

    // ------------------------------------------------------------- the rows
    component TaskRow: CursorSurface {
        id: taskRow

        theme: panel.theme

        property var row: null

        readonly property bool done: row ? row.taskDone === true : false
        readonly property bool isNext: row ? row.taskIsNext === true : false

        // "Next" is carried by the text colour alone — no fill, no outline.
        // A filled row reads as selected-and-waiting-on-you, which is wrong
        // for a list you scan top-down; the colour says the same thing
        // without boxing one line away from the rest.
        bordered: false
        implicitHeight: taskContent.implicitHeight + panel.theme.space(2)

        MouseArea {
            id: taskMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.goals.toggleTask(taskRow.row.taskId)
        }

        PanelHint {
            theme: panel.theme
            visible: taskMouse.containsMouse && !dropMouse.containsMouse
            anchor: taskRow
            above: true
            text: taskRow.done ? "Untick" : "Tick it off"
        }

        Item {
            id: taskContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(taskMark.implicitHeight, taskLabel.implicitHeight)

            // No left inset and no fixed glyph box: OpticalGlyph centers its
            // ink in whatever width it is given, so a space(4) box put half a
            // gutter in front of every circle on top of the row's own inset.
            // Flush left lines the marks up with the section headers and the
            // add-a-task field, which is the column the eye actually follows.
            OpticalGlyph {
                id: taskMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: taskRow.done ? "󰗠" // md-check-circle
                : "󰄰" // md-circle-outline
                verticalInkCenter: true
                pixelSize: panel.theme.fontPx(1.083)
                color: taskRow.done ? panel.theme.okColor : (taskRow.isNext || taskMouse.containsMouse ? panel.theme.accent : panel.theme.textMuted)
            }

            StyledText {
                id: taskLabel
                theme: panel.theme
                role: StyledText.Body
                anchors.left: taskMark.right
                anchors.right: dropTask.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: panel.theme.space(1.5)
                anchors.rightMargin: panel.theme.space(1)
                elide: Text.ElideRight
                // A ticked task stays legible but stops competing: this list
                // is read top-down for the next thing to do, and the one
                // thing to do next is the only line that gets the accent.
                color: taskRow.done ? panel.theme.textMuted : (taskRow.isNext ? panel.theme.accent : panel.theme.textPrimary)
                opacity: taskRow.done ? 0.7 : 1.0
                text: taskRow.row ? taskRow.row.taskText : ""
            }

            OpticalGlyph {
                id: dropTask
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "󰩹" // md-delete-outline
                verticalInkCenter: true
                pixelSize: panel.theme.fontPx(1.0)
                visible: taskMouse.containsMouse || dropMouse.containsMouse
                color: dropMouse.containsMouse ? panel.theme.error : panel.theme.textMuted

                MouseArea {
                    id: dropMouse
                    anchors.fill: parent
                    anchors.margins: -panel.theme.space(0.5)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.goals.removeTask(taskRow.row.taskId)
                }
            }
        }
    }

    // A win, and the undo for a mis-click on Ship. The check stays green
    // rather than turning into a play glyph on hover: this row is a record
    // first and a button second.
    component ShippedRow: CursorSurface {
        id: shippedRow

        theme: panel.theme

        property var goal: null

        bordered: false
        implicitHeight: shippedContent.implicitHeight + panel.theme.space(1.5)

        MouseArea {
            id: shippedMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.goals.startGoal(shippedRow.goal.id)
        }

        PanelHint {
            theme: panel.theme
            visible: shippedMouse.containsMouse
            anchor: shippedRow
            above: true
            text: "Start it again — it stops counting as shipped"
        }

        Item {
            id: shippedContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(shippedMark.implicitHeight, shippedLabel.implicitHeight)

            OpticalGlyph {
                id: shippedMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "󰗠" // md-check-circle
                verticalInkCenter: true
                pixelSize: panel.theme.fontPx(1.0)
                color: panel.theme.okColor
            }

            StyledText {
                id: shippedLabel
                theme: panel.theme
                role: StyledText.Small
                anchors.left: shippedMark.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: panel.theme.space(1.5)
                elide: Text.ElideRight
                color: shippedMouse.containsMouse ? panel.theme.accent : panel.theme.textMuted
                text: shippedRow.goal ? shippedRow.goal.name : ""
            }
        }
    }

    component QueuedRow: CursorSurface {
        id: queuedRow

        theme: panel.theme

        property var goal: null

        bordered: false
        implicitHeight: queuedContent.implicitHeight + panel.theme.space(2)

        MouseArea {
            id: queuedMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.goals.startGoal(queuedRow.goal.id)
        }

        PanelHint {
            theme: panel.theme
            visible: queuedMouse.containsMouse
            anchor: queuedRow
            above: true
            text: panel.hasActive ? "Start this instead — the current goal goes back to the queue" : "Start this one"
        }

        Item {
            id: queuedContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(queuedMark.implicitHeight, queuedLabel.implicitHeight)

            OpticalGlyph {
                id: queuedMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "󰐊" // md-play
                verticalInkCenter: true
                pixelSize: panel.theme.fontPx(1.083)
                color: queuedMouse.containsMouse ? panel.theme.accent : panel.theme.textMuted
            }

            StyledText {
                id: queuedLabel
                theme: panel.theme
                role: StyledText.Body
                anchors.left: queuedMark.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: panel.theme.space(1.5)
                elide: Text.ElideRight
                color: queuedMouse.containsMouse ? panel.theme.accent : panel.theme.textPrimary
                text: queuedRow.goal ? queuedRow.goal.name : ""
            }
        }
    }
}

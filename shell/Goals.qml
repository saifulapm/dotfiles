import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/goals.mjs" as G
import "lib/goals-view.mjs" as V
import "lib/surface.mjs" as S

// Active goals in your order with their tasks, then the done group; drawn in the Surfaces window, saved through the goals service.
Item {
    id: view

    required property var theme
    // The goals service; null until the Desk loads after the paper's first frame.
    required property var goals
    property bool shown: false
    property int selected: 0
    // Goal ids shown with their tasks; the window's own, never saved.
    property var unfolded: ({})
    property bool doneOpen: false
    // null, or {kind: title|deadline|task, edit, goal, title, prefill, error} while a prompt takes typing.
    property var prompt: null
    property bool confirm: false
    // Countdowns read from this, set on open and on each change.
    property real now: Date.now()
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var store: goals ? goals.store : G.emptyStore()
    readonly property var list: V.rows(store, unfolded, doneOpen, now)
    readonly property var row: list[selected] ?? null
    readonly property int count: G.activeGoals(store).length
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property bool caps: S.marginStyle(theme.tokens).caps
    readonly property bool capsTitles: theme.tokens ? theme.tokens.type.display === theme.tokens.type.mono : false

    onListChanged: selected = Math.max(0, Math.min(selected, list.length - 1))

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        now = Date.now();
        prompt = null;
        confirm = false;
        shown = true;
        keys.forceActiveFocus();
    }

    function close() {
        prompt = null;
        confirm = false;
        shown = false;
    }

    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function state() {
        return JSON.stringify({
            open: shown,
            selected: selected,
            rows: list.map(r => ({ kind: r.kind, id: r.id, text: r.text })),
            active: G.activeGoals(store).map(g => g.title),
            done: G.doneGoals(store).map(g => g.title),
            count: count,
            hint: count === 0 ? "n to add a goal" : "",
            prompt: prompt ? { kind: prompt.kind, text: input.text, error: prompt.error } : null,
            confirm: confirm,
            openMs: openMs,
            opens: opens,
            // The window has the keyboard; niri lists a layer Exclusive a moment before its keys arrive.
            keyboard: view.Window.active
        });
    }

    function save(next) {
        now = Date.now();
        return goals.save(next);
    }

    function select(kind, id) {
        const i = V.findRow(list, kind, id);
        if (i >= 0)
            selected = i;
    }

    function setUnfolded(id, on) {
        const next = Object.assign({}, unfolded);
        next[id] = on;
        unfolded = next;
    }

    function goalOf(id) {
        return store.goals.find(g => g.id === id);
    }

    function ask(p) {
        prompt = Object.assign({ edit: "", goal: "", title: "", prefill: "", error: "" }, p);
        input.text = p.prefill || "";
        input.forceActiveFocus();
    }

    function closePrompt() {
        prompt = null;
        keys.forceActiveFocus();
    }

    function move(by) {
        selected = Math.max(0, Math.min(list.length - 1, selected + by));
    }

    function fold() {
        if (row?.kind === "goal")
            setUnfolded(row.id, !unfolded[row.id]);
        else if (row?.kind === "done")
            doneOpen = !doneOpen;
    }

    function addTask() {
        if (row && row.kind !== "done")
            ask({ kind: "task", goal: row.goal });
    }

    function tick() {
        if (row?.kind === "task")
            save(G.toggleTask(store, row.goal, row.id, Date.now()));
        else if (row?.kind === "goal")
            save(G.toggleGoal(store, row.id, Date.now()));
    }

    function edit() {
        if (row?.kind === "task")
            ask({ kind: "task", goal: row.goal, edit: row.id, prefill: row.text });
        else if (row?.kind === "goal")
            ask({ kind: "title", edit: row.id, prefill: row.text });
    }

    function remove() {
        if (row?.kind === "task")
            save(G.deleteTask(store, row.goal, row.id, Date.now()));
        else if (row?.kind === "goal")
            save(G.deleteGoal(store, row.id, Date.now()));
    }

    // Only active goals reorder, and a task only within its goal; the moved row stays selected.
    function reorder(dir) {
        if (row?.kind === "task") {
            const r = row;
            save(G.moveTask(store, r.goal, r.id, dir, Date.now()));
            select("task", r.id);
        } else if (row?.kind === "goal" && !row.done) {
            const r = row;
            save(G.moveGoal(store, r.id, dir, Date.now()));
            select("goal", r.id);
        }
    }

    function submit() {
        const text = input.text;
        const t = Date.now();
        if (prompt.kind === "title") {
            if (!text.trim())
                return closePrompt();
            const g = prompt.edit ? goalOf(prompt.edit) : null;
            const prefill = g && g.deadline !== null ? Qt.formatDate(new Date(g.deadline), "yyyy-MM-dd") : "";
            return ask({ kind: "deadline", edit: prompt.edit, title: text, prefill: prefill });
        }
        if (prompt.kind === "deadline") {
            const g = prompt.edit ? goalOf(prompt.edit) : null;
            // An untouched prefill keeps the deadline as it was, which a typed 3d would not land on 23:59.
            const parsed = g && text === prompt.prefill ? { deadline: g.deadline } : G.parseDeadline(text, t);
            if (!parsed) {
                prompt = Object.assign({}, prompt, { error: "not a deadline: 3d, 5h or 2026-10-21" });
                return;
            }
            const id = g ? g.id : goals.newId();
            if (!save(g ? G.editGoal(store, id, prompt.title, parsed.deadline, t) : G.addGoal(store, prompt.title, parsed.deadline, t, id)))
                return;
            closePrompt();
            return select("goal", id);
        }
        if (!text.trim())
            return closePrompt();
        const goal = prompt.goal;
        const id = prompt.edit || goals.newId();
        if (!save(prompt.edit ? G.editTask(store, goal, id, text, t) : G.addTask(store, goal, text, t, id)))
            return;
        closePrompt();
        setUnfolded(goal, true);
        select("task", id);
    }

    Component.onCompleted: Root.State.loaded.push("goals")
    visible: shown

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            event.accepted = true;
            // While delete? y is up, any other key only cancels it.
            if (view.confirm) {
                view.confirm = false;
                if (event.key === Qt.Key_Y && event.text === "y")
                    view.remove();
                return;
            }
            const shift = event.modifiers & Qt.ShiftModifier;
            if (event.key === Qt.Key_J)
                shift ? view.reorder(1) : view.move(1);
            else if (event.key === Qt.Key_K)
                shift ? view.reorder(-1) : view.move(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                view.fold();
            else if (event.key === Qt.Key_N)
                view.ask({ kind: "title" });
            else if (event.key === Qt.Key_T)
                view.addTask();
            else if (event.key === Qt.Key_Space)
                view.tick();
            else if (event.key === Qt.Key_E)
                view.edit();
            else if (event.key === Qt.Key_D)
                view.confirm = view.row !== null && view.row.kind !== "done";
            else if (event.key === Qt.Key_Escape)
                view.close();
            else
                event.accepted = false;
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(c.paper, panel.style.wash)
        }

        Root.Surface {
            id: panel
            x: Math.round((parent.width - width) / 2)
            y: 104
            width: 680
            height: column.implicitHeight
            tokens: view.theme.tokens
            label: "Goals"

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22
                    Layout.rightMargin: 22
                    Layout.topMargin: 16
                    Layout.bottomMargin: 12
                    spacing: 14

                    Text {
                        id: heading
                        textFormat: Text.PlainText
                        text: "Goals"
                        color: c.ink
                        font.family: fonts.display
                        font.pixelSize: 28
                        font.capitalization: view.capsTitles ? Font.AllUppercase : Font.MixedCase
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.alignment: Qt.AlignBaseline
                        text: view.count + " active"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 13
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.line
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 6

                    Text {
                        visible: view.count === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.bottomMargin: 12
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: "n to add a goal"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 14
                    }

                    Repeater {
                        model: V.blocks(view.list)

                        Rectangle {
                            id: block
                            required property var modelData
                            readonly property var head: modelData.head
                            readonly property bool sel: view.selected >= modelData.row && view.selected <= modelData.row + modelData.tasks.length
                            readonly property var parts: head.kind === "goal" ? head.count.split("/").map(Number) : [0, 0]
                            Layout.fillWidth: true
                            implicitHeight: inner.implicitHeight + 24
                            radius: panel.style.corner.radius ? 8 : 0
                            color: sel && head.kind === "goal" ? c.surface : "transparent"
                            border.width: sel ? 2 : 0
                            border.color: c.accent

                            ColumnLayout {
                                id: inner
                                x: 14
                                y: 12
                                width: parent.width - 28
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: block.head.kind === "goal"
                                        elide: Text.ElideRight
                                        text: block.head.kind === "done" ? (view.doneOpen ? "▾ " : "▸ ") + block.head.text : block.head.text
                                        color: block.head.kind === "goal" && !block.head.done ? c.ink : c.muted
                                        font.family: block.head.kind === "done" ? fonts.mono : fonts.display
                                        font.pixelSize: block.head.kind === "done" ? 11 : 18
                                        font.capitalization: block.head.kind === "done" ? (view.caps ? Font.AllUppercase : Font.MixedCase) : view.capsTitles ? Font.AllUppercase : Font.MixedCase
                                        font.letterSpacing: block.head.kind === "done" ? 1.2 : 0
                                    }
                                    Text {
                                        visible: block.head.kind === "goal"
                                        textFormat: Text.PlainText
                                        text: block.head.count ?? ""
                                        color: c.muted
                                        font.family: fonts.mono
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        visible: block.head.kind === "goal"
                                        textFormat: Text.PlainText
                                        text: block.head.due ?? ""
                                        color: block.sel ? c.danger : c.muted
                                        font.family: fonts.mono
                                        font.pixelSize: 12
                                        font.capitalization: view.caps ? Font.AllUppercase : Font.MixedCase
                                        font.letterSpacing: view.caps ? 1.2 : 0
                                    }
                                }

                                // The selected goal's share of ticked tasks.
                                Rectangle {
                                    visible: block.sel && block.head.kind === "goal" && block.parts[1] > 0
                                    Layout.fillWidth: true
                                    implicitHeight: 4
                                    radius: panel.style.corner.radius ? 2 : 0
                                    color: c.line

                                    Rectangle {
                                        width: parent.width * block.parts[0] / Math.max(1, block.parts[1])
                                        height: parent.height
                                        radius: parent.radius
                                        color: c.accent
                                    }
                                }

                                Repeater {
                                    model: block.modelData.tasks

                                    Text {
                                        required property var modelData
                                        readonly property bool on: view.selected === modelData.row
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 4
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        text: (modelData.done ? "✓ " : "○ ") + modelData.text
                                        font.strikeout: modelData.done
                                        color: on ? c.accent : modelData.done ? c.muted : c.ink
                                        font.family: fonts.ui
                                        font.pixelSize: 14
                                        font.weight: on ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }

                // The prompt for a title, a deadline or a task; Enter takes it, Esc drops it.
                RowLayout {
                    visible: view.prompt !== null || view.confirm
                    Layout.fillWidth: true
                    Layout.leftMargin: 22
                    Layout.rightMargin: 22
                    Layout.bottomMargin: 12
                    spacing: 10

                    Text {
                        textFormat: Text.PlainText
                        text: view.confirm ? "delete? y" : !view.prompt ? "" : view.prompt.kind === "deadline" ? "deadline (3d, 5h, 2026-10-21 or empty)" : view.prompt.kind === "task" ? "task" : "goal"
                        color: view.confirm ? c.danger : c.muted
                        font.family: fonts.ui
                        font.pixelSize: 13
                    }
                    TextInput {
                        id: input
                        visible: view.prompt !== null
                        Layout.fillWidth: true
                        color: c.ink
                        font.family: fonts.ui
                        font.pixelSize: 14
                        clip: true
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape)
                                view.closePrompt();
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                view.submit();
                            else
                                return;
                            event.accepted = true;
                        }
                    }
                    Text {
                        visible: (view.prompt?.error ?? "") !== ""
                        textFormat: Text.PlainText
                        text: view.prompt?.error ?? ""
                        color: c.danger
                        font.family: fonts.ui
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.line
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22
                    Layout.rightMargin: 22
                    Layout.topMargin: 11
                    Layout.bottomMargin: 12
                    spacing: 14

                    Repeater {
                        model: ["j/k", "↵ fold", "n goal", "t task", "␣ tick", "e edit", "d delete", "J/K reorder"]

                        Text {
                            required property string modelData
                            textFormat: Text.PlainText
                            text: modelData
                            color: c.muted
                            font.family: fonts.mono
                            font.pixelSize: 11
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: "Esc"
                        color: c.muted
                        font.family: fonts.mono
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}

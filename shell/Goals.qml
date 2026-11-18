import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/goals.mjs" as G
import "lib/goals-view.mjs" as V
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T

// Active goals in your order with their tasks, then the done group; drawn inside the island on its fill (board 8), saved through the goals service.
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
    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, the tones lifted to read on it, and board 8's tile, selected tile and chip.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property color muted: tones.muted
    readonly property color danger: tones.danger
    readonly property color tile: Qt.alpha(on, 0.07)
    readonly property color sel: Qt.alpha(on, 0.12)
    readonly property color circle: Qt.alpha(on, 0.12)
    // The island reports this as its surface while Goals shows, and grows to this width for it (board 8).
    readonly property string name: "goals"
    readonly property int wantWidth: 640
    // True once the island has come to rest on Goals; the surfaces' window sets it.
    property bool settled: false
    implicitHeight: panel.height

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

    // The prompt row stays drawn through the close; open() clears it.
    function close() {
        shown = false;
    }

    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    // An item's box in the window's pixels.
    function box(item) {
        const p = item.mapToItem(null, 0, 0);
        return { x: p.x, y: p.y, w: item.width, h: item.height };
    }

    function state() {
        return JSON.stringify({
            open: shown,
            selected: selected,
            rows: list.map(r => ({ kind: r.kind, id: r.id, text: r.text, done: r.done })),
            active: G.activeGoals(store).map(g => g.title),
            done: G.doneGoals(store).map(g => g.title),
            count: count,
            empty: emptyLoader.item ? emptyLoader.item.text : null,
            prompt: prompt ? { kind: prompt.kind, text: input.text, error: prompt.error } : null,
            confirm: confirm,
            // Each goal tile and the done row as drawn, top to bottom: its fill, its chip and its tasks' checkboxes.
            blocks: Array.from({ length: blockRepeater.count }, (_, i) => blockRepeater.itemAt(i)?.item).filter(b => b).map(b => b.drawn()),
            heading: { text: heading.text, color: String(heading.color), box: box(heading) },
            confirmLabel: confirm ? { text: promptLabel.text, color: String(promptLabel.color), box: box(promptLabel) } : null,
            // The island's ink and fill, its tones, and the tile fills the blocks draw in.
            on: String(on),
            fill: String(fill),
            muted: String(muted),
            danger: String(danger),
            tile: String(tile),
            sel: String(sel),
            openMs: openMs,
            opens: opens,
            settled: view.settled,
            drawing: view.visible,
            cardBox: panel.drawnBox(),
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

    // The heading's +: a new goal, as n starts one.
    function newGoal() {
        if (!confirm && prompt === null)
            ask({ kind: "title" });
    }

    function move(by) {
        selected = Math.max(0, Math.min(list.length - 1, selected + by));
    }

    // A click selects the row under it, then a goal or done heading folds as Enter does and a task ticks as Space does.
    function clickRow(index) {
        // While delete? or a prompt asks, the keys answer only it, so a row takes no click.
        if (confirm || prompt !== null)
            return;
        selected = index;
        if (row?.kind === "task")
            tick();
        else
            fold();
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

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            event.accepted = true;
            // While the delete question is up, y deletes and any other key only cancels it.
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

        Root.Surface {
            id: panel
            width: parent.width
            height: column.implicitHeight + 32
            tokens: view.theme.tokens
            // The island draws the fill and plays the open.
            bare: true

            Column {
                id: column
                x: 16
                y: 16
                width: parent.width - 32
                spacing: 8

                Item {
                    width: column.width
                    height: 36

                    Text {
                        id: heading
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "Goals"
                        color: view.on
                        font.family: view.fonts.ui ?? ""
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }

                    // A new goal, as n starts one.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        radius: 16
                        color: view.tile

                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: String.fromCodePoint(0xF0415)
                            color: view.on
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 15
                        }
                        Root.Click {
                            name: "goals-new"
                            onTapped: view.newGoal()
                        }
                    }
                }

                Loader {
                    id: emptyLoader
                    width: column.width
                    active: view.list.length === 0
                    sourceComponent: Text {
                        topPadding: 12
                        bottomPadding: 12
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: "No goals yet"
                        color: view.muted
                        font.family: view.fonts.ui ?? ""
                        font.pixelSize: 13
                    }
                }

                // A goal's tile or the done row, each built only as its kind.
                Repeater {
                    id: blockRepeater
                    model: V.blocks(view.list)

                    Loader {
                        id: blockLoader
                        required property var modelData
                        width: column.width
                        sourceComponent: modelData.head.kind === "done" ? doneRow : goalTile

                        Component {
                            id: goalTile
                            GoalTile {
                                block: blockLoader.modelData
                            }
                        }
                        Component {
                            id: doneRow
                            DoneRow {
                                block: blockLoader.modelData
                            }
                        }
                    }
                }

                // The prompt for a title, a deadline or a task, or the delete question; Enter takes it, Esc drops it.
                RowLayout {
                    visible: view.prompt !== null || view.confirm
                    width: column.width
                    height: 36
                    spacing: 10

                    Text {
                        id: promptLabel
                        Layout.leftMargin: 14
                        textFormat: Text.PlainText
                        text: view.confirm ? "Delete “" + (view.row?.text ?? "") + "”?" : !view.prompt ? "" : view.prompt.kind === "deadline" ? "Deadline (3d, 5h, 2026-10-21 or empty)" : view.prompt.kind === "task" ? "Task" : "Goal"
                        color: view.confirm ? view.danger : view.muted
                        font.family: view.fonts.ui ?? ""
                        font.pixelSize: 13
                    }
                    TextInput {
                        id: input
                        visible: view.prompt !== null
                        Layout.fillWidth: true
                        color: view.on
                        selectionColor: Qt.alpha(view.on, 0.3)
                        font.family: view.fonts.ui ?? ""
                        font.pixelSize: 13
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
                        Layout.rightMargin: 14
                        textFormat: Text.PlainText
                        text: view.prompt?.error ?? ""
                        color: view.danger
                        font.family: view.fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    // A goal: its title bold with its deadline chip at the right, then its tasks when unfolded; the tile holding the selection is lighter.
    component GoalTile: Rectangle {
        id: tileItem
        required property var block
        readonly property var head: block.head
        readonly property bool holdsSelection: view.selected >= block.row && view.selected <= block.row + block.tasks.length

        function drawn() {
            const tasks = [];
            for (let i = 0; i < taskRepeater.count; i++)
                tasks.push(taskRepeater.itemAt(i).drawn());
            return { kind: "goal", text: title.text, color: String(color), box: view.box(tileItem), chip: chipLoader.item ? chipLoader.item.drawn() : null, tasks: tasks };
        }

        implicitHeight: tileColumn.implicitHeight + 24
        radius: 14
        color: holdsSelection ? view.sel : view.tile

        Column {
            id: tileColumn
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 4

            Item {
                width: tileColumn.width
                height: 26

                Text {
                    id: title
                    anchors.left: parent.left
                    anchors.right: chipLoader.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: tileItem.head.text
                    color: tileItem.head.done ? view.muted : view.on
                    font.family: view.fonts.ui ?? ""
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Loader {
                    id: chipLoader
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    active: tileItem.head.chip !== null
                    sourceComponent: Rectangle {
                        id: chip
                        function drawn() {
                            return { text: chipText.text, color: String(chipText.color), glyph: chipGlyph.text.codePointAt(0), box: view.box(chip) };
                        }
                        width: chipRow.implicitWidth + 18
                        height: 22
                        radius: 11
                        color: view.circle

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                id: chipGlyph
                                textFormat: Text.PlainText
                                text: String.fromCodePoint(0xF00ED)
                                color: chipText.color
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 11
                            }
                            Text {
                                id: chipText
                                textFormat: Text.PlainText
                                text: tileItem.head.chip ?? ""
                                color: tileItem.head.chipTone === "danger" ? view.danger : view.muted
                                font.family: view.fonts.ui ?? ""
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Root.Click {
                    name: "goals-row:" + tileItem.block.row
                    onTapped: view.clickRow(tileItem.block.row)
                }
            }

            Repeater {
                id: taskRepeater
                model: tileItem.block.tasks

                // A task: a 16 px round checkbox, filled with the ink and a check once done, and its text, struck through when done.
                Rectangle {
                    id: taskRow
                    required property var modelData
                    function drawn() {
                        return {
                            text: label.text,
                            done: modelData.done,
                            check: { w: check.width, h: check.height, radius: check.radius, color: String(check.color), ring: String(check.border.color), ringWidth: check.border.width, glyph: checkGlyph.item ? checkGlyph.item.text.codePointAt(0) : null, box: view.box(check) },
                            strike: label.font.strikeout,
                            ink: String(label.color)
                        };
                    }
                    x: -6
                    width: tileColumn.width + 12
                    height: 28
                    radius: 8
                    color: view.selected === modelData.row ? view.tile : "transparent"

                    Rectangle {
                        id: check
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 8
                        color: taskRow.modelData.done ? view.on : "transparent"
                        border.width: taskRow.modelData.done ? 0 : 1.5
                        border.color: view.muted

                        Loader {
                            id: checkGlyph
                            anchors.centerIn: parent
                            active: taskRow.modelData.done
                            sourceComponent: Text {
                                textFormat: Text.PlainText
                                text: String.fromCodePoint(0xF012C)
                                color: view.fill
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 11
                            }
                        }
                    }
                    Text {
                        id: label
                        anchors.left: check.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: taskRow.modelData.text
                        font.strikeout: taskRow.modelData.done
                        color: taskRow.modelData.done ? view.muted : view.on
                        font.family: view.fonts.ui ?? ""
                        font.pixelSize: 13
                    }

                    Root.Click {
                        name: "goals-row:" + taskRow.modelData.row
                        onTapped: view.clickRow(taskRow.modelData.row)
                    }
                }
            }
        }
    }

    // The done goals, folded behind a chevron at the bottom.
    component DoneRow: Rectangle {
        id: doneItem
        required property var block

        function drawn() {
            return { kind: "done", text: doneText.text, glyph: chevron.text.codePointAt(0), color: String(color), box: view.box(doneItem) };
        }

        implicitHeight: 40
        radius: 12
        color: view.selected === block.row ? view.tile : "transparent"

        Row {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                id: chevron
                textFormat: Text.PlainText
                text: String.fromCodePoint(view.doneOpen ? 0xF0140 : 0xF0142)
                color: view.muted
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 13
            }
            Text {
                id: doneText
                textFormat: Text.PlainText
                text: doneItem.block.head.text
                color: view.muted
                font.family: view.fonts.ui ?? ""
                font.pixelSize: 13
            }
        }

        Root.Click {
            name: "goals-row:" + doneItem.block.row
            onTapped: view.clickRow(doneItem.block.row)
        }
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "." as Root
import "lib/voice.mjs" as L
import "lib/accounts.mjs" as A

// Claude accounts with their limits, then balances and usage, from dots-accounts' rows; the collector runs only when the card opens or on r.
Item {
    id: panel

    required property var theme
    property bool shown: false
    property int opens: 0
    property var openMs: null
    // The open's first frame, the card drawn with or without its rows: the open Saiful's budget times (#166PQ300).
    property var cardMs: null
    // When the open being timed was requested, or -1 once its first frame with rows is swapped.
    property real openT0: -1
    // True once this open's rows are in: the cache's answer, or the rows a fetch still running at the open had drawn.
    property bool rowsIn: false
    property string registryText: ""
    property string rowsText: "[]"
    // The cursor's place among the rows it stops on.
    property int selected: 0
    readonly property bool busy: registryReader.running || cachedReader.running || fetcher.running || user.running || registryRereader.running
    readonly property string dotsBin: Quickshell.shellDir + "/../bin/dots"

    readonly property string command: Quickshell.env("DOTS_ACCOUNTS") || Quickshell.shellDir + "/../bin/dots-accounts"
    readonly property string registryPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/claude-accounts.json"
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property var marks: A.accountsLook(theme.tokens ?? { color: {} })
    readonly property var view: A.accountsView(registryText, rowsText, Date.now(), fetcher.running)
    readonly property var items: A.accountsItems(view)
    readonly property var stops: items.map((it, i) => it.stop ? i : -1).filter(i => i >= 0)
    readonly property int current: stops.length ? stops[Math.min(selected, stops.length - 1)] : -1
    readonly property var activeAccount: view.accounts.find(a => a.active) ?? null
    readonly property Root.Motion motion: Root.Motion {
        shown: panel.shown
        tokens: panel.theme.tokens
    }

    // A second open while a fetch runs leaves that fetch to finish and starts none.
    function open(t0) {
        openT0 = t0;
        openMs = null;
        cardMs = null;
        opens += 1;
        selected = 0;
        rowsIn = busy;
        if (!busy)
            registryReader.running = true;
        shown = true;
        keyTarget.forceActiveFocus();
    }

    // A fetch that is running finishes within its 10 s limit: killing node would orphan codex's process group.
    function close() {
        shown = false;
    }

    function refresh() {
        if (!busy)
            fetcher.running = true;
    }

    // dots claude-account is the registry's only writer, so ACTIVE moves only once it has written and the registry is read again.
    function use() {
        const id = A.useTarget(items[current]);
        if (!id || user.running)
            return;
        user.account = id;
        user.label = items[current].label;
        user.command = [dotsBin, "claude-account", "use", id];
        user.running = true;
    }

    // Called on each of the host window's frames; the first one drawn with this open's rows ends the timing.
    function swapped() {
        if (shown && openT0 >= 0 && cardMs === null)
            cardMs = Date.now() - openT0;
        if (shown && openT0 >= 0 && rowsIn) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function move(by) {
        selected = Math.max(0, Math.min(stops.length - 1, selected + by));
    }

    // A click on a row the cursor stops on moves it there and does what Enter does; a group or limit row takes none.
    function clickRow(i) {
        const s = stops.indexOf(i);
        if (s < 0)
            return;
        selected = s;
        use();
    }

    // Rows that will not parse as a list keep the ones drawn.
    function take(text) {
        if (text.trim().charAt(0) === "[")
            rowsText = text;
        rowsIn = true;
    }

    function state() {
        const groups = [];
        const rows = [];
        for (let i = 0; i < rowRepeater.count; i++) {
            const row = rowRepeater.itemAt(i);
            if (row.isGroup)
                groups.push(row.drawnGroup());
            else
                rows.push(row.drawn());
        }
        const keys = [];
        for (let i = 0; i < keyRepeater.count; i++)
            keys.push((keyRepeater.itemAt(i).keyLabel + " " + keyRepeater.itemAt(i).wordLabel).trim());
        const limit = l => ({ name: l.name, figure: l.figure, reset: l.reset, warning: l.warning });
        const other = r => ({ label: r.label, figure: r.figure, note: r.note, warning: r.warning, error: r.error });
        return JSON.stringify({
            loaded: true,
            open: shown,
            visible: panel.visible,
            drawing: panel.visible,
            busy: busy,
            accounts: view.accounts.map(a => ({ id: a.id, label: a.label, plan: a.plan, active: a.active, note: a.note, limits: a.limits.map(limit) })),
            balances: view.balances.map(other),
            usage: view.usage.map(other),
            groups: groups,
            rows: rows,
            selected: current >= 0 ? items[current].kind + ":" + items[current].label : "",
            footer: footerLine.text,
            hint: keys.join(" · "),
            openMs: openMs,
            cardMs: cardMs,
            opens: opens,
            settled: motion.settled,
            cardBox: card.drawnBox(),
            keyboard: panel.Window.active
        });
    }

    Process {
        id: registryReader
        command: ["cat", panel.registryPath]
        stdout: StdioCollector {
            id: registryOut
        }
        // No registry file reads as empty, which the view takes as the one account main.
        onExited: {
            panel.registryText = registryOut.text;
            cachedReader.running = true;
        }
    }

    // The cache answers in milliseconds, so the card draws the last numbers at once and the full fetch redraws them.
    Process {
        id: cachedReader
        command: [panel.command, "--cached"]
        stdout: StdioCollector {
            id: cachedOut
        }
        // A card closed while the cache was read, as by a quick second Mod+U, starts no fetch.
        onExited: {
            panel.take(cachedOut.text);
            if (panel.shown)
                fetcher.running = true;
        }
    }

    Process {
        id: fetcher
        command: [panel.command]
        stdout: StdioCollector {
            id: fetchOut
        }
        onExited: panel.take(fetchOut.text)
    }

    Process {
        id: user
        property string account: ""
        property string label: ""
        onExited: code => {
            registryRereader.used = code === 0;
            registryRereader.running = true;
        }
    }

    // A refused use leaves the registry as it was, so ACTIVE stays where it names and the island says nothing.
    Process {
        id: registryRereader
        property bool used: false
        command: ["cat", panel.registryPath]
        stdout: StdioCollector {
            id: rereadOut
        }
        onExited: {
            panel.registryText = rereadOut.text;
            if (used && panel.activeAccount && panel.activeAccount.id === user.account)
                panel.theme.notice(A.activeNotice(user.label));
        }
    }

    Component.onCompleted: Root.State.loaded.push("accounts")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "accounts")

    visible: motion.drawing

    // Holds the keyboard while the card shows: j and k move between account and provider rows, r fetches again.
    Item {
        id: keyTarget
        Keys.onPressed: event => {
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                panel.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                panel.move(-1);
            else if (event.key === Qt.Key_R)
                panel.refresh();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                panel.use();
            else if (event.key === Qt.Key_Escape)
                panel.close();
            else
                return;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: card.wash
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: Math.max(24, Math.min(100, Math.round((parent.height - height) / 2)))
        width: 640
        height: column.implicitHeight
        tokens: panel.theme.tokens
        motion: panel.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            // The heading in the launcher's pill, and the key across from it.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                spacing: 12

                Rectangle {
                    implicitWidth: heading.implicitWidth + 18
                    implicitHeight: heading.implicitHeight + 6
                    radius: 8
                    color: look.label.fill
                    Text {
                        id: heading
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: look.heading("accounts", "")
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        font.letterSpacing: 0
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    implicitWidth: headRight.implicitWidth + 18
                    implicitHeight: headRight.implicitHeight + 6
                    radius: 8
                    color: look.tile.fill
                    Text {
                        id: headRight
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "Mod+U"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.letterSpacing: 0
                    }
                }
            }

            Rule {}

            Column {
                id: list
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: 4
                Layout.bottomMargin: 8

                Repeater {
                    id: rowRepeater
                    model: panel.items

                    Rectangle {
                        id: rowItem
                        required property var modelData
                        required property int index
                        // A click on the row does what Enter does on it.
                        Root.Click {
                            name: "accounts-row:" + rowItem.it.kind + ":" + rowItem.it.label
                            onTapped: panel.clickRow(rowItem.index)
                        }
                        readonly property var it: modelData
                        readonly property bool isGroup: it.kind === "group"
                        readonly property bool isLimit: it.kind === "limit"
                        // The note's box shows on this, never on its own Text: a child's visible stays false while its parent hides, so the box never came back once the card had closed.
                        readonly property bool hasNote: !isGroup && !isLimit && (it.note || "") !== ""
                        readonly property bool isAccount: it.kind === "account"
                        readonly property bool isCurrent: index === panel.current
                        readonly property string fig: isGroup || isAccount ? "" : marks.figure(it)
                        readonly property bool warn: !!it.warning
                        readonly property color ink: isCurrent ? look.cursor.text : it.dim ? marks.dim : c.ink
                        readonly property color quiet: isCurrent ? look.cursor.detail : marks.dim
                        // The row as drawn, for the state function.
                        function drawn() {
                            return {
                                kind: it.kind,
                                name: nameText.text,
                                plan: isAccount && resetUnder.visible ? resetUnder.text : "",
                                active: activeMark.visible ? activeText.text : "",
                                figure: figure.visible ? figMain.text : "",
                                reset: resetText.visible ? resetText.text : !isAccount && resetUnder.visible ? resetUnder.text : "",
                                note: noteText.visible ? noteText.text : "",
                                warning: triangle.visible,
                                lines: nameText.lineCount,
                                elided: nameText.truncated,
                                figureElided: figMain.truncated,
                                noteCut: noteText.visible && (noteText.x < 0 || noteText.x + noteText.width > noteBox.width + 0.5),
                                noteElided: noteText.visible && noteText.truncated,
                                // The farthest right any drawn text of the row reaches, in the window, to compare with cardBox.
                                right: [nameText, noteText, figMain, resetText, activeMark].filter(t => t.visible).reduce((m, t) => Math.max(m, t.mapToItem(null, t.width, 0).x), 0)
                            };
                        }
                        function drawnGroup() {
                            const a = groupText.mapToItem(null, 0, 0);
                            return { text: groupText.text, x: a.x, y: a.y, w: groupText.width * card.scale, h: groupText.height * card.scale };
                        }

                        width: list.width
                        implicitHeight: isGroup ? groupRow.implicitHeight + (it.label === "Claude" ? 14 : 20) : row.implicitHeight + (isLimit ? 12 : 10)
                        radius: look.cursor.radius
                        color: isCurrent ? look.cursor.fill : "transparent"

                        // A group label in the plain word.
                        RowLayout {
                            id: groupRow
                            visible: rowItem.isGroup
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            anchors.leftMargin: 12
                            anchors.rightMargin: anchors.leftMargin

                            Text {
                                id: groupText
                                textFormat: Text.PlainText
                                text: rowItem.isGroup ? rowItem.it.label : ""
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: 0
                            }
                        }

                        RowLayout {
                            id: row
                            visible: !rowItem.isGroup
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: anchors.leftMargin
                            spacing: 10

                            // A 32 px tile: a person for an account, a provider's initials for the rest; its limits sit indented under it.
                            Rectangle {
                                implicitWidth: rowItem.isLimit ? 34 : look.tile.size
                                implicitHeight: rowItem.isLimit ? 1 : look.tile.size
                                radius: look.tile.radius
                                color: rowItem.isLimit ? "transparent" : rowItem.isCurrent ? c.surface : look.tile.fill
                                Text {
                                    visible: !rowItem.isLimit && !rowItem.isAccount
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: rowItem.it.label ? rowItem.it.label.charAt(0) + (rowItem.it.label.split(" ")[1] || rowItem.it.label.slice(1, 2)).charAt(0) : ""
                                    color: c.muted
                                    font.family: fonts.ui
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                                Shape {
                                    visible: rowItem.isAccount
                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        strokeColor: rowItem.isCurrent ? look.cursor.text : c.muted
                                        strokeWidth: 1.5
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        startX: 18.7
                                        startY: 13.5
                                        PathArc {
                                            x: 13.3
                                            y: 13.5
                                            radiusX: 2.7
                                            radiusY: 2.7
                                        }
                                        PathArc {
                                            x: 18.7
                                            y: 13.5
                                            radiusX: 2.7
                                            radiusY: 2.7
                                        }
                                        PathMove {
                                            x: 10.8
                                            y: 21.5
                                        }
                                        PathQuad {
                                            x: 21.2
                                            y: 21.5
                                            controlX: 16
                                            controlY: 14
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: rowItem.isLimit ? 92 : -1
                                Layout.fillWidth: !rowItem.isLimit
                                spacing: 0

                                Text {
                                    id: nameText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: rowItem.isLimit ? marks.limitName(rowItem.it.name) : rowItem.it.label || ""
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: rowItem.isLimit ? rowItem.quiet : rowItem.isCurrent ? look.cursor.text : rowItem.ink
                                    font.family: fonts.ui
                                    font.pixelSize: rowItem.isLimit ? 12 : !rowItem.isAccount ? 14 : 15
                                    font.weight: rowItem.isLimit ? Font.Normal : Font.Medium
                                    font.letterSpacing: 0
                                }
                                // The plan under an account's name, the reset under a usage row's.
                                Text {
                                    id: resetUnder
                                    visible: (rowItem.isAccount || rowItem.it.kind === "usage") && text !== ""
                                    textFormat: Text.PlainText
                                    text: rowItem.isAccount ? rowItem.it.plan : rowItem.it.reset || ""
                                    color: c.muted
                                    font.family: fonts.ui
                                    font.pixelSize: 11
                                }
                            }

                            // A rounded 6 px bar.
                            Item {
                                id: bar
                                readonly property real fraction: rowItem.it.fraction ?? 0
                                readonly property color fill: rowItem.warn ? marks.warn : rowItem.it.dim ? marks.dim : marks.bar.fill
                                visible: !rowItem.isGroup && !rowItem.isAccount && rowItem.it.fraction !== null && rowItem.it.fraction !== undefined
                                Layout.fillWidth: rowItem.isLimit
                                Layout.preferredWidth: rowItem.isLimit ? -1 : 120
                                implicitHeight: 6

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 3
                                    color: marks.bar.track
                                    Rectangle {
                                        width: parent.width * bar.fraction
                                        height: parent.height
                                        radius: 3
                                        color: bar.fill
                                    }
                                }
                            }

                            // A stale account's line, or a provider's stale time or failure; a failure speaks in the danger token.
                            Item {
                                id: noteBox
                                visible: rowItem.hasNote
                                // Fixed at its text's width up to a cap, so the figure gives way to it, never the other way; an account's line says what to do and may run longer. Past the cap it ends in an ellipsis.
                                Layout.preferredWidth: Math.min(implicitWidth, rowItem.isAccount ? 360 : 200)
                                implicitWidth: noteText.implicitWidth
                                implicitHeight: noteText.implicitHeight
                                Text {
                                    id: noteText
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, parent.width)
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: rowItem.it.note || ""
                                    color: rowItem.it.error ? marks.warn : rowItem.isCurrent ? look.cursor.detail : marks.dim
                                    font.family: fonts.ui
                                    font.pixelSize: 12
                                }
                            }

                            // The figure at the right: from 80% used it takes the danger token, a bolder weight and a small triangle.
                            Item {
                                id: figure
                                visible: rowItem.fig !== ""
                                // Its natural width gives way to a note or a long figure, so the row never runs past the card.
                                Layout.fillWidth: !rowItem.isLimit
                                Layout.preferredWidth: rowItem.isLimit ? 56 : figRow.implicitWidth
                                Layout.minimumWidth: 0
                                implicitHeight: figRow.implicitHeight
                                clip: true

                                Row {
                                    id: figRow
                                    // What the figure's text has once the triangle and the gap are taken.
                                    readonly property real room: Math.max(0, figure.width - (triangle.visible ? triangle.width + spacing : 0))
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Shape {
                                        id: triangle
                                        visible: rowItem.warn
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 14
                                        height: 14
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            strokeColor: marks.warn
                                            strokeWidth: 1.3
                                            fillColor: "transparent"
                                            joinStyle: ShapePath.RoundJoin
                                            startX: 7
                                            startY: 2
                                            PathLine {
                                                x: 13
                                                y: 12
                                            }
                                            PathLine {
                                                x: 1
                                                y: 12
                                            }
                                            PathLine {
                                                x: 7
                                                y: 2
                                            }
                                            PathMove {
                                                x: 7
                                                y: 5.6
                                            }
                                            PathLine {
                                                x: 7
                                                y: 8.6
                                            }
                                            PathMove {
                                                x: 7
                                                y: 10
                                            }
                                            PathLine {
                                                x: 7
                                                y: 10.4
                                            }
                                        }
                                    }
                                    Text {
                                        id: figMain
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, figRow.room)
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        text: rowItem.fig
                                        color: rowItem.warn ? marks.warn : rowItem.ink
                                        font.family: fonts.ui
                                        font.pixelSize: rowItem.isLimit ? 12 : 14
                                        font.weight: rowItem.warn ? Font.Bold : Font.Medium
                                    }
                                }
                            }

                            Item {
                                visible: !figure.visible
                                Layout.fillWidth: true
                            }

                            // ACTIVE as an ink chip with its dot.
                            Rectangle {
                                id: activeMark
                                visible: rowItem.isAccount && rowItem.it.active
                                implicitWidth: activeRow.implicitWidth + 18
                                implicitHeight: activeRow.implicitHeight + 6
                                radius: marks.active.radius
                                color: marks.active.fill
                                Row {
                                    id: activeRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: marks.active.dot
                                    }
                                    Text {
                                        id: activeText
                                        textFormat: Text.PlainText
                                        text: marks.active.text
                                        color: marks.active.color
                                        font.family: fonts.ui
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        font.letterSpacing: 0
                                    }
                                }
                            }

                            // A limit's reset at the row's end; a usage row's sits under its name.
                            Text {
                                id: resetText
                                visible: rowItem.isLimit
                                // A column when the row has room; when it has none, the column's slack goes to the figure, never the reset's own text.
                                Layout.fillWidth: true
                                Layout.preferredWidth: 112
                                Layout.maximumWidth: 112
                                Layout.minimumWidth: implicitWidth
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: rowItem.it.reset || ""
                                color: rowItem.warn ? marks.warn : rowItem.quiet
                                font.family: fonts.ui
                                font.pixelSize: 11
                                font.letterSpacing: 0
                            }
                        }
                    }
                }
            }

            Rule {}

            // When the rows were fetched, or that a fetch runs.
            Text {
                id: footerLine
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.topMargin: 9
                Layout.bottomMargin: 9
                textFormat: Text.PlainText
                text: view.footer
                color: c.muted
                font.family: look.small.font
                font.pixelSize: look.small.size
                font.letterSpacing: look.small.spacing
            }

            Rule {}

            // The key strip as Pass draws it, each pair in a chip.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: 10
                Layout.bottomMargin: Layout.topMargin
                spacing: 8

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        id: keyRepeater
                        model: A.accountsKeys(look)

                        Rectangle {
                            id: keyPair
                            required property var modelData
                            readonly property string keyLabel: keyText.text
                            readonly property string wordLabel: wordText.text
                            width: pair.implicitWidth + 14
                            height: pair.implicitHeight + 6
                            radius: 6
                            color: look.chip.fill

                            Row {
                                id: pair
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    id: keyText
                                    textFormat: Text.PlainText
                                    text: keyPair.modelData.key
                                    color: look.chip.key
                                    font.family: fonts.mono
                                    font.pixelSize: look.small.size
                                    font.letterSpacing: look.small.spacing
                                    font.bold: true
                                }
                                Text {
                                    id: wordText
                                    visible: text !== ""
                                    textFormat: Text.PlainText
                                    text: keyPair.modelData.word
                                    color: c.muted
                                    font.family: look.small.font
                                    font.pixelSize: look.small.size
                                    font.letterSpacing: look.small.spacing
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The 1 px slot between a card's parts; it draws no line, so the card reads as one piece.
    component Rule: Item {
        Layout.fillWidth: true
        implicitHeight: 1
    }
}

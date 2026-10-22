import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "." as Root
import "lib/voice.mjs" as L
import "lib/accounts.mjs" as A

// Claude accounts with their limits, then balances and usage, from dots-accounts' rows in each theme's voice; the collector runs only when the card opens or on r.
Item {
    id: panel

    required property var theme
    property bool shown: false
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1
    property string registryText: ""
    property string rowsText: "[]"
    // The cursor's place among the rows it stops on.
    property int selected: 0
    readonly property bool busy: registryReader.running || cachedReader.running || fetcher.running

    readonly property string command: Quickshell.env("DOTS_ACCOUNTS") || "dots-accounts"
    readonly property string registryPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/claude-accounts.json"
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property var marks: A.accountsLook(theme.tokens ?? { color: {}, type: { voice: "caps" } })
    readonly property var view: A.accountsView(registryText, rowsText, Date.now(), fetcher.running)
    readonly property var items: A.accountsItems(view)
    readonly property var stops: items.map((it, i) => it.stop ? i : -1).filter(i => i >= 0)
    readonly property int current: stops.length ? stops[Math.min(selected, stops.length - 1)] : -1
    readonly property var activeAccount: view.accounts.find(a => a.active) ?? null
    readonly property bool caps: look.voice === "caps"
    readonly property bool plain: look.voice === "plain"
    readonly property bool bracket: look.voice === "bracket"
    readonly property Root.Motion motion: Root.Motion {
        shown: panel.shown
        tokens: panel.theme.tokens
    }

    // A second open while a fetch runs leaves that fetch to finish and starts none.
    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        selected = 0;
        if (!busy)
            registryReader.running = true;
        shown = true;
        keyTarget.forceActiveFocus();
    }

    // A fetch that is running finishes on its own, so the collector never leaves its cache half written.
    function close() {
        shown = false;
    }

    function refresh() {
        if (!busy)
            fetcher.running = true;
    }

    // Called on each of the host window's frames; the first one after open() ends the timing.
    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function move(by) {
        selected = Math.max(0, Math.min(stops.length - 1, selected + by));
    }

    // Rows that will not parse as a list keep the ones drawn.
    function take(text) {
        if (text.trim().charAt(0) === "[")
            rowsText = text;
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
        const other = r => ({ label: r.label, figure: r.figure, note: r.note, warning: r.warning });
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
            footer: (caps ? stripFooter : footerLine).text,
            hint: keys.join(" · "),
            openMs: openMs,
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
        onExited: {
            panel.take(cachedOut.text);
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
            else if (event.key === Qt.Key_Escape)
                panel.close();
            else
                return;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(c.paper, card.style.wash)
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: Math.max(24, Math.min(100, Math.round((parent.height - height) / 2)))
        // Paper's board is 700 px wide, Artboard's 640 and Blueprint's 760.
        width: plain ? 640 : bracket ? 760 : 700
        height: column.implicitHeight
        tokens: panel.theme.tokens
        label: "Accounts"
        motion: panel.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            // The heading in the launcher's label idiom; Paper names the account cx starts in, the others the key.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: plain ? 18 : bracket ? 22 : 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: plain ? 16 : bracket ? 12 : 18
                Layout.bottomMargin: plain ? 16 : bracket ? 10 : 14
                spacing: 12

                Rectangle {
                    visible: look.label.kind !== "header"
                    implicitWidth: heading.implicitWidth + (plain ? 18 : 14)
                    implicitHeight: heading.implicitHeight + 6
                    radius: plain ? 8 : 0
                    color: look.label.fill
                    Text {
                        id: heading
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: look.heading("accounts", "")
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: plain ? 12 : 10
                        font.weight: plain ? Font.Medium : Font.Normal
                        font.letterSpacing: plain ? 0 : 1.4
                    }
                }

                Text {
                    visible: look.label.kind === "header"
                    textFormat: Text.PlainText
                    text: look.heading("accounts", "usage")
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    implicitWidth: headRight.implicitWidth + (plain ? 18 : 0)
                    implicitHeight: headRight.implicitHeight + (plain ? 6 : 0)
                    radius: 8
                    color: plain ? look.tile.fill : "transparent"
                    Text {
                        id: headRight
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: plain ? "Mod+U" : bracket ? "[MOD+U]" : "CX · " + (panel.activeAccount ? panel.activeAccount.label.toUpperCase() : "")
                        color: bracket ? c.accent : c.muted
                        font.family: fonts.ui
                        font.pixelSize: plain ? 11 : 10
                        font.weight: plain ? Font.Medium : bracket ? Font.Bold : Font.Normal
                        font.letterSpacing: plain ? 0 : 1.4
                    }
                }
            }

            Rule {}

            Column {
                id: list
                Layout.fillWidth: true
                Layout.leftMargin: caps ? 0 : bracket ? 10 : 8
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
                        readonly property var it: modelData
                        readonly property bool isGroup: it.kind === "group"
                        readonly property bool isLimit: it.kind === "limit"
                        readonly property bool isAccount: it.kind === "account"
                        readonly property bool isCurrent: index === panel.current
                        readonly property var group: isGroup ? marks.group([it.label, it.count]) : null
                        readonly property var fig: isGroup || isAccount ? null : marks.figure(it)
                        readonly property bool warn: !!it.warning
                        readonly property color ink: isCurrent ? look.cursor.text : it.dim ? marks.dim : c.ink
                        readonly property color quiet: isCurrent ? look.cursor.detail : marks.dim
                        // The row as drawn, for the state function.
                        function drawn() {
                            return {
                                kind: it.kind,
                                name: nameText.text,
                                plan: planText.visible ? planText.text : "",
                                active: activeMark.visible ? activeText.text : "",
                                figure: (figMain.visible ? figMain.text : "") + (figTail.visible ? " " + figTail.text : ""),
                                reset: resetText.visible ? resetText.text : resetUnder.visible ? resetUnder.text : "",
                                note: noteText.visible ? noteText.text : "",
                                warning: triangle.visible,
                                lines: nameText.lineCount,
                                elided: nameText.truncated
                            };
                        }
                        function drawnGroup() {
                            const a = groupText.mapToItem(null, 0, 0);
                            return { text: groupText.text, right: groupRight.text, x: a.x, y: a.y, w: groupText.width * card.scale, h: groupText.height * card.scale };
                        }

                        width: list.width
                        implicitHeight: isGroup ? groupRow.implicitHeight + (it.label === "Claude" ? 14 : 20) : row.implicitHeight + (isLimit ? (bracket ? 10 : 12) : plain ? 10 : bracket ? 14 : 16)
                        radius: look.cursor.radius
                        color: isCurrent ? look.cursor.fill : "transparent"

                        // A group label: Paper and Blueprint count the rows at the right, Artboard writes the plain word.
                        RowLayout {
                            id: groupRow
                            visible: rowItem.isGroup
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            anchors.leftMargin: caps ? 20 : 12
                            anchors.rightMargin: anchors.leftMargin

                            Text {
                                id: groupText
                                textFormat: Text.PlainText
                                text: rowItem.group ? rowItem.group.text : ""
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: plain ? 0 : 1.6
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                id: groupRight
                                textFormat: Text.PlainText
                                text: rowItem.group ? rowItem.group.right : ""
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: 1.6
                            }
                        }

                        RowLayout {
                            id: row
                            visible: !rowItem.isGroup
                            anchors.fill: parent
                            anchors.leftMargin: caps ? 20 : 12
                            anchors.rightMargin: anchors.leftMargin
                            spacing: plain ? 10 : 14

                            // Paper's cursor mark, Blueprint's row number; a limit row keeps the column empty.
                            Text {
                                visible: !plain
                                Layout.preferredWidth: bracket ? 22 : 10
                                textFormat: Text.PlainText
                                text: bracket ? (rowItem.it.stop ? look.number(panel.stops.indexOf(rowItem.index)) : "") : "▸"
                                color: bracket ? (rowItem.isCurrent ? look.cursor.text : c.muted) : rowItem.isCurrent ? look.cursor.marker : "transparent"
                                font.family: bracket ? look.name.font : fonts.ui
                                font.pixelSize: bracket ? 13 : 15
                                font.bold: bracket && rowItem.isCurrent
                            }

                            // Artboard's 32 px tile: a person for an account, a provider's initials for the rest; its limits sit indented under it.
                            Rectangle {
                                visible: plain
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
                                Layout.preferredWidth: rowItem.isLimit ? (plain ? 92 : bracket ? 118 : 102) : (plain ? -1 : 120)
                                Layout.fillWidth: plain && !rowItem.isLimit
                                Layout.leftMargin: rowItem.isLimit && caps ? 18 : 0
                                spacing: 0

                                Text {
                                    id: nameText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: rowItem.isLimit ? marks.limitName(rowItem.it.name) : marks.words(rowItem.it.label || "")
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: rowItem.isLimit ? (plain || bracket ? rowItem.quiet : rowItem.ink) : rowItem.isCurrent && plain ? look.cursor.text : rowItem.ink
                                    font.family: fonts.ui
                                    font.pixelSize: rowItem.isLimit ? (plain ? 12 : 13) : plain && !rowItem.isAccount ? 14 : 15
                                    font.weight: rowItem.isLimit ? Font.Normal : bracket && rowItem.isAccount ? Font.Bold : bracket ? Font.Normal : Font.Medium
                                    font.letterSpacing: bracket ? (rowItem.isLimit ? 1 : 0.6) : 0
                                }
                                Text {
                                    id: resetUnder
                                    visible: plain && (rowItem.isAccount || rowItem.it.kind === "usage") && text !== ""
                                    textFormat: Text.PlainText
                                    text: rowItem.isAccount ? rowItem.it.plan : rowItem.it.reset || ""
                                    color: c.muted
                                    font.family: fonts.ui
                                    font.pixelSize: 11
                                }
                            }

                            // The plan: Paper's italic serif, Blueprint's bordered caps; Artboard writes it under the name.
                            Rectangle {
                                visible: rowItem.isAccount && !plain && rowItem.it.plan !== ""
                                implicitWidth: planText.implicitWidth + (bracket ? 12 : 0)
                                implicitHeight: planText.implicitHeight + (bracket ? 2 : 0)
                                color: "transparent"
                                border.width: bracket ? 1 : 0
                                border.color: rowItem.isCurrent ? look.cursor.text : c.muted
                                Text {
                                    id: planText
                                    visible: rowItem.isAccount && !plain
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: marks.words(rowItem.it.plan || "")
                                    color: rowItem.isCurrent ? look.cursor.detail : c.muted
                                    font.family: bracket ? fonts.ui : fonts.display
                                    font.pixelSize: bracket ? 10 : 17
                                    font.italic: caps
                                    font.letterSpacing: bracket ? 1.2 : 0
                                }
                            }

                            // Each board's bar: Paper's outlined box, Artboard's rounded line, Blueprint's twenty blocks.
                            Item {
                                id: bar
                                readonly property real fraction: rowItem.it.fraction ?? 0
                                readonly property color fill: rowItem.warn ? marks.warn : rowItem.it.dim ? marks.dim : marks.bar.fill
                                readonly property int blocks: Math.round(fraction * 20)
                                visible: !rowItem.isGroup && !rowItem.isAccount && rowItem.it.fraction !== null && rowItem.it.fraction !== undefined
                                Layout.fillWidth: plain && rowItem.isLimit
                                Layout.preferredWidth: bracket ? 164 : plain ? (rowItem.isLimit ? -1 : 120) : 110
                                implicitHeight: bracket ? blockText.implicitHeight : plain ? 6 : 8

                                Rectangle {
                                    visible: marks.bar.kind === "box"
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.width: 1
                                    border.color: rowItem.it.dim ? marks.dim : marks.bar.track
                                    Rectangle {
                                        x: 1
                                        y: 1
                                        width: (parent.width - 2) * bar.fraction
                                        height: parent.height - 2
                                        color: bar.fill
                                    }
                                }
                                Rectangle {
                                    visible: marks.bar.kind === "round"
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
                                Row {
                                    visible: marks.bar.kind === "blocks"
                                    Text {
                                        id: blockText
                                        textFormat: Text.PlainText
                                        text: "▮".repeat(bar.blocks)
                                        color: bar.fill
                                        font.family: fonts.mono
                                        font.pixelSize: 12
                                        font.letterSpacing: 0.6
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "▮".repeat(20 - bar.blocks)
                                        color: marks.bar.track
                                        font.family: fonts.mono
                                        font.pixelSize: 12
                                        font.letterSpacing: 0.6
                                    }
                                }
                            }

                            // A stale account's line, or a provider's stale time or failure; a failure speaks in the danger token.
                            Rectangle {
                                visible: noteText.visible
                                implicitWidth: noteText.implicitWidth + (bracket && rowItem.it.error ? 16 : 0)
                                implicitHeight: noteText.implicitHeight + (bracket && rowItem.it.error ? 2 : 0)
                                color: "transparent"
                                border.width: bracket && rowItem.it.error ? 1 : 0
                                border.color: marks.warn
                                Text {
                                    id: noteText
                                    visible: !rowItem.isGroup && !rowItem.isLimit && (rowItem.it.note || "") !== ""
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: bracket ? (rowItem.it.error ? "✕ " : "") + (rowItem.it.note || "").toUpperCase() : rowItem.it.note || ""
                                    color: rowItem.it.error ? marks.warn : rowItem.isCurrent ? look.cursor.detail : marks.dim
                                    font.family: caps ? fonts.display : fonts.ui
                                    font.pixelSize: caps ? 17 : bracket ? 11 : 12
                                    font.italic: caps
                                    font.weight: bracket && rowItem.it.error ? Font.Bold : Font.Normal
                                    font.letterSpacing: bracket ? 1.2 : 0
                                }
                            }

                            // The figure: from 80% used it takes the danger token, a bolder weight and a small triangle. Paper writes it after the bar, the others at the right.
                            Item {
                                id: figure
                                visible: rowItem.fig !== null && rowItem.fig.main !== ""
                                Layout.fillWidth: !caps && !(plain && rowItem.isLimit)
                                Layout.preferredWidth: caps ? 230 : plain && rowItem.isLimit ? 56 : figRow.implicitWidth
                                implicitHeight: figRow.implicitHeight

                                Row {
                                    id: figRow
                                    anchors.left: caps ? parent.left : undefined
                                    anchors.right: caps ? undefined : parent.right
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
                                        textFormat: Text.PlainText
                                        text: rowItem.fig ? rowItem.fig.main : ""
                                        color: rowItem.warn ? marks.warn : rowItem.ink
                                        font.family: fonts.ui
                                        font.pixelSize: rowItem.isLimit ? (plain ? 12 : 13) : plain ? 14 : 13
                                        font.weight: rowItem.warn ? Font.Bold : plain ? Font.Medium : Font.Normal
                                    }
                                    Text {
                                        id: figTail
                                        visible: text !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        textFormat: Text.PlainText
                                        text: rowItem.fig ? rowItem.fig.tail : ""
                                        color: rowItem.isCurrent ? look.cursor.detail : c.muted
                                        font.family: fonts.ui
                                        font.pixelSize: rowItem.isLimit ? 12 : 13
                                    }
                                }
                            }

                            Item {
                                visible: caps || !figure.visible
                                Layout.fillWidth: true
                            }

                            // ACTIVE in each board's mark: Paper's box, Artboard's ink chip with its dot, Blueprint's bracket.
                            Rectangle {
                                id: activeMark
                                visible: rowItem.isAccount && rowItem.it.active
                                implicitWidth: activeRow.implicitWidth + (bracket ? 0 : plain ? 18 : 12)
                                implicitHeight: activeRow.implicitHeight + (bracket ? 0 : 6)
                                radius: marks.active.radius
                                color: marks.active.fill
                                border.width: marks.active.border === "transparent" ? 0 : 1
                                border.color: rowItem.isCurrent && caps ? look.cursor.text : marks.active.border
                                Row {
                                    id: activeRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Rectangle {
                                        visible: marks.active.dot !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: marks.active.dot || "transparent"
                                    }
                                    Text {
                                        id: activeText
                                        textFormat: Text.PlainText
                                        text: marks.active.text
                                        color: rowItem.isCurrent && !plain ? look.cursor.text : marks.active.color
                                        font.family: fonts.ui
                                        font.pixelSize: plain ? 11 : 10
                                        font.weight: plain ? Font.Medium : bracket ? Font.Bold : Font.Normal
                                        font.letterSpacing: plain ? 0 : 1.4
                                    }
                                }
                            }

                            // The reset at the row's end: Paper's italic serif, Blueprint's caps; Artboard puts a usage row's under its name.
                            Text {
                                id: resetText
                                visible: !rowItem.isGroup && !rowItem.isAccount && !(plain && rowItem.it.kind === "usage") && (rowItem.isLimit || rowItem.it.kind === "usage")
                                Layout.preferredWidth: caps ? -1 : bracket ? 140 : 112
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: marks.words(rowItem.it.reset || "")
                                color: rowItem.warn && plain ? marks.warn : rowItem.quiet
                                font.family: caps ? fonts.display : fonts.ui
                                font.pixelSize: caps ? 17 : 11
                                font.italic: caps
                                font.letterSpacing: bracket ? 1.2 : 0
                            }
                        }
                    }
                }
            }

            Rule {
                visible: !caps
            }

            // When the rows were fetched, or that a fetch runs; Paper writes it at the key strip's end.
            Text {
                id: footerLine
                visible: !caps
                Layout.fillWidth: true
                Layout.leftMargin: bracket ? 22 : 20
                Layout.topMargin: 9
                Layout.bottomMargin: 9
                textFormat: Text.PlainText
                text: marks.words(view.footer)
                color: bracket && fetcher.running ? c.accent : c.muted
                font.family: look.small.font
                font.pixelSize: look.small.size
                font.letterSpacing: look.small.spacing
            }

            Rule {}

            // The key strip as Pass draws it: chips in Artboard, tracked caps in Paper, brackets in Blueprint.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: plain ? 14 : bracket ? 22 : 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: plain ? 10 : 12
                Layout.bottomMargin: bracket ? 14 : Layout.topMargin
                spacing: 8

                Flow {
                    Layout.fillWidth: true
                    spacing: plain ? 8 : 14

                    Repeater {
                        id: keyRepeater
                        model: A.accountsKeys(look)

                        Rectangle {
                            id: keyPair
                            required property var modelData
                            readonly property string keyLabel: keyText.text
                            readonly property string wordLabel: wordText.text
                            width: pair.implicitWidth + (plain ? 14 : 0)
                            height: pair.implicitHeight + (plain ? 6 : 0)
                            radius: 6
                            color: look.chip.fill

                            Row {
                                id: pair
                                anchors.centerIn: parent
                                spacing: plain ? 6 : 5

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

                // Paper's red square marks a fetch that runs.
                Rectangle {
                    visible: caps && fetcher.running
                    implicitWidth: 7
                    implicitHeight: 7
                    color: c.accent
                }
                Text {
                    id: stripFooter
                    visible: caps
                    textFormat: Text.PlainText
                    text: view.footer
                    color: fetcher.running ? c.ink : c.muted
                    font.family: fonts.display
                    font.pixelSize: 17
                    font.italic: true
                }
            }
        }
    }

    // A rule across the card: solid, or dashed in Blueprint.
    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: look.rule.dashed ? "transparent" : look.rule.color

        Root.Dashed {
            visible: look.rule.dashed
            anchors.fill: parent
            color: look.rule.color
        }
    }
}

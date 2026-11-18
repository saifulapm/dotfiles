import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/accounts.mjs" as A
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T

// Claude accounts with their limits, then balances and usage, drawn inside the island on its fill (board 8), from dots-accounts' rows; the collector runs only while the island shows it, on open and on r or the refresh button.
Item {
    id: panel

    required property var theme
    property bool shown: false
    property int opens: 0
    property var openMs: null
    // The open's first frame, drawn with or without its rows: the open the 50 ms budget times.
    property var cardMs: null
    // When the open being timed was requested, or -1 once its first frame with rows is swapped.
    property real openT0: -1
    // True once this open's rows are in: the cache's answer, or the rows a fetch still running at the open had drawn.
    property bool rowsIn: false
    property string registryText: ""
    property string rowsText: "[]"
    // The id of this device's Context7 key, from the state file dots context7 use writes.
    property string context7Text: ""
    // What "updated N min ago" counts from; the minute tick below moves it while the island shows Accounts.
    property real now: Date.now()
    // The cursor's place among the rows it stops on.
    property int selected: 0
    readonly property bool busy: registryReader.running || cachedReader.running || fetcher.running || user.running || registryRereader.running || keyUser.running || context7Reader.running
    readonly property string dotsBin: Quickshell.shellDir + "/bin/dots"

    readonly property string command: Quickshell.env("DOTS_ACCOUNTS") || Quickshell.shellDir + "/bin/dots-accounts"
    readonly property string registryPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/claude-accounts.json"
    readonly property string context7Path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/context7-active"
    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, and the tones lifted to read on it.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property var view: A.accountsView(registryText, rowsText, now, fetcher.running, context7Text)
    readonly property var items: A.accountsItems(view)
    readonly property var stops: items.filter(it => it.stop).map(it => it.key)
    readonly property string current: stops.length ? stops[Math.min(selected, stops.length - 1)] : ""
    readonly property var activeAccount: items.find(it => it.kind === "account" && it.active) ?? null
    readonly property var otherAccounts: items.filter(it => it.kind === "account" && !it.active)
    // Board 8 draws the balances and the usage rows as one set of tiles under the one caption.
    readonly property var tileItems: items.filter(it => it.kind !== "account")
    readonly property string updated: view.busy ? "refreshing…" : A.updatedText(view.latest, now)
    readonly property string refreshGlyph: String.fromCodePoint(0xF0450)
    // The island reports this as its surface while Accounts shows, and grows to this width for it (board 8).
    readonly property string name: "accounts"
    readonly property int wantWidth: 640
    // True once the island has come to rest on Accounts; the surfaces' window sets it.
    property bool settled: false
    implicitHeight: column.implicitHeight + 32

    // A second open while a fetch runs leaves that fetch to finish and starts none.
    function open(t0) {
        openT0 = t0;
        openMs = null;
        cardMs = null;
        opens += 1;
        selected = 0;
        now = Date.now();
        rowsIn = busy;
        if (!busy) {
            context7Reader.used = false;
            context7Reader.running = true;
            registryReader.running = true;
        }
        shown = true;
        keyTarget.forceActiveFocus();
    }

    // A fetch that is running finishes within its 10 s limit: killing node would orphan its children's process groups.
    function close() {
        shown = false;
    }

    function refresh() {
        if (!busy)
            fetcher.running = true;
    }

    // dots claude-account is the registry's only writer, so ACTIVE moves only once it has written and the registry is read again; on a Context7 key row, dots context7 use makes the key this device's, and the state file is read again.
    function use() {
        const item = items.find(it => it.key === current) ?? null;
        const key = A.context7Target(item);
        if (key) {
            if (keyUser.running)
                return;
            keyUser.key = key;
            keyUser.command = [dotsBin, "context7", "use", key];
            keyUser.running = true;
            return;
        }
        const id = A.useTarget(item);
        if (!id || user.running)
            return;
        user.account = id;
        user.label = item.label;
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

    // A click on a row the cursor stops on moves it there and does what Enter does; any other row takes none.
    function clickRow(key) {
        const s = stops.indexOf(key);
        if (s < 0)
            return;
        selected = s;
        use();
    }

    // Rows that will not parse as a list keep the ones drawn.
    function take(text) {
        if (text.trim().charAt(0) === "[")
            rowsText = text;
        now = Date.now();
        rowsIn = true;
    }

    // An item's place in the window.
    function boxOf(item) {
        const p = item.mapToItem(null, 0, 0);
        return { x: p.x, y: p.y, w: item.width, h: item.height };
    }

    function state() {
        const bars = [];
        for (let i = 0; i < barRepeater.count; i++)
            bars.push(barRepeater.itemAt(i).drawn());
        const others = [];
        for (let i = 0; i < otherRepeater.count; i++)
            others.push(otherRepeater.itemAt(i).drawn());
        const tiles = [];
        for (let i = 0; i < tileRepeater.count; i++)
            tiles.push(tileRepeater.itemAt(i).drawn());
        const captions = balanceCaption.visible ? [balanceCaption.text] : [];
        const limit = l => ({ name: l.name, figure: l.figure, reset: l.reset, warning: l.warning });
        const other = r => ({ label: r.label, figure: r.figure, note: r.note, warning: r.warning, error: r.error });
        return JSON.stringify({
            // The latest notice, drawn at the tool's foot while the island holds the tool.
            note: toolNote.text,
            loaded: true,
            open: shown,
            visible: panel.visible,
            drawing: panel.visible,
            busy: busy,
            title: titleText.text,
            titleBox: boxOf(titleText),
            updated: updatedLabel.visible ? updatedLabel.text : "",
            refreshButton: { glyph: refreshText.text, w: refreshButton.width, h: refreshButton.height, fill: String(refreshButton.color) },
            active: activeTile.visible ? activeTile.drawn() : null,
            bars: bars,
            others: others,
            captions: captions,
            tiles: tiles,
            accounts: view.accounts.map(a => ({ id: a.id, label: a.label, plan: a.plan, active: a.active, note: a.note, limits: a.limits.map(limit) })),
            balances: view.balances.map(other),
            usage: view.usage.map(other),
            selected: current,
            ink: String(on),
            fillColor: String(fill),
            openMs: openMs,
            cardMs: cardMs,
            opens: opens,
            settled: panel.settled,
            box: boxOf(panel),
            keyboard: panel.Window.active
        });
    }

    // The minute the header counts "updated N min ago" in moves only while Accounts shows.
    Root.Tick {
        interval: 30000
        repeat: true
        running: panel.shown
        onTriggered: panel.now = Date.now()
    }

    Process {
        id: registryReader
        command: ["cat", panel.registryPath]
        stdout: StdioCollector {
            id: registryOut
        }
        // No registry file reads as empty, which the view takes as the one account main; an island closed meanwhile starts no collector.
        onExited: {
            panel.registryText = registryOut.text;
            if (panel.shown)
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
            if (used && panel.activeAccount && panel.activeAccount.account === user.account)
                panel.theme.notice(A.activeNotice(user.label));
        }
    }

    Process {
        id: keyUser
        property string key: ""
        onExited: code => {
            context7Reader.used = code === 0;
            context7Reader.running = true;
        }
    }

    // No state file reads as empty, which the view takes as main; a refused use leaves it as it was and the island says nothing.
    Process {
        id: context7Reader
        property bool used: false
        command: ["cat", panel.context7Path]
        stdout: StdioCollector {
            id: context7Out
        }
        onExited: {
            panel.context7Text = context7Out.text;
            if (used && panel.view.usage.some(u => u.context7 === keyUser.key && u.active))
                panel.theme.notice(A.context7Notice(keyUser.key));
        }
    }

    Component.onCompleted: Root.State.loaded.push("accounts")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "accounts")

    // Holds the keyboard while Accounts shows: j and k move between the rows Enter acts on, r fetches again.
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

    // A press anywhere on the tool is on its card, so the surfaces' window never takes it for a click outside.
    Item {
        objectName: "card"
        anchors.fill: parent
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 8

        // The heading, when the rows were fetched, and the refresh button.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 10

            Text {
                id: titleText
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: "Accounts"
                color: panel.on
                font.family: panel.fonts.ui
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            Text {
                id: updatedLabel
                visible: text !== ""
                textFormat: Text.PlainText
                text: panel.updated
                color: panel.tones.muted
                font.family: panel.fonts.ui
                font.pixelSize: 11
            }

            Rectangle {
                id: refreshButton
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: Qt.alpha(panel.on, 0.07)

                Text {
                    id: refreshText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: panel.refreshGlyph
                    color: panel.on
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 15
                }

                Root.Click {
                    name: "accounts-refresh"
                    onTapped: panel.refresh()
                }
            }
        }

        // The active account: shaded, with its inverted chip and a bar for each limit.
        Rectangle {
            id: activeTile
            function drawn() {
                return {
                    name: activeName.text,
                    chip: chipText.text,
                    chipFill: String(chip.color),
                    chipInk: String(chipText.color),
                    fill: String(color),
                    note: activeNote.visible ? activeNote.text : "",
                    chipBox: panel.boxOf(chip),
                    box: panel.boxOf(activeTile)
                };
            }

            visible: panel.activeAccount !== null
            Layout.fillWidth: true
            implicitHeight: visible ? activeColumn.implicitHeight + 24 : 0
            radius: 14
            color: Qt.alpha(panel.on, 0.12)

            ColumnLayout {
                id: activeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        id: activeName
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: panel.activeAccount ? panel.activeAccount.label : ""
                        elide: Text.ElideRight
                        color: panel.on
                        font.family: panel.fonts.ui
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    Rectangle {
                        id: chip
                        implicitWidth: chipText.implicitWidth + 18
                        implicitHeight: 22
                        radius: 11
                        color: panel.on

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: "Active"
                            color: panel.fill
                            font.family: panel.fonts.ui
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                    }
                }

                // A stale account's line, or what to do about a failed one.
                Text {
                    id: activeNote
                    visible: text !== ""
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: panel.activeAccount ? panel.activeAccount.note : ""
                    elide: Text.ElideRight
                    color: panel.tones.muted
                    font.family: panel.fonts.ui
                    font.pixelSize: 12
                }

                Repeater {
                    id: barRepeater
                    model: panel.activeAccount ? panel.activeAccount.limits : []

                    RowLayout {
                        id: barRow
                        required property var modelData
                        function drawn() {
                            return {
                                label: barLabel.text,
                                height: track.height,
                                share: track.width > 0 ? meter.width / track.width : 0,
                                trackFill: String(track.color),
                                meterFill: String(meter.color),
                                right: barRight.text,
                                rightColor: String(barRight.color),
                                warning: modelData.warning,
                                meterBox: panel.boxOf(meter)
                            };
                        }

                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            id: barLabel
                            Layout.preferredWidth: 76
                            textFormat: Text.PlainText
                            text: barRow.modelData.label
                            elide: Text.ElideRight
                            color: panel.tones.muted
                            font.family: panel.fonts.ui
                            font.pixelSize: 12
                        }

                        Rectangle {
                            id: track
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: Qt.alpha(panel.on, 0.16)

                            Rectangle {
                                id: meter
                                width: parent.width * (barRow.modelData.fraction ?? 0)
                                height: parent.height
                                radius: 4
                                color: barRow.modelData.warning ? panel.tones.danger : panel.on
                            }
                        }

                        Text {
                            id: barRight
                            Layout.preferredWidth: 92
                            Layout.minimumWidth: Math.min(implicitWidth, 160)
                            horizontalAlignment: Text.AlignRight
                            textFormat: Text.PlainText
                            text: barRow.modelData.right
                            elide: Text.ElideLeft
                            color: barRow.modelData.warning ? panel.tones.danger : panel.tones.muted
                            font.family: panel.fonts.ui
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }

        // The other accounts, one line each.
        Repeater {
            id: otherRepeater
            model: panel.otherAccounts

            Rectangle {
                id: otherRow
                required property var modelData
                function drawn() {
                    return {
                        name: otherName.text,
                        line: otherLine.text,
                        selected: modelData.key === panel.current,
                        fill: String(color),
                        box: panel.boxOf(otherRow),
                        elided: otherLine.truncated,
                        right: otherLine.mapToItem(null, otherLine.width, 0).x
                    };
                }

                Layout.fillWidth: true
                implicitHeight: 48
                radius: 12
                color: modelData.key === panel.current ? Qt.alpha(panel.on, 0.12) : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Text {
                        id: otherName
                        textFormat: Text.PlainText
                        text: otherRow.modelData.label
                        elide: Text.ElideRight
                        Layout.maximumWidth: 200
                        color: panel.on
                        font.family: panel.fonts.ui
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    Text {
                        id: otherLine
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        textFormat: Text.PlainText
                        text: [otherRow.modelData.line, otherRow.modelData.note].filter(s => s).join(" · ")
                        elide: Text.ElideRight
                        color: panel.tones.muted
                        font.family: panel.fonts.ui
                        font.pixelSize: 12
                    }
                }

                Root.Click {
                    name: "accounts-row:" + otherRow.modelData.key
                    onTapped: panel.clickRow(otherRow.modelData.key)
                }
            }
        }

        Text {
            id: balanceCaption
            visible: panel.tileItems.length > 0
            Layout.preferredHeight: 22
            Layout.leftMargin: 4
            verticalAlignment: Text.AlignBottom
            textFormat: Text.PlainText
            text: "BALANCES"
            color: panel.tones.muted
            font.family: panel.fonts.ui
            font.pixelSize: 10
            font.letterSpacing: 1.2
        }

        Grid {
            id: balanceGrid
            visible: panel.tileItems.length > 0
            Layout.fillWidth: true
            columns: 2
            spacing: 8

            Repeater {
                id: tileRepeater
                model: panel.tileItems
                delegate: tileComponent
            }
        }
        // A switch of account or key's word, which the island cannot show while Accounts holds it.
        Root.ToolNote {
            id: toolNote
            theme: panel.theme
            Layout.fillWidth: true
            color: panel.tones.muted
            font.family: panel.fonts.ui ?? ""
        }
    }

    // A balance or a usage row as a tile: its name and any note, then its figure with the muted rest after "of"; a figure from 80% used takes the danger tone.
    Component {
        id: tileComponent

        Rectangle {
            id: tile
            required property var modelData
            readonly property bool selected: modelData.key === panel.current
            function drawn() {
                return {
                    kind: modelData.kind,
                    name: tileName.text,
                    main: tileMain.text,
                    rest: tileRest.text,
                    note: tileNote.visible ? tileNote.text : "",
                    reset: tileReset.visible ? tileReset.text : "",
                    warning: modelData.warning,
                    selected: selected,
                    fill: String(color),
                    mainColor: String(tileMain.color),
                    mainElided: tileMain.truncated,
                    noteElided: tileNote.visible && tileNote.truncated,
                    noteColor: String(tileNote.color),
                    box: panel.boxOf(tile),
                    right: [tileName, tileNote, tileMain, tileRest, tileReset].filter(t => t.visible).reduce((m, t) => Math.max(m, t.mapToItem(null, t.width, 0).x), 0)
                };
            }

            // Two tiles to a row, sized from the card's column: the grid's own width comes from its tiles, so sizing them from it loops its polish and leaves the card unlaid.
            width: (column.width - 8) / 2
            height: 64
            radius: 14
            color: Qt.alpha(panel.on, selected ? 0.12 : 0.07)

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 2

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        id: tileName
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: tile.modelData.name
                        elide: Text.ElideRight
                        color: panel.tones.muted
                        font.family: panel.fonts.ui
                        font.pixelSize: 12
                    }

                    // A stale value's time, or a failure; a failure speaks in the danger tone.
                    Text {
                        id: tileNote
                        visible: text !== ""
                        Layout.maximumWidth: 130
                        textFormat: Text.PlainText
                        text: tile.modelData.note || ""
                        elide: Text.ElideRight
                        color: tile.modelData.error ? panel.tones.danger : panel.tones.muted
                        font.family: panel.fonts.ui
                        font.pixelSize: 12
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        id: tileMain
                        Layout.maximumWidth: 170
                        textFormat: Text.PlainText
                        text: tile.modelData.main
                        elide: Text.ElideRight
                        color: tile.modelData.warning ? panel.tones.danger : panel.on
                        font.family: panel.fonts.ui
                        font.pixelSize: 17
                        font.weight: Font.Bold
                    }

                    Text {
                        id: tileRest
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: tile.modelData.rest
                        elide: Text.ElideRight
                        color: panel.tones.muted
                        font.family: panel.fonts.ui
                        font.pixelSize: 12
                    }

                    Text {
                        id: tileReset
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: tile.modelData.reset || ""
                        color: panel.tones.muted
                        font.family: panel.fonts.ui
                        font.pixelSize: 11
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            Root.Click {
                visible: tile.modelData.stop
                enabled: tile.modelData.stop
                name: "accounts-row:" + tile.modelData.key
                onTapped: panel.clickRow(tile.modelData.key)
            }
        }
    }
}

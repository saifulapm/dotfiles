import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/cheatsheet.mjs" as Lib
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T
import "lib/island-host.mjs" as H

// Every titled niri bind, each surface's own keys and the touchpad's gestures in six columns, drawn inside the island on its fill.
Item {
    id: sheet

    required property var theme
    property bool shown: false
    property var rows: []
    // False until the binds file is first read and its rows are built.
    property bool bindsRead: false
    // How many row titles are cut short on screen, so a check can tell every bind apart.
    property int truncated: 0
    readonly property string query: input.text
    readonly property var columns: Lib.columnsOfSix(Lib.groupRowsSix(Lib.filterRows(rows, query)))
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1
    // When the last open and close were asked for, in ms since the epoch.
    property real openedAt: 0
    property real closedAt: 0
    // The island grows to this width for the sheet, as the boards draw it.
    readonly property int wantWidth: 1160

    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and the tones lifted to read on its fill.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray" })

    implicitHeight: column.implicitHeight
    // The last row is in by this many ms after the open (rowFade's cap).
    readonly property int introEnd: H.rowFade(99).delay + H.rowFade(99).ms
    // Milliseconds since the open began, which each row's fade reads; at rest every row is in.
    property real introMs: introEnd
    readonly property bool busy: intro.running
    // The first row's width on the open's first frame, so a check can tell it never reflowed.
    property var openRowWidth: null

    // Row n's fade: 0 to 1 on an ease-out from its delay, as H.rowFade times it.
    function rowIn(n) {
        const f = H.rowFade(n);
        const x = Math.max(0, Math.min(1, (introMs - f.delay) / f.ms));
        return 1 - Math.pow(1 - x, 3);
    }

    NumberAnimation {
        id: intro
        target: sheet
        property: "introMs"
        from: 0
        to: sheet.introEnd
        duration: sheet.introEnd
    }

    function open(t0) {
        openT0 = t0;
        openedAt = t0;
        openMs = null;
        opens += 1;
        input.text = "";
        list.contentY = 0;
        openRowWidth = null;
        shown = true;
        intro.restart();
        input.forceActiveFocus();
    }

    function close() {
        if (shown)
            closedAt = Date.now();
        shown = false;
        intro.stop();
        introMs = introEnd;
    }

    // One Esc level: a query typed is cleared first, then the sheet closes (2TM85BFB).
    function stepBack() {
        if (input.text !== "")
            input.text = "";
        else
            close();
    }

    // Called on each of the host window's frames; the first one after the open ends the timing, so a first open's load counts.
    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
            openRowWidth = groupRepeater.count && groupRepeater.itemAt(0).groupRows.count ? groupRepeater.itemAt(0).groupRows.itemAt(0).width : null;
        }
    }

    function state() {
        const drawn = [];
        const rowKeys = [];
        for (let i = 0; i < groupRepeater.count; i++) {
            const g = groupRepeater.itemAt(i);
            const rs = [];
            for (const r of [g.groupRows, g.tailRows]) {
                for (let j = 0; j < r.count; j++) {
                    const row = r.itemAt(j);
                    rs.push({ key: row.entry.key, surface: row.entry.surface ?? null, width: row.width });
                    rowKeys.push(row.entry.key);
                }
            }
            drawn.push({ name: g.entry.name, rows: rs });
        }
        return JSON.stringify({
            open: shown,
            rows: rows.length,
            truncated: truncated,
            groups: Lib.GROUPS_SIX,
            columns: drawn,
            query: query,
            openMs: openMs,
            opens: opens,
            drawing: shown,
            busy: busy,
            openedAt: openedAt,
            closedAt: closedAt,
            openRowWidth: openRowWidth,
            heading: heading.text,
            rowKeys: rowKeys,
            // Whatever the sheet draws under its columns, as visible items after the list; the board draws nothing there.
            belowColumns: Array.from(column.children).slice(Array.from(column.children).indexOf(list) + 1).filter(c => c.visible).length
        });
    }

    Component.onCompleted: Root.State.loaded.push("cheatsheet")

    // The nested session sets DOTS_NIRI_BINDS to the repo's binds, so it never reads the live ones.
    FileView {
        path: Quickshell.env("DOTS_NIRI_BINDS") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri/binds.kdl"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            sheet.rows = Lib.parseBinds(text()).concat(Lib.IN_SURFACES, Lib.TOUCHPAD);
            sheet.bindsRead = true;
        }
        onLoadFailed: sheet.bindsRead = true
    }

    // The click-outside test reads a press on this as one on the sheet.
    ColumnLayout {
        id: column
        objectName: "card"
        width: sheet.width
        height: sheet.height
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 16
            spacing: 16
            opacity: sheet.rowIn(0)
            transform: Translate {
                y: H.rowFade(0).rise * (1 - sheet.rowIn(0))
            }

            Text {
                id: heading
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: "Keys"
                color: sheet.on
                font.family: sheet.fonts.ui ?? ""
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            // The search field: a tile a shade above the island's fill; typing filters the rows.
            Rectangle {
                Layout.preferredWidth: 240
                implicitHeight: 32
                radius: 10
                color: Qt.alpha(sheet.on, 0.06)

                Text {
                    anchors.fill: input
                    visible: input.text === ""
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    text: "Search"
                    color: sheet.tones.muted
                    font: input.font
                }

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: sheet.on
                    font.family: sheet.fonts.ui ?? ""
                    font.pixelSize: 13
                    clip: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape)
                            sheet.stepBack();
                        else
                            return;
                        event.accepted = true;
                    }
                }
            }
        }

        // Scrolls when the columns are taller than the island's height cap leaves room for.
        Flickable {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: groups.implicitHeight + 16
            contentHeight: groups.implicitHeight + 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: groups
                x: 16
                width: list.width - 32
                spacing: 16

                Repeater {
                    id: groupRepeater
                    model: sheet.columns

                    // A column holds one group: its caption, then its rows.
                    Column {
                        id: group
                        required property var modelData
                        readonly property var entry: modelData[0]
                        readonly property alias groupRows: rowRepeater
                        readonly property alias tailRows: tailRepeater
                        width: (groups.width - 5 * groups.spacing) / 6
                        spacing: 6

                        Text {
                            textFormat: Text.PlainText
                            bottomPadding: 2
                            opacity: sheet.rowIn(1)
                            transform: Translate {
                                y: H.rowFade(1).rise * (1 - sheet.rowIn(1))
                            }
                            text: group.entry.name
                            color: sheet.tones.muted
                            font.family: sheet.fonts.ui ?? ""
                            font.pixelSize: 10
                            font.letterSpacing: 1.2
                            font.capitalization: Font.AllUppercase
                        }

                        // The first seven rows come in one by one.
                        Repeater {
                            id: rowRepeater
                            model: group.entry.rows.slice(0, 7)

                            KeyRow {
                                id: row
                                required property var modelData
                                required property int index
                                entry: modelData
                                width: group.width
                                opacity: sheet.rowIn(2 + index)
                                transform: Translate {
                                    y: H.rowFade(2 + row.index).rise * (1 - sheet.rowIn(2 + row.index))
                                }
                            }
                        }

                        // The rest come in together with the tenth, past rowFade's cap, so a long column costs one fade.
                        Column {
                            width: group.width
                            spacing: 6
                            opacity: sheet.rowIn(9)
                            transform: Translate {
                                y: H.rowFade(9).rise * (1 - sheet.rowIn(9))
                            }

                            Repeater {
                                id: tailRepeater
                                model: group.entry.rows.slice(7)

                                KeyRow {
                                    required property var modelData
                                    entry: modelData
                                    width: group.width
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A title, then its keys in one 20 px chip; a chip per key cost the shell 10 MiB of idle memory across the sheet's rows.
    component KeyRow: RowLayout {
        required property var entry
        spacing: 6

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: parent.entry.title
            // Titles wrap rather than elide: Mod+Ctrl+1 to 9 differ only past "Move Column to Workspace".
            wrapMode: Text.Wrap
            onTruncatedChanged: sheet.truncated += truncated ? 1 : -1
            Component.onDestruction: if (truncated) sheet.truncated -= 1
            color: sheet.on
            font.family: sheet.fonts.ui ?? ""
            font.pixelSize: 13
        }

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Math.max(20, keyText.implicitWidth + 12)
            implicitHeight: 20
            radius: 10
            color: Qt.alpha(sheet.on, 0.11)

            Text {
                id: keyText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: Lib.chipsOf(parent.parent.entry.key).join("  ")
                color: sheet.on
                font.family: sheet.fonts.mono ?? ""
                font.pixelSize: 11
            }
        }
    }
}

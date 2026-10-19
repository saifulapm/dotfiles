import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/cheatsheet.mjs" as Lib
import "lib/voice.mjs" as V

// Every titled niri bind in four columns, drawn in the Surfaces window.
Item {
    id: sheet

    required property var theme
    property bool shown: false
    property var rows: []
    // How many row titles are cut short on screen, so a check can tell every bind apart.
    property int truncated: 0
    readonly property string query: input.text
    readonly property var columns: Lib.groupRows(Lib.filterRows(rows, query))
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: V.listLook(theme.tokens)
    readonly property Root.Motion motion: Root.Motion {
        shown: sheet.shown
        tokens: sheet.theme.tokens
    }

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        input.text = "";
        list.contentY = 0;
        shown = true;
        keys.forceActiveFocus();
    }

    function close() {
        shown = false;
    }

    // Called on each of the host window's frames; the first one after open() ends the timing.
    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function state() {
        // The keys as drawn, read from the row and legend items.
        const rowKeys = [];
        for (let i = 0; i < groupRepeater.count; i++) {
            const g = groupRepeater.itemAt(i).rowRepeater;
            for (let j = 0; j < g.count; j++)
                rowKeys.push(g.itemAt(j).keyLabel);
        }
        const legend = [];
        for (let i = 0; i < legendRepeater.count; i++)
            legend.push(legendRepeater.itemAt(i));
        const r = topRule.mapToItem(null, 0, 0);
        return JSON.stringify({
            open: shown,
            rows: rows.length,
            truncated: truncated,
            groups: Lib.GROUPS,
            query: query,
            openMs: openMs,
            opens: opens,
            motion: motion.curves?.kind ?? null,
            settleMs: motion.settleMs,
            settled: motion.settled,
            drawing: motion.drawing,
            cardBox: card.drawnBox(),
            heading: (look.label.kind === "header" ? header : look.label.kind === "pill" ? pill : chip).text,
            headingKind: look.label.kind,
            ruleBox: { x: r.x, y: r.y, w: topRule.width, h: topRule.height },
            rowKeys: rowKeys,
            legend: legend.map(p => p.keyLabel + " " + p.wordLabel).join("  "),
            legendKeys: legend.map(p => p.keyLabel),
            legendSpacing: legend.length ? legend[0].wordSpacing : 0
        });
    }

    Component.onCompleted: Root.State.loaded.push("cheatsheet")

    // The nested session sets DOTS_NIRI_BINDS to the repo's binds, so it never reads the live ones.
    FileView {
        path: Quickshell.env("DOTS_NIRI_BINDS") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri/binds.kdl"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: sheet.rows = Lib.parseBinds(text())
    }

    visible: motion.drawing

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Slash)
                input.forceActiveFocus();
            else if (event.key === Qt.Key_Escape)
                sheet.close();
            else
                return;
            event.accepted = true;
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(c.paper, card.style.wash)
        }

        Root.Surface {
            id: card
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            width: Math.min(1160, parent.width - 48)
            height: Math.min(column.implicitHeight, parent.height - 96)
            tokens: sheet.theme.tokens
            label: "Keys"
            motion: sheet.motion

            ColumnLayout {
                id: column
                anchors.fill: parent
                spacing: 0

                // Blueprint names the sheet on a line of its own, as the launcher names its mode.
                RowLayout {
                    visible: look.label.kind === "header"
                    Layout.fillWidth: true
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    Layout.topMargin: 12

                    Text {
                        id: header
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: look.heading("keys", "")
                        color: look.small.color
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    Layout.topMargin: look.label.kind === "header" ? 8 : 18
                    Layout.bottomMargin: 14
                    spacing: 14

                    Rectangle {
                        visible: look.label.kind === "chip"
                        implicitWidth: chip.implicitWidth + 14
                        implicitHeight: chip.implicitHeight + 6
                        color: look.label.fill
                        Text {
                            id: chip
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: look.heading("keys", "")
                            color: look.label.color
                            font.family: fonts.ui
                            font.pixelSize: 10
                            font.letterSpacing: 1.4
                        }
                    }

                    Rectangle {
                        visible: look.label.kind === "pill"
                        implicitWidth: pill.implicitWidth + 18
                        implicitHeight: pill.implicitHeight + 6
                        radius: 8
                        color: look.label.fill
                        Text {
                            id: pill
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: look.heading("keys", "")
                            color: look.label.color
                            font.family: fonts.ui
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: "read from the niri binds · Mod = Super"
                        elide: Text.ElideRight
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 12
                    }
                    TextInput {
                        id: input
                        visible: activeFocus || text !== ""
                        Layout.preferredWidth: 220
                        color: c.ink
                        font.family: fonts.mono
                        font.pixelSize: 12
                        clip: true
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape)
                                sheet.close();
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                keys.forceActiveFocus();
                            else
                                return;
                            event.accepted = true;
                        }
                    }
                    Row {
                        spacing: look.legend("").chips ? 8 : 14
                        Repeater {
                            model: look.keys([["/", "filter"], ["esc", "close"]])
                            KeyPair {}
                        }
                    }
                }

                Rule {
                    id: topRule
                }

                // Scrolls when the columns are taller than the screen leaves room for.
                Flickable {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: groups.implicitHeight + 36
                    contentHeight: groups.implicitHeight + 36
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: groups
                        x: 24
                        y: 18
                        width: list.width - 48
                        spacing: 28

                        Repeater {
                            id: groupRepeater
                            model: sheet.columns

                            Column {
                                id: group
                                required property var modelData
                                readonly property alias rowRepeater: rowRepeater
                                width: (groups.width - 3 * groups.spacing) / 4
                                spacing: 6

                                Text {
                                    textFormat: Text.PlainText
                                    bottomPadding: 4
                                    text: group.modelData.name
                                    color: look.small.color
                                    font.family: look.small.font
                                    font.pixelSize: look.small.size
                                    font.letterSpacing: look.small.spacing
                                }

                                Repeater {
                                    id: rowRepeater
                                    model: group.modelData.rows

                                    RowLayout {
                                        required property var modelData
                                        readonly property string keyLabel: rowKey.text
                                        width: group.width
                                        spacing: 6

                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.maximumWidth: group.width - rowKey.implicitWidth - 24
                                            text: modelData.title
                                            // Titles wrap rather than elide: Mod+Ctrl+1 to 9 differ only past "Move Column to Workspace".
                                            wrapMode: Text.Wrap
                                            onTruncatedChanged: sheet.truncated += truncated ? 1 : -1
                                            Component.onDestruction: if (truncated) sheet.truncated -= 1
                                            color: c.ink
                                            font.family: fonts.ui
                                            font.pixelSize: 13
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: "........................................................................"
                                            clip: true
                                            color: c.line
                                            font.family: fonts.mono
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            id: rowKey
                                            textFormat: Text.PlainText
                                            text: look.keyText(modelData.key)
                                            color: c.ink
                                            font.family: fonts.mono
                                            font.pixelSize: 11
                                            font.letterSpacing: look.small.spacing
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rule {}

                // The keys every surface shares, in the launcher's legend: chips in Artboard.
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: look.voice === "plain" ? 14 : 24
                    Layout.rightMargin: Layout.leftMargin
                    Layout.topMargin: look.voice === "plain" ? 10 : 12
                    Layout.bottomMargin: Layout.topMargin
                    spacing: look.legend("").chips ? 8 : 14

                    Text {
                        textFormat: Text.PlainText
                        height: look.legend("").chips ? implicitHeight + 6 : implicitHeight
                        verticalAlignment: Text.AlignVCenter
                        text: look.tabText("inside every surface")
                        color: c.muted
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }

                    Repeater {
                        id: legendRepeater
                        model: look.keys([["j/k", "move"], ["↵", "act"], ["/", "search"], ["⇥", "section"], ["esc", "close"]])
                        KeyPair {}
                    }
                }
            }
        }
    }

    // One key and its word as the launcher's legend draws them: a chip in Artboard, tracked caps in Paper, brackets in Blueprint.
    component KeyPair: Rectangle {
        id: keyPair
        required property var modelData
        readonly property string keyLabel: keyText.text
        readonly property string wordLabel: wordText.text
        readonly property real wordSpacing: wordText.font.letterSpacing
        width: pairRow.implicitWidth + (look.legend("").chips ? 14 : 0)
        height: pairRow.implicitHeight + (look.legend("").chips ? 6 : 0)
        radius: 6
        color: look.chip.fill

        Row {
            id: pairRow
            anchors.centerIn: parent
            spacing: look.legend("").chips ? 6 : 5

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
                textFormat: Text.PlainText
                text: keyPair.modelData.word
                color: c.muted
                font.family: look.small.font
                font.pixelSize: look.small.size
                font.letterSpacing: look.small.spacing
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

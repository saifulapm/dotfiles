import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "." as Root
import "lib/voice.mjs" as L
import "lib/pass.mjs" as P

// The pass store as a list in the launcher's idiom; every secret goes through bin/dots-pass, and the list itself holds only names.
Item {
    id: pass

    required property var theme
    property bool shown: false
    readonly property string query: input.text
    property int selected: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1
    // dots-pass list's entries as of this open.
    property var entries: []
    property bool listed: false
    // A dots-pass run that outlives the card, such as a copy waiting on gpg's passphrase; the card stays loaded until it ends.
    readonly property bool busy: runner.running

    readonly property string bin: Quickshell.shellDir + "/../bin/dots-pass"
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property var found: P.passRows(entries, query)
    readonly property var rows: found.slice(0, 8)
    readonly property var current: rows[selected] ?? null
    readonly property Root.Motion motion: Root.Motion {
        shown: pass.shown
        tokens: pass.theme.tokens
    }

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        input.text = "";
        selected = 0;
        listed = false;
        lister.running = true;
        shown = true;
        input.forceActiveFocus();
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

    function move(by) {
        selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }

    // The card closes first, since gpg may ask for its passphrase on its own card; the island says how the copy went.
    function copy(kind) {
        if (!current || runner.running)
            return;
        close();
        runner.kind = kind;
        runner.command = [bin, kind, current.name];
        runner.running = true;
    }

    function state() {
        const cur = rowRepeater.itemAt(selected);
        const keys = [];
        for (let i = 0; i < keyRepeater.count; i++)
            keys.push((keyRepeater.itemAt(i).keyLabel + " " + keyRepeater.itemAt(i).wordLabel).trim());
        return JSON.stringify({
            loaded: true,
            open: shown,
            query: query,
            listed: listed,
            count: found.length,
            countText: (look.label.kind === "header" ? headerCount : chipCount).text,
            heading: (look.label.kind === "header" ? header : look.label.kind === "pill" ? pill : chip).text,
            // Each row as drawn: its runs' text and which are underlined, and its tag.
            rows: rows.map((r, i) => {
                const item = rowRepeater.itemAt(i);
                return {
                    name: item ? item.drawnName : "",
                    underlined: item ? item.underlined() : "",
                    otp: item ? item.tagShown : false
                };
            }),
            selected: selected,
            cursorFill: cur ? String(cur.color) : null,
            focus: results.activeFocus ? "list" : "query",
            hint: keys.join(" · "),
            busy: busy,
            openMs: openMs,
            opens: opens,
            settled: motion.settled,
            drawing: pass.visible,
            cardBox: card.drawnBox(),
            keyboard: pass.Window.active
        });
    }

    onQueryChanged: selected = 0

    Process {
        id: lister
        command: [pass.bin, "list"]
        stdout: StdioCollector {
            id: listOut
        }
        onExited: code => {
            if (code === 0)
                pass.entries = P.parseEntries(listOut.text);
            pass.listed = true;
        }
    }

    Process {
        id: runner
        property string kind: ""
        stderr: StdioCollector {
            id: runErr
        }
        onExited: code => pass.theme.notice(code === 0 ? P.copiedText(kind) : P.failedText(runErr.text))
    }

    Component.onCompleted: Root.State.loaded.push("pass")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "pass")

    visible: motion.drawing

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(c.paper, card.style.wash)
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: 168
        width: 640
        height: column.implicitHeight
        tokens: pass.theme.tokens
        label: "Pass"
        motion: pass.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            // Blueprint names the surface and counts its matches on a line of their own above the query.
            RowLayout {
                visible: look.label.kind === "header"
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                Layout.topMargin: 12

                Text {
                    id: header
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: look.heading("pass", "store")
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }
                Text {
                    id: headerCount
                    textFormat: Text.PlainText
                    text: look.count(found.length)
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: look.voice === "plain" ? 18 : look.voice === "bracket" ? 22 : 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: look.voice === "plain" ? 16 : look.voice === "bracket" ? 8 : 18
                Layout.bottomMargin: look.voice === "plain" ? 16 : 14
                spacing: look.voice === "caps" ? 14 : look.voice === "bracket" ? 10 : 12

                Rectangle {
                    visible: look.label.kind === "chip"
                    implicitWidth: chip.implicitWidth + 14
                    implicitHeight: chip.implicitHeight + 6
                    color: look.label.fill
                    Text {
                        id: chip
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: look.heading("pass", "")
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: 10
                        font.letterSpacing: 1.4
                    }
                }

                Text {
                    visible: look.prompt.text !== ""
                    textFormat: Text.PlainText
                    text: look.prompt.text
                    color: look.prompt.color
                    font.family: look.query.font
                    font.pixelSize: look.query.size
                }

                TextInput {
                    id: input
                    Layout.fillWidth: true
                    color: c.ink
                    font.family: look.query.font
                    font.pixelSize: look.query.size
                    clip: true
                    focus: true
                    cursorDelegate: look.caret === "block" ? blockCaret : null
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J))
                            pass.move(1);
                        else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K))
                            pass.move(-1);
                        else if (event.key === Qt.Key_Tab)
                            results.forceActiveFocus();
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            pass.copy("copy");
                        else if (event.key === Qt.Key_Escape)
                            pass.close();
                        else
                            return;
                        event.accepted = true;
                    }
                }

                Text {
                    id: chipCount
                    visible: look.label.kind === "chip"
                    textFormat: Text.PlainText
                    text: look.count(found.length)
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
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
                        text: look.heading("pass", "")
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }

            Rule {}

            // Holds focus after Tab, where the plain letter keys act on the cursor row and / returns to the query.
            Item {
                id: results
                Layout.fillWidth: true
                implicitHeight: list.implicitHeight + 16
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                        pass.move(1);
                    else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                        pass.move(-1);
                    else if (event.key === Qt.Key_Slash)
                        input.forceActiveFocus();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        pass.copy("copy");
                    else if (event.key === Qt.Key_O)
                        pass.copy("otp");
                    else if (event.key === Qt.Key_Escape)
                        pass.close();
                    else
                        return;
                    event.accepted = true;
                }

                Column {
                    id: list
                    y: 8
                    // Paper's rows run edge to edge; the others sit inset as tiles.
                    x: look.voice === "plain" ? 8 : look.voice === "bracket" ? 10 : 0
                    width: parent.width - 2 * x

                    // An empty store, or nothing matched, shows the keys that still work.
                    Text {
                        textFormat: Text.PlainText
                        visible: pass.listed && rows.length === 0
                        leftPadding: 20
                        topPadding: 11
                        bottomPadding: 11
                        text: look.keyText("n") + " " + look.tabText("new entry") + " · " + look.keyText("q") + " " + look.tabText("from qr") + " · " + look.keyText("esc") + " " + look.tabText("close")
                        color: c.muted
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }

                    Repeater {
                        id: rowRepeater
                        model: rows

                        Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: index === pass.selected
                            readonly property var runs: P.segments(modelData)
                            readonly property string drawnName: runs.map(r => r.text).join("")
                            function underlined() {
                                const out = [];
                                for (let i = 0; i < runRepeater.count; i++)
                                    if (runRepeater.itemAt(i).font.underline)
                                        out.push(runRepeater.itemAt(i).text);
                                return out.join("");
                            }
                            readonly property bool tagShown: otpTag.visible
                            width: list.width
                            implicitHeight: row.implicitHeight + (look.voice === "caps" ? 22 : 20)
                            radius: look.cursor.radius
                            color: isCurrent ? look.cursor.fill : "transparent"

                            RowLayout {
                                id: row
                                anchors.fill: parent
                                anchors.leftMargin: look.voice === "caps" ? 20 : 12
                                anchors.rightMargin: anchors.leftMargin
                                spacing: look.voice === "plain" ? 12 : 14

                                Text {
                                    visible: look.slot !== "icon"
                                    textFormat: Text.PlainText
                                    text: look.slot === "number" ? look.number(index) : "▸"
                                    color: look.slot === "number" ? (isCurrent ? look.cursor.text : c.muted) : isCurrent ? look.cursor.marker : "transparent"
                                    font.family: look.slot === "number" ? look.name.font : fonts.ui
                                    font.pixelSize: look.slot === "number" ? 13 : 15
                                    font.bold: look.slot === "number" && isCurrent
                                }

                                // Artboard's tile holds the entry's first letter.
                                Rectangle {
                                    visible: look.slot === "icon"
                                    implicitWidth: look.tile.size
                                    implicitHeight: look.tile.size
                                    radius: look.tile.radius
                                    color: look.tile.fill
                                    Text {
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: L.line(rowItem.modelData.leaf).charAt(0).toUpperCase()
                                        color: c.ink
                                        font.family: fonts.mono
                                        font.pixelSize: 15
                                    }
                                }

                                Row {
                                    Layout.fillWidth: true
                                    clip: true

                                    Repeater {
                                        id: runRepeater
                                        model: rowItem.runs

                                        Text {
                                            required property var modelData
                                            textFormat: Text.PlainText
                                            text: look.title(modelData.text)
                                            color: rowItem.isCurrent ? (modelData.folder ? look.cursor.detail : look.cursor.text) : modelData.folder ? c.muted : look.name.color
                                            font.family: look.name.font
                                            font.pixelSize: look.name.size
                                            font.weight: rowItem.isCurrent ? look.cursor.weight : look.name.weight
                                            font.letterSpacing: look.name.spacing
                                            font.underline: modelData.hit
                                        }
                                    }
                                }

                                Text {
                                    id: otpTag
                                    visible: rowItem.modelData.otp
                                    textFormat: Text.PlainText
                                    text: "OTP"
                                    color: rowItem.isCurrent ? look.cursor.detail : look.small.color
                                    font.family: look.small.font
                                    font.pixelSize: look.small.size
                                    font.letterSpacing: look.small.spacing
                                }
                            }
                        }
                    }
                }
            }

            Rule {}

            // The key strip as the launcher's legend draws it: chips in Artboard, tracked caps in Paper, brackets in Blueprint.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: look.voice === "plain" ? 14 : look.voice === "bracket" ? 22 : 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: look.voice === "plain" ? 10 : 12
                Layout.bottomMargin: look.voice === "bracket" ? 14 : Layout.topMargin
                spacing: look.legend("").chips ? 8 : 14

                Repeater {
                    id: keyRepeater
                    model: P.passKeys(look)

                    Rectangle {
                        id: keyPair
                        required property var modelData
                        readonly property string keyLabel: keyText.text
                        readonly property string wordLabel: wordText.text
                        width: pair.implicitWidth + (look.legend("").chips ? 14 : 0)
                        height: pair.implicitHeight + (look.legend("").chips ? 6 : 0)
                        radius: 6
                        color: look.chip.fill

                        Row {
                            id: pair
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

    // Blueprint's caret: a glowing accent block the height of the query.
    Component {
        id: blockCaret

        Rectangle {
            width: 11
            height: input.font.pixelSize
            color: look.prompt.color
            // Qt hides only its own caret when the query loses focus, so a delegate follows cursorVisible itself.
            visible: input.cursorVisible

            RectangularShadow {
                anchors.fill: parent
                z: -1
                blur: 9.6
                color: Qt.alpha(look.prompt.color, 0.8)
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

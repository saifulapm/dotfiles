import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "." as Root
import "lib/voice.mjs" as V
import "lib/pinentry.mjs" as P

// gpg's passphrase or confirmation card, shaped like the polkit prompt and drawn in the Surfaces window; it loads on the first request and unloads 30 s after it closes.
Item {
    id: prompt

    required property var theme
    property bool shown: false
    // {kind, description, prompt, error, answer} from the Pinentry service, while a request shows.
    property var request: null
    // The request as the card draws it, kept while its close still plays.
    property var seen: null
    readonly property bool confirm: seen?.kind === "confirm"

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: V.listLook(theme.tokens)
    readonly property var words: P.cardText(look, seen?.kind ?? "passphrase")
    readonly property Root.Motion motion: Root.Motion {
        shown: prompt.shown
        tokens: prompt.theme.tokens
        onDrawingChanged: if (!drawing)
            prompt.seen = null
    }

    function show(r) {
        request = r;
        seen = r;
        input.text = "";
        shown = true;
        if (confirm)
            confirmKeys.forceActiveFocus();
        else
            input.forceActiveFocus();
    }

    function reply(text) {
        const r = request;
        request = null;
        shown = false;
        input.text = "";
        r?.answer(text);
    }

    function submit() {
        if (request)
            reply(confirm ? P.ALLOW : P.pinAnswer(input.text));
    }

    // Esc, or another surface opening, answers the request so gpg never waits on a card nobody sees.
    function close() {
        if (request)
            reply(confirm ? P.DENY : P.CANCEL);
    }

    // gpg went away on its own, so there is nothing to answer.
    function dismiss() {
        request = null;
        shown = false;
        input.text = "";
    }

    function swapped() {
    }

    function headingItem() {
        return look.label.kind === "header" ? header : look.label.kind === "pill" ? pill : chip;
    }

    function box(item) {
        const a = item.mapToItem(null, 0, 0);
        return { x: a.x, y: a.y, w: item.width, h: item.height };
    }

    function state() {
        const hint = [];
        for (let i = 0; i < hintRepeater.count; i++)
            hint.push(hintRepeater.itemAt(i).keyLabel + " " + hintRepeater.itemAt(i).wordLabel);
        return JSON.stringify({
            loaded: true,
            open: shown,
            kind: seen?.kind ?? null,
            heading: headingItem().text,
            // The heading's chip, pill or line as drawn, for a check that reads the screen.
            headingBox: box(look.label.kind === "header" ? header : headingItem().parent),
            hint: hint.join("  "),
            description: descriptionText.text,
            descriptionLines: descriptionText.lineCount,
            error: errorText.visible ? errorText.text : "",
            // The error line as drawn: cut short when it is longer than the card.
            errorTruncated: errorText.truncated,
            errorRight: errorText.mapToItem(null, errorText.contentWidth, 0).x,
            field: input.text.length,
            masked: input.echoMode === TextInput.Password,
            motion: motion.curves?.kind ?? null,
            settled: motion.settled,
            drawing: prompt.visible,
            cardBox: card.drawnBox()
        });
    }

    Component.onCompleted: Root.State.loaded.push("pinentry")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "pinentry")
    visible: motion.drawing

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(prompt.c.paper, card.style.wash)
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 3)
        width: 520
        height: column.implicitHeight
        tokens: prompt.theme.tokens
        label: prompt.words.heading
        motion: prompt.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            // The heading in the launcher's label idiom: Paper's ink chip, Artboard's pill, Blueprint's header line.
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 20
                Layout.bottomMargin: 10

                Text {
                    id: header
                    visible: prompt.look.label.kind === "header"
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: prompt.words.heading
                    color: prompt.look.small.color
                    font.family: prompt.look.small.font
                    font.pixelSize: prompt.look.small.size
                    font.letterSpacing: prompt.look.small.spacing
                }

                Rectangle {
                    visible: prompt.look.label.kind === "chip"
                    implicitWidth: chip.implicitWidth + 14
                    implicitHeight: chip.implicitHeight + 6
                    color: prompt.look.label.fill
                    Text {
                        id: chip
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: prompt.words.heading
                        color: prompt.look.label.color
                        font.family: prompt.fonts.ui
                        font.pixelSize: 10
                        font.letterSpacing: 1.4
                    }
                }

                Rectangle {
                    visible: prompt.look.label.kind === "pill"
                    implicitWidth: pill.implicitWidth + 18
                    implicitHeight: pill.implicitHeight + 6
                    radius: 8
                    color: prompt.look.label.fill
                    Text {
                        id: pill
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: prompt.words.heading
                        color: prompt.look.label.color
                        font.family: prompt.fonts.ui
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }

            // gpg's description keeps its own line breaks, up to three lines.
            Text {
                id: descriptionText
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: prompt.confirm ? 16 : 0
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: V.inOrder(prompt.seen?.description).trim()
                color: prompt.c.ink
                font.family: prompt.fonts.ui
                font.pixelSize: 14
                lineHeight: 1.2
            }

            Rectangle {
                id: fieldBox
                visible: !prompt.confirm
                Layout.fillWidth: true
                Layout.margins: 20
                implicitHeight: 44
                color: "transparent"
                border.width: 1
                border.color: prompt.c.ink

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: prompt.c.ink
                    font.family: prompt.fonts.ui
                    font.pixelSize: 16
                    clip: true
                    cursorDelegate: prompt.look.caret === "block" ? blockCaret : null
                    Keys.onReturnPressed: prompt.submit()
                    Keys.onEnterPressed: prompt.submit()
                    Keys.onEscapePressed: prompt.close()
                }

                Text {
                    textFormat: Text.PlainText
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    text: V.line(prompt.seen?.prompt).replace(/:$/, "") || "Passphrase"
                    color: prompt.c.muted
                    font.family: prompt.fonts.ui
                    font.pixelSize: 16
                }
            }

            // A confirmation has no field, so the card itself takes the keys.
            Item {
                id: confirmKeys
                Keys.onReturnPressed: prompt.submit()
                Keys.onEnterPressed: prompt.submit()
                Keys.onEscapePressed: prompt.close()
            }

            Text {
                id: errorText
                visible: text !== ""
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 10
                text: P.errorLine(prompt.seen?.error ?? "")
                elide: Text.ElideRight
                color: prompt.c.danger
                font.family: prompt.look.small.font
                font.pixelSize: prompt.look.small.size
                font.letterSpacing: prompt.look.small.spacing
            }

            // The key strip as the launcher's legend draws it: chips in Artboard, tracked caps in Paper, brackets in Blueprint.
            Row {
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 16
                spacing: prompt.look.legend("").chips ? 8 : 14

                Repeater {
                    id: hintRepeater
                    model: prompt.words.keys

                    Rectangle {
                        id: keyPair
                        required property var modelData
                        readonly property string keyLabel: keyText.text
                        readonly property string wordLabel: wordText.text
                        width: pairRow.implicitWidth + (prompt.look.legend("").chips ? 14 : 0)
                        height: pairRow.implicitHeight + (prompt.look.legend("").chips ? 6 : 0)
                        radius: 6
                        color: prompt.look.chip.fill

                        Row {
                            id: pairRow
                            anchors.centerIn: parent
                            spacing: prompt.look.legend("").chips ? 6 : 5

                            Text {
                                id: keyText
                                textFormat: Text.PlainText
                                text: keyPair.modelData.key
                                color: prompt.look.chip.key
                                font.family: prompt.fonts.mono
                                font.pixelSize: prompt.look.small.size
                                font.letterSpacing: prompt.look.small.spacing
                                font.bold: true
                            }
                            Text {
                                id: wordText
                                textFormat: Text.PlainText
                                text: keyPair.modelData.word
                                color: prompt.c.muted
                                font.family: prompt.look.small.font
                                font.pixelSize: prompt.look.small.size
                                font.letterSpacing: prompt.look.small.spacing
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: blockCaret

        Rectangle {
            width: 11
            height: input.font.pixelSize
            color: prompt.look.prompt.color
            // Qt hides only its own caret when the field loses focus, so a delegate follows cursorVisible itself.
            visible: input.cursorVisible

            RectangularShadow {
                anchors.fill: parent
                z: -1
                blur: 9.6
                color: Qt.alpha(prompt.look.prompt.color, 0.8)
            }
        }
    }
}

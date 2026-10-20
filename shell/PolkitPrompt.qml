import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/voice.mjs" as V

// The one Overlay prompt a polkit request shows, drawn in the Surfaces window.
Item {
    id: prompt

    required property var theme
    property bool shown: false
    // The agent's AuthFlow while a request runs.
    property var flow: null
    // The request's text as the card draws it, copied, since the agent may delete a cancelled request while its close still plays.
    property var seen: null
    readonly property var asked: flow ? {
        message: flow.message,
        inputPrompt: flow.inputPrompt,
        responseVisible: flow.responseVisible,
        supplementaryMessage: flow.supplementaryMessage,
        supplementaryIsError: flow.supplementaryIsError
    } : null
    onAskedChanged: if (asked)
        seen = asked

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: V.listLook(theme.tokens)
    readonly property Root.Motion motion: Root.Motion {
        shown: prompt.shown
        tokens: prompt.theme.tokens
        onDrawingChanged: if (!drawing)
            prompt.seen = null
    }

    function show(f) {
        flow = f;
        input.text = "";
        shown = true;
        input.forceActiveFocus();
    }

    // Hiding the prompt, by Esc or by another surface opening, cancels the request it holds.
    function close() {
        if (!shown)
            return;
        const f = flow;
        shown = false;
        input.text = "";
        flow = null;
        if (f && !f.isCompleted)
            f.cancelAuthenticationRequest();
    }

    // The request ended on its own: answered, or cancelled by the daemon.
    function finish() {
        flow = null;
        shown = false;
        input.text = "";
    }

    function submit() {
        if (!flow)
            return;
        flow.submit(input.text);
        input.text = "";
    }

    function swapped() {
    }

    function state() {
        // The hint as drawn, read from its key items.
        const hint = [];
        for (let i = 0; i < hintRepeater.count; i++)
            hint.push(hintRepeater.itemAt(i).keyLabel + " " + hintRepeater.itemAt(i).wordLabel);
        return JSON.stringify({
            heading: (look.label.kind === "header" ? header : look.label.kind === "pill" ? pill : chip).text,
            hint: hint.join("  "),
            open: shown,
            motion: motion.curves?.kind ?? null,
            settleMs: motion.settleMs,
            settled: motion.settled,
            drawing: prompt.visible,
            cardBox: card.drawnBox(),
            message: flow?.message ?? "",
            drawnMessage: messageText.text,
            prompt: flow?.inputPrompt ?? "",
            error: flow?.supplementaryIsError ? flow.supplementaryMessage : "",
            field: input.text.length
        });
    }

    Connections {
        target: prompt.flow
        function onIsCompletedChanged() {
            if (prompt.flow?.isCompleted)
                prompt.finish();
        }
    }

    Component.onCompleted: Root.State.loaded.push("polkit")
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
        label: "Authenticate"
        motion: prompt.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            // The title in the launcher's label idiom: Paper's ink chip, Artboard's pill, Blueprint's header line.
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 20
                Layout.bottomMargin: 10

                Text {
                    id: header
                    visible: prompt.look.label.kind === "header"
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: prompt.look.heading("authenticate", "")
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
                        text: prompt.look.heading("authenticate", "")
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
                        text: prompt.look.heading("authenticate", "")
                        color: prompt.look.label.color
                        font.family: prompt.fonts.ui
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }

            Text {
                id: messageText
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                wrapMode: Text.Wrap
                text: V.inOrder(prompt.seen?.message)
                color: prompt.c.ink
                font.family: prompt.fonts.display
                font.pixelSize: 22
            }

            Rectangle {
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
                    echoMode: prompt.seen?.responseVisible ? TextInput.Normal : TextInput.Password
                    color: prompt.c.ink
                    font.family: prompt.fonts.ui
                    font.pixelSize: 16
                    clip: true
                    Keys.onReturnPressed: prompt.submit()
                    Keys.onEnterPressed: prompt.submit()
                    Keys.onEscapePressed: prompt.close()
                }

                Text {
                    textFormat: Text.PlainText
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    text: V.inOrder(prompt.seen?.inputPrompt) || "Password"
                    color: prompt.c.muted
                    font.family: prompt.fonts.ui
                    font.pixelSize: 16
                }
            }

            // The daemon's word replaces the key hint while it has one.
            Text {
                visible: !!prompt.seen?.supplementaryMessage
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 16
                wrapMode: Text.Wrap
                text: V.inOrder(prompt.seen?.supplementaryMessage)
                color: prompt.seen?.supplementaryIsError ? prompt.c.danger : prompt.c.muted
                font.family: prompt.fonts.ui
                font.pixelSize: 10
                font.letterSpacing: 1.2
            }

            // The key hint as the launcher's legend draws it: chips in Artboard, tracked caps in Paper, brackets in Blueprint.
            Row {
                visible: !prompt.seen?.supplementaryMessage
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 16
                spacing: prompt.look.legend("").chips ? 8 : 14

                Repeater {
                    id: hintRepeater
                    model: prompt.look.keys([["↵", "authenticate"], ["esc", "cancel"]])

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
}

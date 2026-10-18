import QtQuick
import QtQuick.Layouts
import "." as Root

// The one Overlay prompt a polkit request shows, drawn in the Surfaces window.
Item {
    id: prompt

    required property var theme
    property bool shown: false
    // The agent's AuthFlow while a request runs.
    property var flow: null

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})

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
        shown = false;
        input.text = "";
        if (flow && !flow.isCompleted)
            flow.cancelAuthenticationRequest();
        flow = null;
    }

    // The agent calls this once the request has ended on its own.
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
        return JSON.stringify({
            open: shown,
            message: flow?.message ?? "",
            prompt: flow?.inputPrompt ?? "",
            error: flow?.supplementaryIsError ? flow.supplementaryMessage : "",
            field: input.text.length
        });
    }

    Component.onCompleted: Root.State.loaded.push("polkit")
    visible: shown

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

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.margins: 20
                Layout.bottomMargin: 6
                text: "AUTHENTICATE"
                color: prompt.c.muted
                font.family: prompt.fonts.ui
                font.pixelSize: 10
                font.letterSpacing: 1.4
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                wrapMode: Text.Wrap
                text: prompt.flow?.message ?? ""
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
                    echoMode: prompt.flow?.responseVisible ? TextInput.Normal : TextInput.Password
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
                    text: prompt.flow?.inputPrompt || "Password"
                    color: prompt.c.muted
                    font.family: prompt.fonts.ui
                    font.pixelSize: 16
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 16
                wrapMode: Text.Wrap
                text: prompt.flow?.supplementaryMessage ? prompt.flow.supplementaryMessage : "↵ AUTHENTICATE · ESC CANCEL"
                color: prompt.flow?.supplementaryIsError ? prompt.c.danger : prompt.c.muted
                font.family: prompt.fonts.ui
                font.pixelSize: 10
                font.letterSpacing: 1.2
            }
        }
    }
}

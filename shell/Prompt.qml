import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as IT
import "lib/voice.mjs" as V

// Board 7's prompt, drawn inside the island at 520 px: a 36 px icon circle with a bold title and a muted detail, the surface it returns to as a muted chip, the request, a 44 px field or a 30 px bold code, a red line for a wrong answer, then a quiet and an inverted button on the right.
ColumnLayout {
    id: prompt

    required property var theme
    property int glyph: 0
    property string title: ""
    property string detail: ""
    // The surface this prompt hands the island back to, as words; empty over the resting island.
    property string chip: ""
    property string request: ""
    property bool field: false
    property bool secret: true
    property string placeholder: ""
    property string code: ""
    property string error: ""
    property string quiet: "Cancel"
    // Empty for a prompt with Cancel alone.
    property string primary: ""
    // The Click names of the buttons, so a check can press them.
    property string clickName: "prompt"
    readonly property alias input: entry

    signal quietTapped
    signal primaryTapped
    // Enter and Esc in the field.
    signal entered
    signal escaped

    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? IT.islandTones(tokens) : ({ muted: "gray", danger: "red" })

    // The prompt as drawn, for state(): never the field's text, only its length.
    function drawn() {
        return {
            title: titleText.text,
            detail: detailText.text,
            chip: chipBox.visible ? chipText.text : null,
            request: requestText.text,
            field: entry.visible ? { length: entry.text.length, secret: entry.echoMode === TextInput.Password, h: fieldBox.height } : null,
            code: codeText.visible ? { text: codeText.text, px: codeText.font.pixelSize, bold: codeText.font.weight >= Font.Bold } : null,
            error: errorText.visible ? { text: errorText.text, color: String(errorText.color) } : null,
            buttons: [quietButton, primaryButton].filter(b => b.visible).map(b => ({ text: b.text, inverted: b.inverted, box: b.box() })),
            danger: String(tones.danger),
            width: prompt.width
        };
    }

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Rectangle {
            implicitWidth: 36
            implicitHeight: 36
            radius: 18
            color: Qt.alpha(prompt.on, 0.12)

            Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: prompt.glyph ? String.fromCodePoint(prompt.glyph) : ""
                color: prompt.on
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 17
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                id: titleText
                Layout.fillWidth: true
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: V.inOrder(prompt.title)
                color: prompt.on
                font.family: prompt.fonts.ui ?? ""
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            Text {
                id: detailText
                Layout.fillWidth: true
                visible: text !== ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: V.inOrder(prompt.detail)
                color: prompt.tones.muted
                font.family: prompt.fonts.ui ?? ""
                font.pixelSize: 12
            }
        }

        // The surface under the prompt, which comes back once it is answered.
        Rectangle {
            id: chipBox
            visible: prompt.chip !== ""
            Layout.alignment: Qt.AlignTop
            implicitWidth: chipText.implicitWidth + 16
            implicitHeight: 22
            radius: 11
            color: Qt.alpha(prompt.on, 0.08)

            Text {
                id: chipText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: prompt.chip
                color: prompt.tones.muted
                font.family: prompt.fonts.ui ?? ""
                font.pixelSize: 11
            }
        }
    }

    Text {
        id: requestText
        Layout.fillWidth: true
        Layout.topMargin: 14
        visible: text !== ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 6
        elide: Text.ElideRight
        text: V.inOrder(prompt.request)
        color: prompt.tones.muted
        font.family: prompt.fonts.ui ?? ""
        font.pixelSize: 13
    }

    Rectangle {
        id: fieldBox
        visible: prompt.field
        Layout.fillWidth: true
        Layout.topMargin: 12
        implicitHeight: 44
        radius: 12
        color: Qt.alpha(prompt.on, 0.08)
        border.width: prompt.error !== "" ? 1 : 0
        border.color: prompt.tones.danger

        TextInput {
            id: entry
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            echoMode: prompt.secret ? TextInput.Password : TextInput.Normal
            color: prompt.on
            font.family: prompt.fonts.ui ?? ""
            font.pixelSize: 15
            clip: true
            Keys.onReturnPressed: prompt.entered()
            Keys.onEnterPressed: prompt.entered()
            Keys.onEscapePressed: prompt.escaped()
        }

        Text {
            visible: entry.text === ""
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            width: parent.width - 28
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: V.inOrder(prompt.placeholder)
            color: prompt.tones.muted
            font.family: prompt.fonts.ui ?? ""
            font.pixelSize: 15
        }
    }

    Text {
        id: codeText
        visible: prompt.code !== ""
        Layout.fillWidth: true
        Layout.topMargin: 10
        textFormat: Text.PlainText
        text: prompt.code
        color: prompt.on
        font.family: prompt.fonts.ui ?? ""
        font.pixelSize: 30
        font.weight: Font.Bold
        font.letterSpacing: 4
    }

    // A wrong answer: one line in the danger tone, the field cleared above it.
    Text {
        id: errorText
        visible: prompt.error !== ""
        Layout.fillWidth: true
        Layout.topMargin: 8
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: V.inOrder(prompt.error)
        color: prompt.tones.danger
        font.family: prompt.fonts.ui ?? ""
        font.pixelSize: 12
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 16
        spacing: 8

        Item {
            Layout.fillWidth: true
        }
        PromptButton {
            id: quietButton
            text: prompt.quiet
            inverted: false
            clickName: prompt.clickName + "-quiet"
            onTapped: prompt.quietTapped()
        }
        PromptButton {
            id: primaryButton
            visible: prompt.primary !== ""
            text: prompt.primary
            inverted: true
            clickName: prompt.clickName + "-primary"
            onTapped: prompt.primaryTapped()
        }
    }

    // A quiet button is a faint fill with the island's text; the primary is inverted, the island's text as its fill.
    component PromptButton: Rectangle {
        id: button
        property string text: ""
        property bool inverted: false
        property string clickName: ""
        signal tapped

        function box() {
            const a = mapToItem(null, 0, 0);
            return { x: a.x, y: a.y, w: width, h: height };
        }

        implicitWidth: label.implicitWidth + 28
        implicitHeight: 34
        radius: 10
        color: inverted ? prompt.on : Qt.alpha(prompt.on, 0.1)

        Text {
            id: label
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: button.text
            color: button.inverted ? prompt.fill : prompt.on
            font.family: prompt.fonts.ui ?? ""
            font.pixelSize: 13
            font.weight: Font.Bold
        }
        Root.Click {
            name: button.clickName
            onTapped: button.tapped()
        }
    }
}

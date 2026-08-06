import QtQuick

// Bordered single-line input (passphrase, DNS, location search). A focused
// TextInput swallows every printable key, so list navigation from inside the
// box goes through moveRequested instead of j/k.
Rectangle {
    id: field

    required property var theme
    property string placeholder: ""
    property bool password: false
    // Focus is imperative on a freshly created field: forceActiveFocus in
    // the same tick as creation loses to the panel's own focus scope work,
    // so both paths defer a tick.
    property bool focusWhen: false
    property real inputMargin: theme.space(2.5)
    property string inputFont: theme.fontMono
    property alias text: input.text

    signal textEdited(string text)
    signal moveRequested(int delta)
    signal accepted
    signal cancelled

    function takeFocus() {
        input.forceActiveFocus();
    }

    function selectAll() {
        input.selectAll();
    }

    implicitHeight: theme.space(8)
    radius: theme.radius(0.75)
    color: theme.surface2
    border.width: theme.borderWidth
    border.color: input.activeFocus ? theme.accent : theme.surface3
    opacity: enabled ? 1 : 0.5

    onFocusWhenChanged: if (focusWhen)
        Qt.callLater(function () {
            input.forceActiveFocus();
        })

    Component.onCompleted: if (focusWhen)
        Qt.callLater(function () {
            input.forceActiveFocus();
        })

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: field.inputMargin
        anchors.rightMargin: field.inputMargin
        verticalAlignment: TextInput.AlignVCenter
        echoMode: field.password ? TextInput.Password : TextInput.Normal
        color: field.theme.textPrimary
        font.family: field.inputFont
        font.pixelSize: field.theme.fontPx(0.917)
        clip: true

        onTextChanged: field.textEdited(text)
        onAccepted: field.accepted()
        Keys.onEscapePressed: field.cancelled()
        Keys.onDownPressed: field.moveRequested(1)
        Keys.onUpPressed: field.moveRequested(-1)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: field.placeholder
            color: field.theme.textMuted
            font.family: field.theme.fontUi
            font.pixelSize: field.theme.fontPx(0.917)
        }
    }
}

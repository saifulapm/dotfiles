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
    // A key with Alt or Ctrl held, offered to the host BEFORE the input sees
    // it. Accept the event to claim it; anything left unaccepted falls
    // through to normal editing.
    //
    // This exists because a TextInput does not ignore Alt chords the way it
    // ignores Ctrl ones: Qt's line control inserts any key event carrying
    // text, and Alt+U carries "u". So Alt+U typed a literal "u" into the box
    // and the panel's key catcher never saw the event at all (measured
    // 2026-08-21 — the pass panel's Alt+U/Alt+O/Alt+E were all dead on
    // arrival, and the search box quietly filled up with letters instead).
    // Key propagation could not have fixed it: the event was accepted, not
    // ignored, so there was nothing left to bubble.
    signal chord(var event)

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

        // Runs ahead of the input's own handling (Keys.priority defaults to
        // BeforeItem), which is the only place a chord can be caught — see
        // the `chord` signal above. Plain keys are untouched and go straight
        // to editing; Return and Escape keep their dedicated handlers.
        Keys.onPressed: event => {
            if (event.modifiers & (Qt.AltModifier | Qt.ControlModifier))
                field.chord(event);
        }

        StyledText {
            theme: field.theme
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: field.placeholder
            role: StyledText.Body
            muted: true
        }
    }
}

import QtQuick
import "." as Root
import "lib/bt-pairing.mjs" as P

// A Bluetooth pairing request as board 7's prompt, drawn inside the island over whatever it covers: a code to compare or to type on the device at 30 px, or a field for a PIN or passkey, then Reject and Pair, Deny and Allow, or Cancel alone.
Item {
    id: prompt

    required property var theme
    property bool shown: false
    // The surface this prompt returns to, as its chip's words; the surfaces' window sets it.
    property string chip: ""
    // True once the island has come to rest on the prompt; the surfaces' window sets it.
    property bool settled: false
    // The request as drawn, copied, so the card keeps its words while the island draws it on its way out.
    property var seen: null
    readonly property var words: P.promptOf(seen ?? {
            kind: "confirm",
            device: "",
            code: ""
        })
    // The island reports this as its takeover while the prompt shows, and grows to this width for it (board 7).
    readonly property string name: "pairing"
    readonly property int wantWidth: 520
    implicitHeight: card.implicitHeight + 40

    // The surfaces' window calls this for each request Pairing makes current, once it has taken the island over.
    function show() {
        seen = Root.Pairing.current.request;
        shown = true;
        keys.forceActiveFocus();
    }

    // Esc, Reject or a click outside answers no; Pairing then moves on to the next request or to none.
    function close() {
        if (shown)
            Root.Pairing.answer(false);
    }

    function swapped() {
    }

    function state() {
        const d = card.drawn();
        return JSON.stringify({
            open: shown,
            settled: prompt.settled,
            drawing: prompt.visible,
            keyboard: keys.activeFocus,
            kind: seen?.kind ?? "",
            glyph: card.glyph,
            title: d.title,
            detail: d.detail,
            chip: d.chip,
            code: d.code,
            // The field's length and height as drawn.
            field: d.field,
            buttons: d.buttons,
            width: prompt.width
        });
    }

    // Answered, rejected or hung up, the request leaves Pairing, and the prompt goes with it; a waiting one shows next through show().
    Connections {
        target: Root.Pairing
        function onCurrentChanged() {
            if (!Root.Pairing.current)
                prompt.shown = false;
        }
    }

    Component.onCompleted: Root.Pairing.prompt = prompt

    // A press anywhere on the prompt is on its card, so the surfaces' window never takes it for a click outside.
    Item {
        objectName: "card"
        anchors.fill: parent
    }

    // Every key goes to Pairing, which knows each kind's: Enter answers yes, Esc no, and a PIN or passkey takes what is typed.
    Item {
        id: keys
        Keys.onPressed: event => {
            Root.Pairing.key(event);
            event.accepted = true;
        }
    }

    Root.Prompt {
        id: card
        x: 20
        y: 20
        width: parent.width - 40
        theme: prompt.theme
        clickName: "pairing"
        glyph: prompt.words.glyph
        title: prompt.words.title
        detail: prompt.words.detail
        chip: prompt.chip
        field: prompt.words.field
        secret: false
        placeholder: prompt.words.placeholder
        code: prompt.words.code
        quiet: prompt.words.quiet
        primary: prompt.words.primary
        onQuietTapped: prompt.close()
        onPrimaryTapped: Root.Pairing.key({
            key: Qt.Key_Return,
            modifiers: 0,
            text: ""
        })
    }

    // The field draws what Pairing holds, and a click on it never takes the keys from the prompt.
    Binding {
        target: card.input
        property: "text"
        value: Root.Pairing.pin
    }

    Binding {
        target: card.input
        property: "activeFocusOnPress"
        value: false
    }
}

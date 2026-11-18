import QtQuick
import "." as Root
import "lib/pinentry.mjs" as P

// A gpg request as board 7's prompt, drawn inside the island over whatever it covers: a passphrase asks with Cancel and Unlock, a confirmation with Deny and Allow, and a wrong passphrase comes back with its error line.
Item {
    id: prompt

    required property var theme
    property bool shown: false
    // {kind, description, prompt, error, answer} from the Pinentry service, while a request shows.
    property var request: null
    // The request as the prompt draws it, kept after it closes since the island still draws it on its way out.
    property var seen: null
    // The surface this prompt returns to, as its chip's words; the surfaces' window sets it.
    property string chip: ""
    // True once the island has come to rest on the prompt; the surfaces' window sets it.
    property bool settled: false
    readonly property var words: P.cardWords(seen?.kind ?? "passphrase")
    // The island reports this as its takeover while the prompt shows, and grows to this width for it (board 7).
    readonly property string name: "pinentry"
    readonly property int wantWidth: 520
    implicitHeight: card.implicitHeight + 40

    function show(r) {
        request = r;
        seen = r;
        card.input.text = "";
        shown = true;
        (words.field ? card.input : keys).forceActiveFocus();
    }

    function reply(text) {
        const r = request;
        request = null;
        shown = false;
        card.input.text = "";
        r?.answer(text);
    }

    function submit() {
        if (!request)
            return;
        if (seen.kind === "confirm")
            reply(P.ALLOW);
        else if (words.field)
            reply(P.pinAnswer(card.input.text));
    }

    // Esc, Cancel or Deny answers the request so gpg never waits on a prompt nobody sees.
    function close() {
        if (request)
            reply(seen.kind === "confirm" ? P.DENY : P.CANCEL);
    }

    // gpg went away on its own, so there is nothing to answer.
    function dismiss() {
        request = null;
        shown = false;
        card.input.text = "";
    }

    function swapped() {
    }

    function state() {
        const d = card.drawn();
        return JSON.stringify({
            loaded: true,
            open: shown,
            settled: prompt.settled,
            drawing: prompt.visible,
            keyboard: card.input.activeFocus || keys.activeFocus,
            kind: seen?.kind ?? null,
            description: seen?.description ?? "",
            drawnDescription: d.request,
            // The error line as drawn, "" when there is none.
            error: d.error ? d.error.text : "",
            // The field's length, never its text.
            field: card.input.text.length,
            title: d.title,
            detail: d.detail,
            chip: d.chip,
            drawnField: d.field,
            wrong: d.error,
            danger: d.danger,
            buttons: d.buttons,
            width: prompt.width
        });
    }

    Component.onCompleted: Root.State.loaded.push("pinentry")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "pinentry")

    // A press anywhere on the prompt is on its card, so the surfaces' window never takes it for a click outside.
    Item {
        objectName: "card"
        anchors.fill: parent
    }

    // A confirmation has no field, so this takes its keys.
    Item {
        id: keys
        Keys.onReturnPressed: prompt.submit()
        Keys.onEnterPressed: prompt.submit()
        Keys.onEscapePressed: prompt.close()
    }

    Root.Prompt {
        id: card
        x: 20
        y: 20
        width: parent.width - 40
        theme: prompt.theme
        clickName: "pinentry"
        glyph: 0xF0306
        title: prompt.words.title
        detail: prompt.words.detail
        chip: prompt.chip
        request: prompt.seen?.description ?? ""
        field: prompt.words.field
        placeholder: "Passphrase"
        error: P.errorLine(prompt.seen?.error ?? "")
        quiet: prompt.words.quiet
        primary: prompt.words.primary
        onQuietTapped: prompt.close()
        onPrimaryTapped: prompt.submit()
        onEntered: prompt.submit()
        onEscaped: prompt.close()
    }
}

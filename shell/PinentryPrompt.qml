import QtQuick
import "." as Root
import "lib/takeover.mjs" as T
import "lib/pinentry.mjs" as P

// A gpg request as board 7's prompt, drawn inside the island over whatever it covers: a passphrase asks with Cancel and Unlock, a confirmation with Deny and Allow, and a wrong passphrase comes back with its error line.
Item {
    id: prompt

    required property var theme
    property bool shown: false
    // {kind, description, prompt, error, answer, hangUp} from the Pinentry service, while a request shows.
    property var request: null
    // Answered, while gpg-agent checks the answer: the field is empty and inert, and only Esc or Cancel does anything.
    property bool checking: false
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

    // When the prompt last showed; Enter does nothing for half a second after it (29PTQZ0V).
    property real shownAt: 0

    function show(r) {
        shownAt = Date.now();
        request = r;
        seen = r;
        checking = false;
        card.input.text = "";
        shown = true;
        (words.field ? card.input : keys).forceActiveFocus();
    }

    // The prompt stays shown after an answer until gpg-agent asks again or its pinentry hangs up, so the island never hands back in between; keys go to the inert keys item meanwhile.
    function reply(text) {
        const r = request;
        request = null;
        checking = true;
        card.input.text = "";
        keys.forceActiveFocus();
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

    // Esc, Cancel or Deny answers the request so gpg never waits on a prompt nobody sees, then hangs up, which also cancels a check under way.
    function close() {
        if (!shown)
            return;
        const r = seen;
        if (request)
            reply(seen.kind === "confirm" ? P.DENY : P.CANCEL);
        r.hangUp();
    }

    // gpg went away on its own, so there is nothing to answer.
    function dismiss() {
        request = null;
        checking = false;
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
            checking: prompt.checking,
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
        Keys.onReturnPressed: if (T.enterReady(prompt.shownAt, Date.now()))
            prompt.submit()
        Keys.onEnterPressed: if (T.enterReady(prompt.shownAt, Date.now()))
            prompt.submit()
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
        input.enabled: !prompt.checking
        error: P.errorLine(prompt.seen?.error ?? "")
        quiet: prompt.words.quiet
        primary: prompt.words.primary
        onQuietTapped: prompt.close()
        onPrimaryTapped: prompt.submit()
        onEntered: if (T.enterReady(prompt.shownAt, Date.now()))
            prompt.submit()
        onEscaped: prompt.close()
    }
}

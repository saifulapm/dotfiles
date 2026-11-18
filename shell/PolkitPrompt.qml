import QtQuick
import "." as Root
import "lib/takeover.mjs" as T

// A polkit request as board 7's prompt, drawn inside the island over whatever it covers: Cancel and Allow, the password field, and a red line after a wrong password.
Item {
    id: prompt

    required property var theme
    property bool shown: false
    property int submits: 0
    // The agent's AuthFlow while a request runs.
    property var flow: null
    // The request's text as the prompt draws it, copied, since the agent may delete a cancelled request while the island still draws it on its way out.
    property var seen: null
    // The surface this prompt returns to, as its chip's words; the surfaces' window sets it.
    property string chip: ""
    // True once the island has come to rest on the prompt; the surfaces' window sets it.
    property bool settled: false
    // A wrong password's line, until the next key.
    property string wrong: ""
    // When the prompt last showed; Enter does nothing for half a second after it (29PTQZ0V).
    property real shownAt: 0
    readonly property var asked: flow ? {
        message: flow.message,
        inputPrompt: flow.inputPrompt,
        responseVisible: flow.responseVisible,
        supplementaryMessage: flow.supplementaryMessage,
        supplementaryIsError: flow.supplementaryIsError
    } : null
    onAskedChanged: if (asked)
        seen = asked
    // The island reports this as its takeover while the prompt shows, and grows to this width for it (board 7).
    readonly property string name: "polkit"
    readonly property int wantWidth: 520
    implicitHeight: card.implicitHeight + 40

    function show(f) {
        flow = f;
        shownAt = Date.now();
        wrong = "";
        card.input.text = "";
        shown = true;
        card.input.forceActiveFocus();
    }

    // Hiding the prompt, by Esc, Cancel or a click outside, cancels the request it holds.
    function close() {
        if (!shown)
            return;
        const f = flow;
        shown = false;
        card.input.text = "";
        flow = null;
        if (f && !f.isCompleted)
            f.cancelAuthenticationRequest();
    }

    // The request ended on its own: answered, or cancelled by the daemon.
    function finish() {
        flow = null;
        shown = false;
        card.input.text = "";
    }

    function submit() {
        if (!flow)
            return;
        flow.submit(card.input.text);
        card.input.text = "";
        submits += 1;
    }

    function swapped() {
    }

    function state() {
        const d = card.drawn();
        return JSON.stringify({
            open: shown,
            settled: prompt.settled,
            drawing: prompt.visible,
            keyboard: card.input.activeFocus,
            message: flow?.message ?? "",
            drawnMessage: d.request,
            prompt: flow?.inputPrompt ?? "",
            error: flow?.supplementaryIsError ? flow.supplementaryMessage : "",
            // The field's length, never its text.
            field: card.input.text.length,
            // How many answers this shell has handed a request, by Enter or by Allow.
            submits: submits,
            shownAt: shownAt,
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

    Connections {
        target: prompt.flow
        function onIsCompletedChanged() {
            if (prompt.flow?.isCompleted)
                prompt.finish();
        }
        // PAM refused the password; the agent starts a fresh session, so the prompt stays with its field cleared.
        function onAuthenticationFailed() {
            card.input.text = "";
            prompt.wrong = "Wrong password, try again";
        }
    }

    Component.onCompleted: Root.State.loaded.push("polkit")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "polkit")

    // A press anywhere on the prompt is on its card, so the surfaces' window never takes it for a click outside.
    Item {
        objectName: "card"
        anchors.fill: parent
    }

    Root.Prompt {
        id: card
        x: 20
        y: 20
        width: parent.width - 40
        theme: prompt.theme
        clickName: "polkit"
        glyph: 0xF099D
        title: "Authentication required"
        detail: prompt.seen?.inputPrompt ? prompt.seen.inputPrompt.replace(/:\s*$/, "") : "Password"
        chip: prompt.chip
        request: prompt.seen?.message ?? ""
        field: true
        secret: !prompt.seen?.responseVisible
        placeholder: "Password"
        // A wrong password reads as its own line; the daemon's own error word, when it has one, takes its place.
        error: prompt.wrong !== "" ? prompt.wrong : prompt.seen?.supplementaryIsError ? prompt.seen.supplementaryMessage : ""
        quiet: "Cancel"
        primary: "Allow"
        onQuietTapped: prompt.close()
        onPrimaryTapped: prompt.submit()
        onEntered: if (T.enterReady(prompt.shownAt, Date.now()))
            prompt.submit()
        onEscaped: prompt.close()
    }

    Connections {
        target: card.input
        function onTextChanged() {
            if (card.input.text !== "")
                prompt.wrong = "";
        }
    }
}

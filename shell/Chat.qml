import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T
import "lib/chat.mjs" as C
import "lib/chat-tools.mjs" as M

// The AI chat inside the island, as board 6 draws it: Saiful's messages in a bubble, replies streamed from pxy as Markdown blocks, each closed block drawn once and kept.
Item {
    id: chat

    required property var theme
    property bool shown: false
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1
    // pxy's alias this chat asks, and the model pxy last answered with.
    property string alias: "chat"
    property string model: ""
    // When this conversation started, in ms since the epoch, or 0 before its first message.
    property real conversation: 0
    property string title: ""
    // The messages as pxy reads them: role and content, oldest first.
    property var messages: []
    property bool streaming: false
    // pxy's own line when the last request failed, else empty.
    property string error: ""
    // The reply streaming now, or the last one: its text so far and its blocks as drawn.
    property string replyText: ""
    property int replyBlocks: 0
    // How many of the reply's blocks have closed, each drawn once.
    property int replyClosed: 0
    // Where the keys go: the field, or the reply list with one block picked (a row of rows).
    property string focusArea: "input"
    property int pick: -1
    // Each finished reply's first row and its whole text, so Y copies the reply a picked block is in.
    property var replies: []
    // A reply that finished while the chat was closed, until the chat opens again.
    property bool unseen: false
    // A reply streaming outlives the surface's close; the card stays loaded until it ends and is seen.
    readonly property bool busy: streaming || unseen
    readonly property string url: Quickshell.env("DOTS_CHAT_URL") || "http://127.0.0.1:4100/v1/chat/completions"

    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property color tile: Qt.alpha(on, 0.07)
    readonly property color bubble: Qt.alpha(on, 0.12)
    // The danger tone as a colour, so a check compares it with what the alert draws in.
    readonly property color dangerTone: tones.danger
    // Code sits on a panel darker than the island's fill.
    readonly property color panel: Qt.darker(fill, 1.35)
    // The island reports this as its surface while the chat shows, and grows to this width for it (board 6).
    readonly property string name: "chat"
    readonly property int wantWidth: 640
    // True once the island has come to rest on the chat; the surfaces' window sets it.
    property bool settled: false
    implicitHeight: card.height

    // The XMLHttpRequest of the reply streaming now, and its readers.
    property var xhr: null
    property var reader: null
    property var cutter: null
    // Where this reply's rows start in the list.
    property int replyRow: 0
    // The tool calls this round streams, gathered by their index, and how many calls this turn has used of its 10.
    property var calls: []
    property int spent: 0
    // The round's calls still to answer, one mem at a time, and the tool messages answered so far.
    property var queue: []
    property var answered: []
    // The chips drawn in this conversation, as {name, arg}.
    property var tools: []

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        shown = true;
        unseen = false;
        focusInput();
    }

    function close() {
        shown = false;
    }

    // Called on each of the host window's frames; the first one after open() ends the timing.
    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function send() {
        const text = field.text.trim();
        if (text === "" || streaming)
            return;
        field.text = "";
        if (!conversation) {
            conversation = Date.now();
            title = text.split("\n")[0].slice(0, 60);
        }
        messages = messages.concat([{ role: "user", content: text }]);
        rows.append({ kind: "user", bkind: "", lang: "", html: "", text: text });
        spent = 0;
        ask();
    }

    // The launcher's "? " question, sent as if typed into the field.
    function askFrom(text) {
        field.text = text;
        send();
    }

    // One request to pxy for the conversation so far; its stream is read as it grows.
    function ask() {
        error = "";
        replyText = "";
        replyBlocks = 0;
        replyClosed = 0;
        replyRow = rows.count;
        calls = [];
        reader = C.sse();
        cutter = C.blocks();
        streaming = true;
        const req = new XMLHttpRequest();
        xhr = req;
        req.onreadystatechange = () => {
            if (req !== xhr)
                return;
            if (req.readyState === XMLHttpRequest.LOADING || req.readyState === XMLHttpRequest.DONE)
                read(req);
            if (req.readyState === XMLHttpRequest.DONE)
                finish(req);
        };
        req.open("POST", url);
        req.setRequestHeader("Authorization", "Bearer pxy-local");
        req.setRequestHeader("Content-Type", "application/json");
        req.send(JSON.stringify({ model: alias, stream: true, messages: messages, tools: M.TOOLS }));
    }

    function read(req) {
        if (req.status !== 200)
            return;
        const got = reader.feed(req.responseText);
        let added = "";
        for (const ev of got.events) {
            if (ev.error) {
                error = C.clean(ev.error.message ?? "pxy failed");
                continue;
            }
            if (ev.model)
                model = C.clean(ev.model);
            const delta = ev.choices?.[0]?.delta ?? {};
            for (const piece of delta.tool_calls ?? [])
                gather(piece);
            added += delta.content ?? "";
        }
        if (added === "")
            return;
        replyText += C.clean(added);
        draw(cutter.feed(replyText));
    }

    // Closed blocks are added once and never touched again; only the open block's row is set on each chunk.
    function draw(r) {
        for (let i = replyClosed; i < r.closed.length; i++)
            put(replyRow + i, r.closed[i]);
        replyClosed = r.closed.length;
        let count = replyClosed;
        if (r.open) {
            put(replyRow + count, r.open);
            count += 1;
        }
        while (rows.count > replyRow + count)
            rows.remove(rows.count - 1);
        replyBlocks = count;
    }

    function put(at, block) {
        const row = { kind: "block", bkind: block.kind, lang: block.lang, html: block.html, text: block.text };
        if (at < rows.count)
            rows.set(at, row);
        else
            rows.append(row);
    }

    // A call's id and name come on its first piece and its arguments in pieces after, all under one index.
    function gather(piece) {
        const list = calls;
        const call = list[piece.index] ?? { id: "", type: "function", function: { name: "", arguments: "" } };
        if (piece.id)
            call.id = piece.id;
        if (piece.function?.name)
            call.function.name = piece.function.name;
        call.function.arguments += piece.function?.arguments ?? "";
        list[piece.index] = call;
        calls = list;
    }

    // A tool round: each call draws a chip, then runs or is refused, and the answers go back to pxy in one request.
    function useTools(asked) {
        messages = messages.concat([{ role: "assistant", content: replyText || null, tool_calls: asked }]);
        for (const call of asked) {
            const chip = M.chipFor(call.function.name, call.function.arguments);
            rows.append({ kind: "tool", bkind: chip.name, lang: "", html: "", text: chip.arg });
            tools = tools.concat([chip]);
        }
        const share = M.take(asked, spent);
        spent += share.run.length;
        const todo = [];
        for (const call of share.run) {
            const a = M.argvFor(call.function.name, call.function.arguments);
            todo.push(a.argv ? { id: call.id, argv: a.argv } : { id: call.id, note: "not run: " + a.error });
        }
        for (const call of share.skipped)
            todo.push({ id: call.id, note: "not run: this turn's " + M.CALLS_MAX + " tool calls are spent" });
        queue = todo;
        answered = [];
        next();
    }

    function next() {
        if (!streaming)
            return;
        if (queue.length === 0) {
            messages = messages.concat(answered);
            ask();
            return;
        }
        const job = queue[0];
        queue = queue.slice(1);
        if (!job.argv) {
            answer(job.id, job.note);
            return;
        }
        memRun.callId = job.id;
        memRun.command = ["mem"].concat(job.argv);
        memRun.running = true;
    }

    // The next call starts on a later turn of the event loop, so mem's Process is never restarted from inside its own exit.
    function answer(id, content) {
        answered = answered.concat([{ role: "tool", tool_call_id: id, content: content }]);
        Qt.callLater(chat.next);
    }

    function finish(req) {
        if (req.status === 200) {
            draw(cutter.end(replyText));
            const asked = calls.filter(c => c);
            if (asked.length > 0 && error === "") {
                xhr = null;
                useTools(asked);
                return;
            }
            // A reply that pxy's error cut off stays drawn but is not sent back, so r asks for the message again.
            if (replyText !== "" && error === "") {
                messages = messages.concat([{ role: "assistant", content: replyText }]);
                replies = replies.concat([{ row: replyRow, text: replyText }]);
            }
        } else if (error === "") {
            error = failure(req);
        }
        xhr = null;
        unseen = !shown;
        streaming = false;
    }

    // The stop button ends the turn where it stands: the stream is cut off, what came stays drawn, and no tool call after it runs.
    function stop() {
        if (!streaming)
            return;
        const req = xhr;
        xhr = null;
        queue = [];
        if (req) {
            req.abort();
            draw(cutter.end(replyText));
            if (replyText !== "") {
                messages = messages.concat([{ role: "assistant", content: replyText }]);
                replies = replies.concat([{ row: replyRow, text: replyText }]);
            }
        }
        streaming = false;
    }

    // pxy's own line from its error body, else the HTTP status, else the refused connection.
    function failure(req) {
        if (req.status === 0)
            return "pxy did not answer at " + url;
        let line = "";
        try {
            line = JSON.parse(req.responseText).error?.message ?? "";
        } catch (e) {
            line = "";
        }
        return C.clean(line || ("pxy answered HTTP " + req.status));
    }

    function newChat() {
        if (streaming)
            return;
        rows.clear();
        messages = [];
        replies = [];
        tools = [];
        conversation = 0;
        title = "";
        error = "";
        replyText = "";
        replyBlocks = 0;
        replyClosed = 0;
        pick = -1;
        focusInput();
    }

    function toggleAlias() {
        alias = alias === "chat" ? "default" : "chat";
    }

    // r asks again for the last message after pxy failed it.
    function retry() {
        if (streaming || error === "" || messages.length === 0 || messages[messages.length - 1].role !== "user")
            return;
        ask();
    }

    function blockRows() {
        const out = [];
        for (let i = 0; i < rows.count; i++) {
            if (rows.get(i).kind === "block")
                out.push(i);
        }
        return out;
    }

    // Tab moves to the reply list on its last block, and stops there with nothing picked while there is no reply yet, so Tab cycles the same three stops every time.
    function focusReplies() {
        const found = blockRows();
        pick = found.length ? found[found.length - 1] : -1;
        focusArea = "replies";
        replyKeys.forceActiveFocus();
    }

    function focusInput() {
        focusArea = "input";
        field.forceActiveFocus();
    }

    function move(by) {
        const found = blockRows();
        const next = found[Math.max(0, Math.min(found.length - 1, found.indexOf(pick) + by))];
        if (next !== undefined)
            pick = next;
    }

    function copy(text) {
        textCopier.createObject(chat, { text: text });
    }

    function copyBlock() {
        if (pick >= 0 && pick < rows.count)
            copy(rows.get(pick).text);
    }

    function copyReply() {
        const found = replies.filter(r => r.row <= pick);
        if (found.length)
            copy(found[found.length - 1].text);
    }

    // The last reply's blocks as drawn, so a check reads what the island shows.
    function drawn() {
        const out = [];
        for (let i = replyRow; i < replyRow + replyBlocks && i < rows.count; i++)
            out.push({ kind: rows.get(i).bkind, html: rows.get(i).html });
        return out;
    }

    function state() {
        return JSON.stringify({
            open: shown,
            streaming: streaming,
            unseen: unseen,
            conversation: conversation || null,
            title: title,
            alias: alias,
            model: model,
            blocks: replyBlocks,
            tools: tools,
            error: error,
            rows: rows.count,
            input: field.text,
            focus: focusArea,
            pick: pick,
            drawn: drawn(),
            failure: { drawn: failureLine.visible, retry: retryButton.visible, alert: String(alertGlyph.color) },
            danger: String(dangerTone),
            openMs: openMs,
            opens: opens,
            settled: chat.settled,
            keyboard: chat.Window.active
        });
    }

    ListModel {
        id: rows
    }

    onPickChanged: {
        const item = replyRepeater.itemAt(pick);
        if (!item)
            return;
        if (item.y < list.contentY)
            list.contentY = item.y;
        else if (item.y + item.height > list.contentY + list.height)
            list.contentY = item.y + item.height - list.height;
    }

    // The reply list's keys, held while Tab has moved there.
    Item {
        id: replyKeys
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            const shift = event.modifiers & Qt.ShiftModifier;
            if (ctrl && event.key === Qt.Key_N)
                chat.newChat();
            else if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                chat.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                chat.move(-1);
            else if (event.key === Qt.Key_Y && shift)
                chat.copyReply();
            else if (event.key === Qt.Key_Y)
                chat.copyBlock();
            else if (event.key === Qt.Key_M)
                chat.toggleAlias();
            else if (event.key === Qt.Key_R)
                chat.retry();
            else if (event.key === Qt.Key_Tab)
                chat.focusInput();
            else if (event.key === Qt.Key_Escape)
                chat.close();
            else
                return;
            event.accepted = true;
        }
    }

    // wl-copy serves the copy itself, so it outlives the chat; the text goes on stdin, since one argument is capped at 128 KiB.
    Component {
        id: textCopier

        Process {
            property string text
            running: true
            stdinEnabled: true
            command: ["wl-copy"]
            onStarted: {
                write(text);
                stdinEnabled = false;
            }
            onExited: destroy()
        }
    }

    // mem runs as an argv with no shell, so a query is only ever one argument; a failed run answers with its stderr so the model sees why.
    Process {
        id: memRun
        property string callId: ""
        stdout: StdioCollector {
            id: memOut
        }
        stderr: StdioCollector {
            id: memErr
        }
        onExited: code => chat.answer(callId, M.cut(code === 0 ? memOut.text : memErr.text))
    }

    // The island draws the fill and plays the open; this is the content.
    Item {
        id: card
        objectName: "card"
        width: parent.width
        height: column.implicitHeight + 32

        Column {
            id: column
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 12

            // The conversation's title, the model pill, then the round history and new-chat buttons.
            Item {
                width: column.width
                height: 32

                Text {
                    anchors.left: parent.left
                    anchors.right: pill.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: chat.title || "New chat"
                    color: chat.on
                    font.family: chat.fonts.ui ?? ""
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }

                Rectangle {
                    id: pill
                    anchors.right: historyButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: pillRow.implicitWidth + 20
                    height: 28
                    radius: 14
                    color: chat.tile

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: chat.tones.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: chat.alias
                            color: chat.on
                            font.family: chat.fonts.ui ?? ""
                            font.pixelSize: 12
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: String.fromCodePoint(0xF0140)
                            color: chat.tones.muted
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 14
                        }
                    }
                }

                Rectangle {
                    id: historyButton
                    anchors.right: newButton.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    radius: 14
                    color: chat.tile

                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: String.fromCodePoint(0xF02DA)
                        color: chat.on
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 15
                    }
                }

                Rectangle {
                    id: newButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    radius: 14
                    color: chat.tile

                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: String.fromCodePoint(0xF0415)
                        color: chat.on
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 15
                    }
                }
            }

            // A new chat: a sparkle in a circle and what the chat can do.
            Item {
                visible: rows.count === 0
                width: column.width
                height: visible ? 150 : 0

                Rectangle {
                    id: sparkle
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 24
                    width: 52
                    height: 52
                    radius: 26
                    color: chat.tile

                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: String.fromCodePoint(0xF0674)
                        color: chat.tones.accent
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 24
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: sparkle.bottom
                    anchors.topMargin: 14
                    textFormat: Text.PlainText
                    text: "Ask anything, or about any of your projects"
                    color: chat.tones.muted
                    font.family: chat.fonts.ui ?? ""
                    font.pixelSize: 13
                }
            }

            // The conversation, scrolled to its end while a reply arrives.
            Flickable {
                id: list
                visible: rows.count > 0
                width: column.width
                height: visible ? Math.min(contentHeight, 440) : 0
                contentHeight: messageColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentHeightChanged: if (chat.streaming)
                    contentY = Math.max(0, contentHeight - height)

                Column {
                    id: messageColumn
                    width: list.width
                    spacing: 10

                    Repeater {
                        id: replyRepeater
                        model: rows

                        // The picked block sits on the lit tile while the reply list has the keys.
                        delegate: Item {
                            id: row
                            required property int index
                            required property string kind
                            required property string bkind
                            required property string lang
                            required property string html
                            required property string text
                            width: messageColumn.width
                            height: rowLoader.height

                            Rectangle {
                                visible: chat.focusArea === "replies" && chat.pick === row.index
                                x: -6
                                y: -4
                                width: parent.width + 12
                                height: parent.height + 8
                                radius: 10
                                color: chat.bubble
                            }

                            Loader {
                                id: rowLoader
                                readonly property string bkind: row.bkind
                                readonly property string lang: row.lang
                                readonly property string html: row.html
                                readonly property string text: row.text
                                width: parent.width
                                sourceComponent: row.kind === "user" ? userRow : row.kind === "tool" ? toolRow : row.bkind === "code" ? codeRow : blockRow
                            }
                        }
                    }

                    // pxy's own line under the message it failed, a red alert first, then Retry.
                    Item {
                        id: failureLine
                        visible: chat.error !== "" && !chat.streaming
                        width: messageColumn.width
                        height: visible ? Math.max(failureText.implicitHeight, 26) : 0

                        Text {
                            id: alertGlyph
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: String.fromCodePoint(0xF0028)
                            color: chat.tones.danger
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 16
                        }

                        Text {
                            id: failureText
                            anchors.left: alertGlyph.right
                            anchors.leftMargin: 8
                            anchors.right: retryButton.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            text: chat.error
                            color: chat.on
                            font.family: chat.fonts.ui ?? ""
                            font.pixelSize: 13
                        }

                        Rectangle {
                            id: retryButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: retryLabel.implicitWidth + 22
                            height: 26
                            radius: 13
                            color: chat.tile

                            Text {
                                id: retryLabel
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: "Retry"
                                color: chat.on
                                font.family: chat.fonts.ui ?? ""
                                font.pixelSize: 12
                            }

                            Root.Click {
                                name: "chat-retry"
                                onTapped: chat.retry()
                            }
                        }
                    }

                    // While text streams in, an accent block marks where it arrives.
                    Rectangle {
                        visible: chat.streaming
                        width: 8
                        height: 14
                        radius: 2
                        color: chat.tones.accent
                    }
                }
            }

            // The paperclip, the field, and the round send button that turns into stop while a reply streams.
            Rectangle {
                width: column.width
                height: Math.max(52, field.implicitHeight + 28)
                radius: 16
                color: chat.tile

                Text {
                    id: clip
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(0xF03E2)
                    color: chat.tones.muted
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 18
                }

                TextEdit {
                    id: field
                    anchors.left: clip.right
                    anchors.leftMargin: 10
                    anchors.right: sendButton.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    color: chat.on
                    selectionColor: Qt.alpha(chat.on, 0.3)
                    font.family: chat.fonts.ui ?? ""
                    font.pixelSize: 14
                    focus: true
                    Keys.onPressed: event => {
                        const shift = event.modifiers & Qt.ShiftModifier;
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !shift)
                            chat.send();
                        else if (event.key === Qt.Key_Tab)
                            chat.focusReplies();
                        else if (ctrl && event.key === Qt.Key_N)
                            chat.newChat();
                        else if (event.key === Qt.Key_Escape)
                            chat.close();
                        else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        visible: field.text === ""
                        textFormat: Text.PlainText
                        text: "Ask anything"
                        color: chat.tones.muted
                        font: field.font
                    }
                }

                Rectangle {
                    id: sendButton
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    height: 34
                    radius: 17
                    color: chat.tones.accent

                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: String.fromCodePoint(chat.streaming ? 0xF04DB : 0xF048A)
                        color: chat.fill
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 16
                    }

                    Root.Click {
                        name: "chat-send"
                        onTapped: chat.streaming ? chat.stop() : chat.send()
                    }
                }
            }
        }
    }

    // Saiful's message, right-aligned in a bubble.
    Component {
        id: userRow

        Item {
            implicitHeight: bubbleBox.height

            Rectangle {
                id: bubbleBox
                anchors.right: parent.right
                width: Math.min(parent.width * 0.8, userText.implicitWidth + 28)
                height: userText.implicitHeight + 18
                radius: 14
                color: chat.bubble

                Text {
                    id: userText
                    x: 14
                    y: 9
                    width: Math.min(implicitWidth, bubbleBox.parent.width * 0.8 - 28)
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    text: parent.parent.parent.text
                    color: chat.on
                    font.family: chat.fonts.ui ?? ""
                    font.pixelSize: 13
                }
            }
        }
    }

    // A mem call the model made: a database icon, the tool's name in bold and its argument muted, on a tile.
    Component {
        id: toolRow

        Item {
            readonly property string toolName: parent ? parent.bkind : ""
            readonly property string toolArg: parent ? parent.text : ""
            implicitHeight: 28

            Rectangle {
                width: Math.min(parent.width, chipRow.implicitWidth + 24)
                height: 28
                radius: 14
                color: chat.tile

                Row {
                    id: chipRow
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        id: chipIcon
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: String.fromCodePoint(0xF01BC)
                        color: chat.tones.accent
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 14
                    }

                    Text {
                        id: chipName
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: chipRow.parent.parent.toolName
                        color: chat.on
                        font.family: chat.fonts.ui ?? ""
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, chipRow.parent.parent.width - 40 - chipIcon.width - chipName.width)
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: chipRow.parent.parent.toolArg
                        color: chat.tones.muted
                        font.family: chat.fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    // A paragraph, heading, list, quote or table of the reply, as plain 13 px text with no bubble.
    Component {
        id: blockRow

        Text {
            id: styledBlock
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            text: parent.html
            color: chat.on
            font.family: parent.bkind === "table" ? (chat.fonts.mono ?? "") : (chat.fonts.ui ?? "")
            font.pixelSize: parent.bkind === "heading" ? 15 : 13
            font.weight: parent.bkind === "heading" ? Font.Bold : Font.Normal
            leftPadding: parent.bkind === "quote" ? 12 : 0

            Rectangle {
                visible: parent.parent.bkind === "quote"
                width: 3
                height: parent.height
                radius: 1.5
                color: chat.tones.muted
            }
        }
    }

    // A code block on a darker panel, headed by its language and a copy icon.
    Component {
        id: codeRow

        Rectangle {
            implicitHeight: codeText.implicitHeight + 46
            radius: 12
            color: chat.panel

            Text {
                x: 14
                y: 10
                textFormat: Text.PlainText
                text: parent.parent.lang || "code"
                color: chat.tones.muted
                font.family: chat.fonts.mono ?? ""
                font.pixelSize: 11
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                y: 8
                textFormat: Text.PlainText
                text: String.fromCodePoint(0xF018F)
                color: chat.tones.muted
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 14
            }

            Text {
                id: codeText
                x: 14
                y: 32
                width: parent.width - 28
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                text: parent.parent.text
                color: chat.on
                font.family: chat.fonts.mono ?? ""
                font.pixelSize: 12
            }
        }
    }
}

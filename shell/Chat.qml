import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T
import "lib/chat.mjs" as C
import "lib/chat-tools.mjs" as M
import "lib/chat-history.mjs" as H
import "lib/chat-files.mjs" as F

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
    readonly property bool held: streaming || unseen
    // The island reads a surface's busy as its rows still settling, so a finished reply waiting unseen does not count.
    readonly property bool busy: streaming
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
    // Inline code's tint, mixed opaque into the island's fill, since rich text reads one colour per span.
    readonly property color codeTint: Qt.tint(fill, Qt.alpha(on, 0.14))
    readonly property string codeOpen: '<span style="background-color: ' + String(codeTint) + ';">&nbsp;'
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
    // Counts turns, so a mem run or a deferred step from a turn that stop, a new message or a new chat ended does nothing.
    property int turn: 0
    // The chips drawn in this conversation, as {name, arg}.
    property var tools: []
    // The chat page or the history page, and while history shows, its rows newest first, the files they came from and the row picked.
    property string page: "chat"
    property var listed: []
    property var found: []
    property int historyPick: 0
    // Where each conversation is kept, one JSON file each.
    readonly property string store: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/dots/chat"
    // The files and images waiting above the field for the next message, each {name, size, kind} with its text or its data URL.
    property var attachments: []
    // The line that refused the last file over its limit, else empty.
    property string refusal: ""
    // Paths the picker chose that are still to be measured and read, one at a time.
    property var toRead: []

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
        // Typed or pasted text rides in the message, so it answers to the same 512 KiB as a text file.
        const over = F.check({ name: "the message", kind: "text", size: text.length });
        if (over) {
            refusal = over;
            return;
        }
        field.text = "";
        if (!conversation) {
            conversation = Date.now();
            title = text.split("\n")[0].slice(0, 60);
        }
        const message = { role: "user", content: text };
        if (attachments.length)
            message.attachments = attachments;
        attachments = [];
        refusal = "";
        messages = messages.concat([message]);
        rows.append({ kind: "user", bkind: "", lang: "", html: "", text: text });
        spent = 0;
        turn += 1;
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
        // Attachments go on the wire only inside their message's content, and only the turn whose message has an image asks the vision model.
        const users = messages.filter(m => m.role === "user");
        const last = users.length ? users[users.length - 1] : null;
        // An earlier turn's images stay out of later requests, which a text model would refuse and which would ride again on every turn.
        const wire = messages.map(m => m.attachments ? { role: m.role, content: F.content(m.content, m === last ? m.attachments : m.attachments.filter(a => a.kind !== "image")) } : m);
        const body = { model: F.modelFor(alias, last ? last.attachments : []), stream: true, messages: wire };
        // Once the turn's 10 calls are spent the tools are left out, so the model has to answer.
        if (spent < M.CALLS_MAX)
            body.tools = M.TOOLS;
        req.send(JSON.stringify(body));
    }

    function pickFiles() {
        if (attachPicker.connected)
            return;
        refusal = "";
        attachPicker.connected = true;
    }

    // Each picked file is measured first, so one over its limit is refused without being read.
    function readNext() {
        if (toRead.length === 0 || sizer.running || fileLoader.running)
            return;
        const path = toRead[0];
        toRead = toRead.slice(1);
        const name = path.split("/").pop();
        sizer.job = { path: path, name: name, kind: F.isImage(name) ? "image" : "text" };
        sizer.command = ["stat", "-c", "%s", "--", path];
        sizer.running = true;
    }

    function measured(code) {
        const job = sizer.job;
        job.size = Number(sizeOut.text.trim());
        const line = code === 0 ? F.check(job) : job.name + " could not be read";
        if (line) {
            refusal = line;
            Qt.callLater(chat.readNext);
            return;
        }
        fileLoader.job = job;
        fileLoader.command = job.kind === "image" ? ["base64", "-w0", "--", job.path] : ["cat", "--", job.path];
        fileLoader.running = true;
    }

    function loaded(code) {
        const job = fileLoader.job;
        if (code === 0) {
            const a = { name: job.name, size: job.size, kind: job.kind };
            if (job.kind === "image")
                a.data = "data:" + mimeOf(job.name) + ";base64," + fileOut.text.trim();
            else
                a.text = fileOut.text;
            attachments = attachments.concat([a]);
        }
        Qt.callLater(chat.readNext);
    }

    function mimeOf(name) {
        const ext = name.split(".").pop().toLowerCase();
        return "image/" + (ext === "jpg" ? "jpeg" : ext);
    }

    // Ctrl+V takes an image off the clipboard when it holds one, else the field pastes its text as before.
    function paste() {
        if (clipTypes.running || clipImage.running)
            return;
        refusal = "";
        clipTypes.running = true;
    }

    function typesRead(code) {
        const types = code === 0 ? clipTypesOut.text.split("\n").map(t => t.trim()) : [];
        const type = types.indexOf("image/png") >= 0 ? "image/png" : types.find(t => t.startsWith("image/"));
        if (!type) {
            field.paste();
            return;
        }
        clipImage.mime = type;
        clipImage.command = ["sh", "-c", 'wl-paste -t "$1" | base64 -w0', "sh", type];
        clipImage.running = true;
    }

    function imagePasted(code) {
        const b64 = clipImageOut.text.trim();
        if (code !== 0 || b64 === "")
            return;
        const size = Math.floor(b64.length * 3 / 4) - (b64.endsWith("==") ? 2 : b64.endsWith("=") ? 1 : 0);
        const a = { name: "pasted." + clipImage.mime.split("/")[1], size: size, kind: "image" };
        const line = F.check(a);
        if (line) {
            refusal = line;
            return;
        }
        a.data = "data:" + clipImage.mime + ";base64," + b64;
        attachments = attachments.concat([a]);
    }

    function removeAttachment(at) {
        attachments = attachments.filter((a, i) => i !== at);
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
        next(turn);
    }

    // A call answered after stop, a new message or a new chat belongs to a turn that is over, and is dropped.
    function next(from) {
        if (!streaming || from !== turn)
            return;
        if (queue.length === 0) {
            messages = messages.concat(answered);
            ask();
            return;
        }
        const job = queue[0];
        queue = queue.slice(1);
        if (!job.argv) {
            answer(job.id, job.note, turn);
            return;
        }
        memRun.callId = job.id;
        memRun.turn = turn;
        memRun.command = ["mem"].concat(job.argv);
        memRun.running = true;
    }

    // The next call starts on a later turn of the event loop, so mem's Process is never restarted from inside its own exit.
    function answer(id, content, from) {
        if (from !== turn)
            return;
        answered = answered.concat([{ role: "tool", tool_call_id: id, content: content }]);
        Qt.callLater(chat.next, from);
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
        save();
    }

    // The stop button ends the turn where it stands: the stream is cut off, what came stays drawn, and no tool call after it runs.
    function stop() {
        if (!streaming)
            return;
        const req = xhr;
        xhr = null;
        queue = [];
        turn += 1;
        // Stopped between tool rounds, the calls asked have no answers, which pxy would refuse on the next message, so the round leaves the conversation.
        if (!req) {
            memRun.running = false;
            let at = messages.length;
            while (at > 0 && messages[at - 1].role !== "user")
                at -= 1;
            messages = messages.slice(0, at);
        }
        if (req) {
            req.abort();
            draw(cutter.end(replyText));
            if (replyText !== "") {
                messages = messages.concat([{ role: "assistant", content: replyText }]);
                replies = replies.concat([{ row: replyRow, text: replyText }]);
            }
        }
        streaming = false;
        save();
    }

    // The whole conversation is written over its file after each turn, then the oldest past 50 are deleted.
    function save() {
        if (!conversation)
            return;
        saver.createObject(chat, { file: H.fileName(conversation), text: H.serialize({ start: conversation, title: title, alias: alias, model: model, messages: messages }) });
    }

    function pruneFrom(names) {
        const old = H.prune(names.split("\n"));
        if (old.length)
            remover.createObject(chat, { command: ["rm", "-f", "--"].concat(old.map(n => store + "/" + n)) });
    }

    // The files are read only while the history page shows, so nothing of them is held at rest.
    function openHistory() {
        page = "history";
        focusArea = "history";
        historyPick = 0;
        listed = [];
        found = [];
        historyKeys.forceActiveFocus();
        lister.running = true;
    }

    // Each line is a file's name, a tab, then its JSON, which JSON.stringify writes with no raw newline.
    function listFrom(out) {
        if (page !== "history")
            return;
        const convs = [];
        for (const line of out.split("\n")) {
            const tab = line.indexOf("\t");
            const conv = tab > 0 ? H.parse(line.slice(tab + 1)) : null;
            if (!conv)
                continue;
            conv.file = line.slice(0, tab);
            convs.push(conv);
        }
        found = convs;
        listed = H.rows(convs, Date.now());
    }

    function moveHistory(by) {
        historyPick = Math.max(0, Math.min(listed.length - 1, historyPick + by));
    }

    // Tool rounds cannot be replayed, so a reopened conversation keeps only its typed messages and the replies' text.
    function reopen() {
        const row = listed[historyPick];
        const conv = row ? found.find(c => c.start === row.start) : null;
        if (!conv || streaming)
            return;
        newChat();
        // A history file is plain data anyone can write, so what it holds is cleaned as a reply is, and only the two aliases are asked.
        const kept = conv.messages.filter(m => (m.role === "user" || m.role === "assistant") && typeof m.content === "string" && m.content !== "").map(m => ({ role: m.role, content: C.clean(m.content) }));
        for (const m of kept) {
            if (m.role === "user") {
                rows.append({ kind: "user", bkind: "", lang: "", html: "", text: m.content });
                continue;
            }
            replyRow = rows.count;
            for (const block of C.blocks().end(m.content).closed)
                put(rows.count, block);
            replyBlocks = rows.count - replyRow;
            replies = replies.concat([{ row: replyRow, text: m.content }]);
        }
        messages = kept;
        conversation = conv.start;
        title = C.clean(String(conv.title || H.title(conv))).replace(/\s+/g, " ").trim().slice(0, 60);
        alias = conv.alias === "default" ? "default" : "chat";
        model = C.clean(String(conv.model || "")).slice(0, 80);
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
        turn += 1;
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

    // r asks again after pxy failed the last message, or the request that follows a tool round.
    function retry() {
        const last = messages.length ? messages[messages.length - 1].role : "";
        if (streaming || error === "" || (last !== "user" && last !== "tool"))
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

    // Tab moves to the reply list on the last reply's code block, so Tab then y copies the code, else on its last block; with no reply yet it stops there with nothing picked, so Tab cycles the same three stops every time.
    function focusReplies() {
        const found = blockRows();
        const code = found.filter(i => i >= replyRow && rows.get(i).bkind === "code");
        pick = code.length ? code[code.length - 1] : found.length ? found[found.length - 1] : -1;
        focusArea = "replies";
        replyKeys.forceActiveFocus();
    }

    // Back in the field the history page closes, and its rows are let go.
    function focusInput() {
        page = "chat";
        listed = [];
        found = [];
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
            attachments: attachments.map(a => ({ name: a.name, size: a.size, kind: a.kind })),
            pill: F.pillText(alias, attachments),
            refusal: refusal,
            error: error,
            rows: rows.count,
            input: field.text.length > 200 ? field.text.slice(0, 200) : field.text,
            inputHeight: inputBar.height,
            focus: focusArea,
            pick: pick,
            drawn: drawn(),
            page: page,
            history: page === "history" ? listed.map(r => ({ title: r.title, question: r.question, age: r.age })) : [],
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
                chat.openHistory();
            else if (event.key === Qt.Key_Escape)
                chat.close();
            else
                return;
            event.accepted = true;
        }
    }

    // The history page's keys, held while Tab has moved there.
    Item {
        id: historyKeys
        Keys.onPressed: event => {
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                chat.moveHistory(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                chat.moveHistory(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                chat.reopen();
            else if (event.key === Qt.Key_Tab)
                chat.focusInput();
            else if (event.key === Qt.Key_Escape)
                chat.close();
            else
                return;
            event.accepted = true;
        }
    }

    // The JSON goes on stdin into a hidden temp file that mv puts in place, so a reader never sees half a file; the names that follow let the oldest be pruned.
    Component {
        id: saver

        Process {
            property string file
            property string text
            running: true
            stdinEnabled: true
            command: ["sh", "-c", 'mkdir -p "$1" && cat > "$1/.$2.tmp" && mv "$1/.$2.tmp" "$1/$2" && ls -1 "$1"', "sh", chat.store, file]
            stdout: StdioCollector {
                id: savedNames
            }
            onStarted: {
                write(text);
                stdinEnabled = false;
            }
            onExited: code => {
                if (code === 0)
                    chat.pruneFrom(savedNames.text);
                destroy();
            }
        }
    }

    Component {
        id: remover

        Process {
            running: true
            onExited: destroy()
        }
    }

    Process {
        id: lister
        command: ["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for f in *.json; do [ -f "$f" ] || continue; printf "%s\\t" "$f"; tr -d "\\n" < "$f"; echo; done', "sh", chat.store]
        stdout: StdioCollector {
            id: listedFiles
        }
        onExited: chat.listFrom(listedFiles.text)
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
        property int turn: 0
        onExited: code => chat.answer(callId, M.cut(code === 0 ? memOut.text : memErr.text), turn)
    }

    // The shell's own file picker, asked over its socket as the island's attach asks it: one request line, one answer line.
    Socket {
        id: attachPicker
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/dots-picker-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        onConnectedChanged: {
            if (connected) {
                write(JSON.stringify({ mode: "open", multiple: true, title: "Attach to the message", app: "", folder: Quickshell.env("HOME"), name: "", filters: [], filter: 0, accept: "" }) + "\n");
                flush();
            }
        }
        parser: SplitParser {
            onRead: data => {
                let r = null;
                try {
                    r = JSON.parse(data);
                } catch (e) {}
                if (r?.response === 0 && Array.isArray(r.paths)) {
                    chat.toRead = chat.toRead.concat(r.paths);
                    Qt.callLater(chat.readNext);
                }
                attachPicker.connected = false;
            }
        }
    }

    // Paths go to stat, cat and base64 as argv, and what a file holds comes back only on stdout.
    Process {
        id: sizer
        property var job: null
        stdout: StdioCollector {
            id: sizeOut
        }
        onExited: code => chat.measured(code)
    }

    Process {
        id: fileLoader
        property var job: null
        stdout: StdioCollector {
            id: fileOut
        }
        onExited: code => chat.loaded(code)
    }

    Process {
        id: clipTypes
        command: ["wl-paste", "--list-types"]
        stdout: StdioCollector {
            id: clipTypesOut
        }
        onExited: code => chat.typesRead(code)
    }

    // The script is fixed and the type is its one argument, so the image's bytes only ever pass through the pipe.
    Process {
        id: clipImage
        property string mime: ""
        stdout: StdioCollector {
            id: clipImageOut
        }
        onExited: code => chat.imagePasted(code)
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
                            text: F.pillText(chat.alias, chat.attachments)
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

                    Root.Click {
                        name: "chat-history"
                        onTapped: chat.openHistory()
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

                    Root.Click {
                        name: "chat-new"
                        onTapped: chat.newChat()
                    }
                }
            }

            // The history page, made only while it shows: one tile per conversation, its title, its first question and its age.
            Loader {
                id: historyLoader
                active: chat.page === "history"
                visible: active
                width: column.width
                sourceComponent: historyPage
            }

            // A new chat: a sparkle in a circle and what the chat can do.
            Item {
                visible: rows.count === 0 && chat.page === "chat"
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
                visible: rows.count > 0 && chat.page === "chat"
                width: column.width
                height: visible ? Math.min(contentHeight, 440) : 0
                contentHeight: messageColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // A failure's line with Retry under the message scrolls into view too.
                onContentHeightChanged: if (chat.streaming || chat.error !== "")
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
                                readonly property int rowIndex: row.index
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

            // The attachments waiting for the next message, each with its remove button; an image shows a thumbnail.
            Flow {
                visible: chat.attachments.length > 0
                width: column.width
                spacing: 6

                Repeater {
                    model: chat.attachments

                    Rectangle {
                        required property var modelData
                        required property int index
                        width: chipLine.implicitWidth + 20
                        height: 32
                        radius: 16
                        color: chat.tile

                        Row {
                            id: chipLine
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Image {
                                visible: parent.parent.modelData.kind === "image"
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                source: visible ? parent.parent.modelData.data : ""
                                sourceSize.width: 44
                                sourceSize.height: 44
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            Text {
                                visible: parent.parent.modelData.kind !== "image"
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: String.fromCodePoint(0xF0219)
                                color: chat.tones.muted
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 14
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: F.chipText(parent.parent.modelData)
                                color: chat.on
                                font.family: chat.fonts.ui ?? ""
                                font.pixelSize: 12
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: String.fromCodePoint(0xF0156)
                                color: chat.tones.muted
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 14

                                Root.Click {
                                    name: "chat-unattach:" + chipLine.parent.index
                                    anchors.margins: -4
                                    onTapped: chat.removeAttachment(chipLine.parent.index)
                                }
                            }
                        }
                    }
                }
            }

            // The paperclip, the field, and the round send button that turns into stop while a reply streams.
            Rectangle {
                width: column.width
                id: inputBar
                height: Math.max(52, fieldBox.height + 28)
                radius: 16
                color: chat.tile

                Text {
                    id: paperclip
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(0xF03E2)
                    color: chat.tones.muted
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 18

                    Root.Click {
                        name: "chat-attach"
                        anchors.margins: -6
                        onTapped: chat.pickFiles()
                    }
                }

                // The field scrolls past about five lines, so a long paste never pushes the bar out of the island.
                Flickable {
                    id: fieldBox
                    anchors.left: paperclip.right
                    anchors.leftMargin: 10
                    anchors.right: sendButton.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.min(field.implicitHeight, 100)
                    contentWidth: width
                    contentHeight: field.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    function follow(r) {
                        if (r.y < contentY)
                            contentY = r.y;
                        else if (r.y + r.height > contentY + height)
                            contentY = r.y + r.height - height;
                    }

                    TextEdit {
                        id: field
                        width: fieldBox.width
                        onCursorRectangleChanged: fieldBox.follow(cursorRectangle)
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
                            else if (ctrl && event.key === Qt.Key_O)
                                chat.pickFiles();
                            else if (ctrl && event.key === Qt.Key_V)
                                chat.paste();
                            else if (event.key === Qt.Key_Backspace && field.text === "" && chat.attachments.length)
                                chat.removeAttachment(chat.attachments.length - 1);
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

            Text {
                visible: chat.refusal !== ""
                width: column.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: chat.refusal
                color: chat.tones.danger
                font.family: chat.fonts.ui ?? ""
                font.pixelSize: 12
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
            // Rich text, so inline code can sit on a tint, the nearest a Text comes to board 6's pill.
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            text: parent.html.replace(/<code>/g, chat.codeOpen).replace(/<\/code>/g, "&nbsp;</span>")
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

                Root.Click {
                    name: "chat-copy:" + parent.parent.parent.rowIndex
                    onTapped: chat.copy(parent.parent.parent.text)
                }
            }

            Text {
                id: codeText
                x: 14
                y: 32
                width: parent.width - 28
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                text: parent.parent.html
                color: chat.on
                font.family: chat.fonts.mono ?? ""
                font.pixelSize: 12
            }
        }
    }

    // The picked conversation sits on the lit tile, and the page scrolls to keep it in view.
    Component {
        id: historyPage

        Flickable {
            id: historyList
            readonly property int picked: chat.historyPick
            implicitHeight: chat.listed.length ? Math.min(contentHeight, 440) : 60
            contentHeight: historyColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onPickedChanged: {
                const item = historyRepeater.itemAt(picked);
                if (!item)
                    return;
                if (item.y < contentY)
                    contentY = item.y;
                else if (item.y + item.height > contentY + height)
                    contentY = item.y + item.height - height;
            }

            Text {
                visible: chat.listed.length === 0
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "No conversations yet"
                color: chat.tones.muted
                font.family: chat.fonts.ui ?? ""
                font.pixelSize: 13
            }

            Column {
                id: historyColumn
                width: historyList.width
                spacing: 6

                Repeater {
                    id: historyRepeater
                    model: chat.listed

                    delegate: Rectangle {
                        id: historyRow
                        required property int index
                        required property var modelData
                        width: historyColumn.width
                        height: 52
                        radius: 12
                        color: chat.historyPick === index ? chat.bubble : chat.tile

                        Text {
                            x: 14
                            y: 8
                            width: parent.width - 28 - ageText.implicitWidth - 12
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            text: historyRow.modelData.title || "New chat"
                            color: chat.on
                            font.family: chat.fonts.ui ?? ""
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            x: 14
                            y: 28
                            width: parent.width - 28
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            text: historyRow.modelData.question
                            color: chat.tones.muted
                            font.family: chat.fonts.ui ?? ""
                            font.pixelSize: 12
                        }

                        Text {
                            id: ageText
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            y: 8
                            textFormat: Text.PlainText
                            text: historyRow.modelData.age
                            color: chat.tones.muted
                            font.family: chat.fonts.ui ?? ""
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}

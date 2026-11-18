import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T
import "lib/pass.mjs" as P

// The pass store inside the island, as board 8 draws it: names only, one password shown for 10 s; every secret goes through bin/dots-pass, and the list itself holds only names.
Item {
    id: pass

    required property var theme
    property bool shown: false
    readonly property string query: input.text
    property int selected: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1
    // dots-pass list's entries as of this open.
    property var entries: []
    property bool listed: false
    // A dots-pass run that outlives the card, such as a copy waiting on gpg's passphrase; the card stays loaded until it ends.
    readonly property bool busy: runner.running || changer.running || revealer.running
    // What the card shows under its query: the list, the new-entry card, or the list with the delete question under it.
    property string mode: "list"
    // The entry whose password shows on its row, and the password, for 10 s.
    property string revealName: ""
    property string revealText: ""
    // When the shown password hides, and how long it has left, counted each second while it shows.
    property real revealUntil: 0
    property real revealLeft: 0
    // The new entry's generated password and its length.
    property string generated: ""
    property int length: P.LENGTH.start
    readonly property string pathTag: P.pathTag(entries, newPath.text)
    // What the clipboard's QR says it is (issuer, account, type, digits, period), never its secret, while q picks the entry to save it to.
    property var qr: null

    readonly property string bin: Quickshell.shellDir + "/bin/dots-pass"
    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, the tones lifted to read on it, and board 8's tile, selected row and circle.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property color tile: Qt.alpha(on, 0.07)
    readonly property color sel: Qt.alpha(on, 0.12)
    readonly property color circle: Qt.alpha(on, 0.12)
    readonly property var found: P.passRows(entries, query)
    readonly property var rows: found.slice(0, 8)
    // The last row offers a new entry while the list shows; the cursor on it has no entry.
    readonly property bool newRowShown: mode === "list" && listed
    readonly property var current: rows[selected] ?? null
    // The island reports this as its surface while Pass shows, and grows to this width for it (board 8).
    readonly property string name: "pass"
    readonly property int wantWidth: 640
    // True once the island has come to rest on Pass; the surfaces' window sets it.
    property bool settled: false
    implicitHeight: card.height

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        input.text = "";
        selected = 0;
        mode = "list";
        qr = null;
        newPath.text = "";
        listed = false;
        lister.running = true;
        shown = true;
        input.forceActiveFocus();
    }

    // Every secret the card holds goes at close: a shown password and a new entry's preview. The rest stays as drawn while the close plays, and open() resets it.
    function close() {
        shown = false;
        hide();
        generated = "";
    }

    function hide() {
        revealTick.stop();
        revealName = "";
        revealText = "";
        revealUntil = 0;
    }

    function reveal() {
        if (!current || revealer.running)
            return;
        hide();
        revealer.name = current.name;
        revealer.wanted = true;
        revealer.command = [bin, "show", current.name];
        revealer.running = true;
    }

    // dots-pass reads the clipboard's QR and answers with what it describes; the card never holds the code's secret.
    function scanQr() {
        if (scanner.running)
            return;
        hide();
        scanner.running = true;
    }

    // Enter while picking: the cursor row, or the typed name when nothing matches it.
    function saveQr() {
        const name = current ? current.name : query.trim();
        if (!qr || changer.running || (!current && P.pathTag(entries, name) !== "new"))
            return;
        change("qr-save", name, "");
        qr = null;
        mode = "list";
    }

    // Esc while picking a QR's entry goes back to the list; otherwise it closes, and a reveal still waiting on gpg is dropped.
    function leave() {
        if (mode === "qr") {
            back();
            return;
        }
        revealer.wanted = false;
        close();
    }

    signal reopenWanted

    // Back as it was, after the passphrase card took its place.
    function reopen() {
        shown = true;
        results.forceActiveFocus();
    }

    function enter() {
        if (mode === "qr")
            saveQr();
        else if (newRowShown && selected === rows.length)
            startNew(query.trim());
        else
            copy("copy");
    }

    // The new-entry row starts it under the typed name; n starts it empty.
    function startNew(path) {
        hide();
        mode = "new";
        newPath.text = path;
        length = P.LENGTH.start;
        generate();
        newPath.forceActiveFocus();
    }

    function generate() {
        generator.running = false;
        generator.command = [bin, "generate", String(length)];
        generator.running = true;
    }

    function lengthen(by) {
        const next = P.stepLength(length, by);
        if (next === length)
            return;
        length = next;
        generate();
    }

    // An existing path is never overwritten; the tag already says so.
    function save() {
        if (pathTag !== "new" || generated === "" || changer.running)
            return;
        change("insert", newPath.text.trim(), generated);
        generated = "";
        mode = "list";
        results.forceActiveFocus();
    }

    // The path field types every letter; on the password tile - and + (or h and l) change its length.
    function newKey(event, onLength) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            save();
        else if (event.key === Qt.Key_Escape)
            back();
        else if (event.key === Qt.Key_Tab)
            (onLength ? newPath : lengthBox).forceActiveFocus();
        else if (onLength && (event.key === Qt.Key_Minus || event.key === Qt.Key_H))
            lengthen(-1);
        else if (onLength && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.key === Qt.Key_L))
            lengthen(1);
        else
            return;
        event.accepted = true;
    }

    function back() {
        qr = null;
        mode = "list";
        generated = "";
        newPath.text = "";
        results.forceActiveFocus();
    }

    function askDelete() {
        if (!current)
            return;
        hide();
        mode = "delete";
        deleting = current.name;
    }
    property string deleting: ""

    function answerDelete(yes) {
        if (yes)
            change("delete", deleting, "");
        mode = "list";
        deleting = "";
    }

    // kak opens in a foot window of its own, which saves and pushes when it closes.
    function edit() {
        if (!current)
            return;
        const name = current.name;
        close();
        Quickshell.execDetached([bin, "edit", name]);
    }

    // insert and delete change the store; the list reads it again after, and the island says how it went.
    function change(verb, name, stdin) {
        changer.verb = verb;
        changer.name = name;
        changer.stdin = stdin;
        changer.command = [bin, verb, name];
        changer.running = true;
    }

    // Called on each of the host window's frames; the first one after open() ends the timing.
    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function move(by) {
        selected = Math.max(0, Math.min(rows.length - (newRowShown ? 0 : 1), selected + by));
    }

    // A click on a row does what Enter does on it; while the delete question or the new entry's fields are open, the keys answer only them, so a row takes no click.
    function clickRow(i) {
        if (mode !== "list" && mode !== "qr")
            return;
        selected = i;
        enter();
    }

    // The card closes first, since gpg may ask for its passphrase on its own card; the island says how the copy went.
    function copy(kind) {
        if (!current || runner.running)
            return;
        close();
        runner.kind = kind;
        runner.command = [bin, kind, current.name];
        runner.running = true;
    }

    function state() {
        const cur = rowRepeater.itemAt(selected);
        return JSON.stringify({
            loaded: true,
            open: shown,
            query: query,
            listed: listed,
            count: found.length,
            // Each row as drawn: its runs' text and which are underlined, and its tag.
            rows: rows.map((r, i) => {
                const item = rowRepeater.itemAt(i);
                return {
                    name: item ? item.drawnName : "",
                    underlined: item ? item.underlined() : "",
                    otp: item ? item.tagText() === "OTP" : false
                };
            }),
            selected: selected,
            cursorFill: cur ? String(cur.color) : null,
            // The cursor row's eye and inverted Copy, as drawn.
            buttons: cur ? cur.buttons() : null,
            newRow: newRowShown ? { text: newRowText.text, selected: selected === rows.length } : null,
            focus: results.activeFocus ? "list" : "query",
            busy: busy,
            mode: mode,
            // The cursor row as drawn while its password shows, and the seconds it has left.
            revealed: cur?.revealed ? { text: cur.shownText(), hides: cur.hidesText() } : null,
            newEntry: mode === "new" ? { path: newPath.text, tag: tagText.text, length: generated.length, lengthText: lengthText.text, focus: lengthBox.activeFocus ? "length" : "path" } : null,
            deleteLine: deleteLine.visible ? deleteLine.text : "",
            deleteColor: String(deleteLine.color),
            note: toolNote.text,
            // The island's ink and fill and its danger tone, which the rows, Copy and the delete question draw in.
            on: String(on),
            fill: String(fill),
            danger: String(tones.danger),
            qr: mode === "qr" && qr ? { issuer: qrIssuer.text, account: qrAccount.text, meta: qrMeta.text, question: qrQuestion.text } : null,
            openMs: openMs,
            opens: opens,
            settled: pass.settled,
            drawing: pass.visible,
            cardBox: card.drawnBox(),
            keyboard: pass.Window.active
        });
    }

    onQueryChanged: selected = 0
    onSelectedChanged: hide()

    Process {
        id: lister
        command: [pass.bin, "list"]
        stdout: StdioCollector {
            id: listOut
        }
        onExited: code => {
            if (code === 0)
                pass.entries = P.parseEntries(listOut.text);
            pass.listed = true;
        }
    }

    Process {
        id: runner
        property string kind: ""
        stderr: StdioCollector {
            id: runErr
        }
        onExited: code => pass.theme.notice(code === 0 ? P.copiedText(kind) : P.failedText(runErr.text))
    }

    Process {
        id: revealer
        property string name: ""
        stdout: StdioCollector {
            id: revealOut
        }
        // gpg's passphrase card closes Pass while it asks; once answered, Pass comes back showing the password, unless Esc closed it.
        property bool wanted: false
        onExited: code => {
            if (code !== 0 || !(pass.shown || wanted))
                return;
            wanted = false;
            if (!pass.shown)
                pass.reopenWanted();
            if (!pass.shown)
                return;
            pass.revealName = name;
            pass.revealText = revealOut.text.replace(/\n$/, "");
            pass.revealUntil = Date.now() + revealTick.interval;
            pass.revealLeft = revealTick.interval;
            revealTick.restart();
            // The decrypt may have learnt or dropped the entry's OTP tag, so the list is read again.
            lister.running = true;
        }
    }

    Root.Tick {
        id: revealTick
        interval: 10000
        onTriggered: pass.hide()
    }

    // The shown password's countdown moves each second.
    Root.Tick {
        interval: 1000
        repeat: true
        running: pass.revealUntil > 0
        onTriggered: pass.revealLeft = pass.revealUntil - Date.now()
    }

    Process {
        id: scanner
        command: [pass.bin, "qr-scan"]
        stdout: StdioCollector {
            id: scanOut
        }
        stderr: StdioCollector {
            id: scanErr
        }
        onExited: code => {
            if (!pass.shown)
                return;
            if (code !== 0) {
                pass.theme.notice(P.changedText("qr-save", "", code, scanErr.text));
                return;
            }
            pass.qr = P.qrInfo(scanOut.text);
            pass.mode = "qr";
            input.text = "";
            input.forceActiveFocus();
        }
    }

    Process {
        id: generator
        stdout: StdioCollector {
            id: generatedOut
        }
        onExited: code => {
            if (code === 0 && pass.mode === "new")
                pass.generated = generatedOut.text.replace(/\n$/, "");
        }
    }

    // A new password reaches dots-pass on stdin, never in its arguments.
    Process {
        id: changer
        property string verb: ""
        property string name: ""
        property string stdin: ""
        stdinEnabled: true
        stderr: StdioCollector {
            id: changeErr
        }
        onStarted: {
            if (stdin !== "")
                write(stdin + "\n");
            stdin = "";
        }
        onExited: code => {
            pass.theme.notice(P.changedText(verb, name, code, changeErr.text));
            if (pass.shown)
                lister.running = true;
        }
    }

    Component.onCompleted: Root.State.loaded.push("pass")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "pass")

    // One letter of a row's name, which is monospaced, so a long name is cut to the letters its row holds.
    TextMetrics {
        id: nameMetrics
        font.family: pass.fonts.ui ?? ""
        font.pixelSize: 13
        font.weight: Font.Bold
        text: "M"
    }

    Root.Surface {
        id: card
        width: parent.width
        height: column.implicitHeight + 32
        tokens: pass.theme.tokens
        // The island draws the fill and plays the open.
        bare: true

        Column {
            id: column
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 8

            // The search field, a key at its left; the new entry takes its place.
            Rectangle {
                visible: pass.mode !== "new"
                width: column.width
                height: 48
                radius: 14
                color: pass.tile

                Text {
                    id: keyGlyph
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(0xF0306)
                    color: pass.tones.muted
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 18
                }

                TextInput {
                    id: input
                    anchors.left: keyGlyph.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: pass.on
                    selectionColor: Qt.alpha(pass.on, 0.3)
                    font.family: pass.fonts.ui ?? ""
                    font.pixelSize: 15
                    clip: true
                    focus: true
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J))
                            pass.move(1);
                        else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K))
                            pass.move(-1);
                        else if (event.key === Qt.Key_Tab)
                            results.forceActiveFocus();
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            pass.enter();
                        else if (event.key === Qt.Key_Escape)
                            pass.leave();
                        else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        visible: input.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "Search"
                        color: pass.tones.muted
                        font: input.font
                    }
                }
            }

            // What the QR holds, then the question; the list under it picks the entry.
            Column {
                visible: pass.mode === "qr" && !!pass.qr
                x: 12
                width: column.width - 24
                topPadding: 6
                bottomPadding: 6
                spacing: 4

                Text {
                    id: qrIssuer
                    width: parent.width
                    textFormat: Text.PlainText
                    text: pass.qr?.issuer ?? ""
                    elide: Text.ElideRight
                    color: pass.on
                    font.family: pass.fonts.ui ?? ""
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
                Text {
                    id: qrAccount
                    width: parent.width
                    textFormat: Text.PlainText
                    text: pass.qr?.account ?? ""
                    elide: Text.ElideRight
                    color: pass.tones.muted
                    font.family: pass.fonts.ui ?? ""
                    font.pixelSize: 13
                }
                Text {
                    id: qrMeta
                    textFormat: Text.PlainText
                    text: pass.qr?.meta ?? ""
                    color: pass.tones.muted
                    font.family: pass.fonts.ui ?? ""
                    font.pixelSize: 12
                }
                Text {
                    id: qrQuestion
                    topPadding: 6
                    textFormat: Text.PlainText
                    text: "Save to which entry?"
                    color: pass.on
                    font.family: pass.fonts.ui ?? ""
                    font.pixelSize: 13
                }
            }

            // Holds focus after Tab, where the plain letter keys act on the cursor row and / returns to the query.
            Item {
                id: results
                visible: pass.mode !== "new"
                width: column.width
                implicitHeight: list.implicitHeight
                Keys.onPressed: event => {
                    if (pass.mode === "delete") {
                        if (event.key === Qt.Key_Y)
                            pass.answerDelete(true);
                        else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape)
                            pass.answerDelete(false);
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                        pass.move(1);
                    else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                        pass.move(-1);
                    else if (event.key === Qt.Key_Slash)
                        input.forceActiveFocus();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        pass.enter();
                    else if (event.key === Qt.Key_O)
                        pass.copy("otp");
                    else if (event.key === Qt.Key_S)
                        pass.reveal();
                    else if (event.key === Qt.Key_N)
                        pass.startNew("");
                    else if (event.key === Qt.Key_E)
                        pass.edit();
                    else if (event.key === Qt.Key_D)
                        pass.askDelete();
                    else if (event.key === Qt.Key_Q)
                        pass.scanQr();
                    else if (event.key === Qt.Key_Escape)
                        pass.leave();
                    else
                        return;
                    event.accepted = true;
                }

                Column {
                    id: list
                    width: parent.width
                    spacing: 4

                    Repeater {
                        id: rowRepeater
                        model: rows

                        // A row is the entry's name only; the cursor row is lighter and carries its eye and its Copy, and a shown password counts down under the name.
                        Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: index === pass.selected
                            // As many letters as the name's column holds, the last an ellipsis when the name is longer.
                            readonly property var runs: P.segments(modelData, Math.max(1, Math.floor(nameColumn.width / Math.max(1, nameMetrics.advanceWidth))))
                            readonly property string drawnName: runs.map(r => r.text).join("")
                            function underlined() {
                                const out = [];
                                for (let i = 0; i < runRepeater.count; i++)
                                    if (runRepeater.itemAt(i).font.underline)
                                        out.push(runRepeater.itemAt(i).text);
                                return out.join("");
                            }
                            readonly property bool revealed: pass.revealName === modelData.name
                            function shownText() {
                                return revealedText.text;
                            }
                            function tagText() {
                                return otpTag.visible ? otpTagText.text : "";
                            }
                            function hidesText() {
                                return rowItem.revealed ? P.hidesText(pass.revealLeft) : "";
                            }
                            function buttons() {
                                return { eye: eyeGlyph.text === String.fromCodePoint(0xF0209) ? "eye-off" : "eye", copy: copyButton.visible ? { text: copyText.text, fill: String(copyButton.color), ink: String(copyText.color) } : null };
                            }
                            width: list.width
                            height: 48
                            radius: 12
                            color: isCurrent ? pass.sel : "transparent"

                            // A click on the row does what Enter does on it.
                            Root.Click {
                                name: "pass-row:" + rowItem.index
                                onTapped: pass.clickRow(rowItem.index)
                            }

                            Column {
                                id: nameColumn
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: rowEnd.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    width: parent.width
                                    clip: true

                                    Repeater {
                                        id: runRepeater
                                        model: rowItem.runs

                                        Text {
                                            required property var modelData
                                            textFormat: Text.PlainText
                                            text: modelData.text
                                            color: modelData.folder ? pass.tones.muted : pass.on
                                            font.family: pass.fonts.ui ?? ""
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            font.underline: modelData.hit
                                        }
                                    }
                                }

                                // The shown password and the seconds it has left.
                                Row {
                                    visible: rowItem.revealed
                                    width: parent.width
                                    spacing: 0

                                    Text {
                                        id: revealedText
                                        width: Math.min(implicitWidth, parent.width - hidesLine.implicitWidth)
                                        textFormat: Text.PlainText
                                        text: rowItem.revealed ? pass.revealText : ""
                                        elide: Text.ElideRight
                                        color: pass.tones.muted
                                        font.family: pass.fonts.mono ?? ""
                                        font.pixelSize: 12
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        id: hidesLine
                                        textFormat: Text.PlainText
                                        text: " · " + P.hidesText(pass.revealLeft)
                                        color: pass.tones.muted
                                        font.family: pass.fonts.ui ?? ""
                                        font.pixelSize: 12
                                    }
                                }
                            }

                            Row {
                                id: rowEnd
                                anchors.right: parent.right
                                anchors.rightMargin: rowItem.isCurrent ? 8 : 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                // Entries with a code carry an OTP pill.
                                Rectangle {
                                    id: otpTag
                                    visible: rowItem.modelData.otp
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: otpRow.implicitWidth + 16
                                    height: 22
                                    radius: 11
                                    color: pass.circle

                                    Row {
                                        id: otpRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            textFormat: Text.PlainText
                                            text: String.fromCodePoint(0xF0432)
                                            color: pass.tones.muted
                                            font.family: "Symbols Nerd Font Mono"
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            id: otpTagText
                                            anchors.verticalCenter: parent.verticalCenter
                                            textFormat: Text.PlainText
                                            text: "OTP"
                                            color: pass.tones.muted
                                            font.family: pass.fonts.ui ?? ""
                                            font.pixelSize: 11
                                        }
                                    }
                                }

                                // The eye shows or hides the password.
                                Rectangle {
                                    visible: rowItem.isCurrent
                                    width: 34
                                    height: 34
                                    radius: 10
                                    color: pass.tile

                                    Text {
                                        id: eyeGlyph
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: String.fromCodePoint(rowItem.revealed ? 0xF0209 : 0xF0208)
                                        color: pass.on
                                        font.family: "Symbols Nerd Font Mono"
                                        font.pixelSize: 15
                                    }
                                    Root.Click {
                                        name: "pass-eye"
                                        onTapped: rowItem.revealed ? pass.hide() : pass.reveal()
                                    }
                                }

                                // Copy, inverted, as Enter does.
                                Rectangle {
                                    id: copyButton
                                    visible: rowItem.isCurrent
                                    width: copyRow.implicitWidth + 24
                                    height: 34
                                    radius: 10
                                    color: pass.on

                                    Row {
                                        id: copyRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            textFormat: Text.PlainText
                                            text: String.fromCodePoint(0xF018F)
                                            color: pass.fill
                                            font.family: "Symbols Nerd Font Mono"
                                            font.pixelSize: 13
                                        }
                                        Text {
                                            id: copyText
                                            anchors.verticalCenter: parent.verticalCenter
                                            textFormat: Text.PlainText
                                            text: "Copy"
                                            color: pass.fill
                                            font.family: pass.fonts.ui ?? ""
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                        }
                                    }
                                    Root.Click {
                                        name: "pass-copy"
                                        onTapped: pass.copy("copy")
                                    }
                                }
                            }
                        }
                    }

                    // The last row starts a new entry under the typed name.
                    Rectangle {
                        id: newRow
                        visible: pass.newRowShown
                        readonly property bool isCurrent: pass.selected === pass.rows.length
                        width: list.width
                        height: 48
                        radius: 12
                        color: isCurrent ? pass.sel : "transparent"

                        Root.Click {
                            name: "pass-new"
                            onTapped: pass.clickRow(pass.rows.length)
                        }

                        Row {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: String.fromCodePoint(0xF0415)
                                color: newRow.isCurrent ? pass.on : pass.tones.muted
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 13
                            }
                            Text {
                                id: newRowText
                                anchors.verticalCenter: parent.verticalCenter
                                width: list.width - 60
                                textFormat: Text.PlainText
                                text: P.newRowText(pass.query)
                                elide: Text.ElideRight
                                color: newRow.isCurrent ? pass.on : pass.tones.muted
                                font.family: pass.fonts.ui ?? ""
                                font.pixelSize: 13
                            }
                        }
                    }

                    // The delete question, in the danger tone, with its two answers.
                    Rectangle {
                        visible: pass.mode === "delete"
                        width: list.width
                        height: 48
                        radius: 12
                        color: pass.tile

                        Text {
                            id: deleteLine
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - deleteButtons.width - 36
                            textFormat: Text.PlainText
                            text: P.deleteText(pass.deleting)
                            elide: Text.ElideRight
                            color: pass.tones.danger
                            font.family: pass.fonts.ui ?? ""
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Row {
                            id: deleteButtons
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Button {
                                label: "Keep"
                                name: "pass-keep"
                                onTapped: pass.answerDelete(false)
                            }
                            Button {
                                label: "Delete"
                                name: "pass-delete"
                                tint: pass.tones.danger
                                onTapped: pass.answerDelete(true)
                            }
                        }
                    }
                }
            }

            // The new entry: its name, then the generated password at 20 px with its length, then Cancel and Save.
            Column {
                visible: pass.mode === "new"
                width: column.width
                spacing: 8

                Row {
                    height: 36
                    spacing: 12

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        radius: 16
                        color: pass.tile
                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: String.fromCodePoint(0xF0141)
                            color: pass.on
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 16
                        }
                        Root.Click {
                            name: "pass-back"
                            onTapped: pass.back()
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "New entry"
                        color: pass.on
                        font.family: pass.fonts.ui ?? ""
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }
                }

                // The name, tagged new or exists.
                Rectangle {
                    width: column.width
                    height: 44
                    radius: 12
                    color: newPath.activeFocus ? pass.sel : pass.tile

                    TextInput {
                        id: newPath
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: tagText.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: pass.on
                        selectionColor: Qt.alpha(pass.on, 0.3)
                        font.family: pass.fonts.ui ?? ""
                        font.pixelSize: 13
                        clip: true
                        Keys.onPressed: event => pass.newKey(event, false)

                        Text {
                            visible: newPath.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: "folder/name"
                            color: pass.tones.muted
                            font: newPath.font
                        }
                    }

                    Text {
                        id: tagText
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: pass.pathTag
                        color: pass.pathTag === "exists" ? pass.tones.danger : pass.tones.muted
                        font.family: pass.fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                }

                // Holds focus after Tab, where - and + (or h and l) shorten and lengthen the password.
                Rectangle {
                    id: lengthBox
                    width: column.width
                    height: 92
                    radius: 12
                    color: activeFocus ? pass.sel : pass.tile
                    Keys.onPressed: event => pass.newKey(event, true)

                    Text {
                        id: preview
                        x: 14
                        y: 14
                        width: parent.width - 28 - 42
                        textFormat: Text.PlainText
                        text: pass.generated
                        elide: Text.ElideRight
                        color: pass.on
                        font.family: pass.fonts.mono ?? ""
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }

                    // Another password at the same length.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: preview.verticalCenter
                        width: 32
                        height: 32
                        radius: 10
                        color: pass.circle
                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: String.fromCodePoint(0xF0450)
                            color: pass.on
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 15
                        }
                        Root.Click {
                            name: "pass-regenerate"
                            onTapped: pass.generate()
                        }
                    }

                    Row {
                        x: 14
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: "Length"
                            color: pass.tones.muted
                            font.family: pass.fonts.ui ?? ""
                            font.pixelSize: 12
                        }
                        Step {
                            label: "−"
                            name: "pass-shorter"
                            onTapped: pass.lengthen(-1)
                        }
                        Text {
                            id: lengthText
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            horizontalAlignment: Text.AlignHCenter
                            textFormat: Text.PlainText
                            text: String(pass.length)
                            color: pass.on
                            font.family: pass.fonts.ui ?? ""
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Step {
                            label: "+"
                            name: "pass-longer"
                            onTapped: pass.lengthen(1)
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    Button {
                        label: "Cancel"
                        name: "pass-cancel"
                        onTapped: pass.back()
                    }
                    Button {
                        label: "Save"
                        name: "pass-save"
                        tint: pass.on
                        onTapped: pass.save()
                    }
                }
            }

            // A save's or a scan's word, which the island cannot show while Pass holds it.
            Root.ToolNote {
                id: toolNote
                theme: pass.theme
                x: 12
                width: column.width - 24
                color: pass.tones.muted
                font.family: pass.fonts.ui ?? ""
            }
        }
    }

    // A 36 px button: a tile, or filled with its tint and its word in the island's fill.
    component Button: Rectangle {
        id: button
        property string label: ""
        property string name: ""
        property color tint: "transparent"
        readonly property bool filled: tint.a > 0
        signal tapped
        width: buttonText.implicitWidth + 32
        height: 36
        radius: 10
        color: filled ? tint : pass.tile
        Text {
            id: buttonText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: button.label
            color: button.filled ? pass.fill : pass.on
            font.family: pass.fonts.ui ?? ""
            font.pixelSize: 13
            font.weight: button.filled ? Font.Bold : Font.Normal
        }
        Root.Click {
            name: button.name
            onTapped: button.tapped()
        }
    }

    // The length's − and + circles.
    component Step: Rectangle {
        id: step
        property string label: ""
        property string name: ""
        signal tapped
        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        radius: 13
        color: pass.circle
        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: step.label
            color: pass.on
            font.family: pass.fonts.ui ?? ""
            font.pixelSize: 13
        }
        Root.Click {
            name: step.name
            onTapped: step.tapped()
        }
    }
}

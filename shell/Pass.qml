import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "." as Root
import "lib/voice.mjs" as L
import "lib/pass.mjs" as P

// The pass store as a list in the launcher's idiom; every secret goes through bin/dots-pass, and the list itself holds only names.
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
    // The new entry's generated password and its length.
    property string generated: ""
    property int length: P.LENGTH.start
    readonly property string pathTag: P.pathTag(entries, newPath.text)
    // What the clipboard's QR says it is (issuer, account, type, digits, period), never its secret, while q picks the entry to save it to.
    property var qr: null

    readonly property string bin: Quickshell.shellDir + "/../bin/dots-pass"
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property var found: P.passRows(entries, query)
    readonly property var rows: found.slice(0, 8)
    readonly property var current: rows[selected] ?? null
    readonly property Root.Motion motion: Root.Motion {
        shown: pass.shown
        tokens: pass.theme.tokens
    }

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
        else
            copy("copy");
    }

    function startNew() {
        hide();
        mode = "new";
        newPath.text = "";
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
        length = Math.max(P.LENGTH.min, Math.min(P.LENGTH.max, length + by));
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

    // The path field types every letter; on the password line h and l change its length.
    function newKey(event, onLength) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            save();
        else if (event.key === Qt.Key_Escape)
            back();
        else if (event.key === Qt.Key_Tab)
            (onLength ? newPath : lengthBox).forceActiveFocus();
        else if (onLength && event.key === Qt.Key_H)
            lengthen(-1);
        else if (onLength && event.key === Qt.Key_L)
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
        selected = Math.max(0, Math.min(rows.length - 1, selected + by));
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
        const keys = [];
        for (let i = 0; i < keyRepeater.count; i++)
            keys.push((keyRepeater.itemAt(i).keyLabel + " " + keyRepeater.itemAt(i).wordLabel).trim());
        return JSON.stringify({
            loaded: true,
            open: shown,
            query: query,
            listed: listed,
            count: found.length,
            countText: (look.label.kind === "header" ? headerCount : chipCount).text,
            heading: (look.label.kind === "header" ? header : look.label.kind === "pill" ? pill : chip).text,
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
            focus: results.activeFocus ? "list" : "query",
            hint: keys.join(" · "),
            busy: busy,
            mode: mode,
            // The cursor row as drawn while its password shows, and its tag.
            revealed: cur?.revealed ? { text: cur.shownText(), tag: cur.tagText() } : null,
            newEntry: mode === "new" ? { path: newPath.text, tag: tagText.text, length: generated.length, lengthText: lengthText.text, focus: lengthBox.activeFocus ? "length" : "path" } : null,
            deleteLine: deleteLine.visible ? deleteLine.text : "",
            qr: mode === "qr" && qr ? { issuer: qrIssuer.text, account: qrAccount.text, meta: qrMeta.text, question: qrQuestion.text } : null,
            openMs: openMs,
            opens: opens,
            settled: motion.settled,
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

    visible: motion.drawing

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(c.paper, card.style.wash)
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: 168
        width: 640
        height: column.implicitHeight
        tokens: pass.theme.tokens
        label: "Pass"
        motion: pass.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            // Blueprint names the surface and counts its matches on a line of their own above the query.
            RowLayout {
                visible: look.label.kind === "header"
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                Layout.topMargin: 12

                Text {
                    id: header
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: look.heading("pass", "store")
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }
                Text {
                    id: headerCount
                    textFormat: Text.PlainText
                    text: look.count(found.length)
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: look.voice === "plain" ? 18 : look.voice === "bracket" ? 22 : 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: look.voice === "plain" ? 16 : look.voice === "bracket" ? 8 : 18
                Layout.bottomMargin: look.voice === "plain" ? 16 : 14
                spacing: look.voice === "caps" ? 14 : look.voice === "bracket" ? 10 : 12

                Rectangle {
                    visible: look.label.kind === "chip"
                    implicitWidth: chip.implicitWidth + 14
                    implicitHeight: chip.implicitHeight + 6
                    color: look.label.fill
                    Text {
                        id: chip
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: look.heading("pass", "")
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: 10
                        font.letterSpacing: 1.4
                    }
                }

                Text {
                    visible: look.prompt.text !== ""
                    textFormat: Text.PlainText
                    text: look.prompt.text
                    color: look.prompt.color
                    font.family: look.query.font
                    font.pixelSize: look.query.size
                }

                TextInput {
                    id: input
                    Layout.fillWidth: true
                    color: c.ink
                    font.family: look.query.font
                    font.pixelSize: look.query.size
                    clip: true
                    focus: true
                    cursorDelegate: look.caret === "block" ? blockCaret : null
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
                }

                Text {
                    id: chipCount
                    visible: look.label.kind === "chip"
                    textFormat: Text.PlainText
                    text: look.count(found.length)
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }

                Rectangle {
                    visible: look.label.kind === "pill"
                    implicitWidth: pill.implicitWidth + 18
                    implicitHeight: pill.implicitHeight + 6
                    radius: 8
                    color: look.label.fill
                    Text {
                        id: pill
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: look.heading("pass", "")
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }

            Rule {}

            // What the QR holds, then the question; the list under it picks the entry.
            ColumnLayout {
                visible: pass.mode === "qr" && !!pass.qr
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 14
                spacing: 4

                Text {
                    id: qrIssuer
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: pass.qr?.issuer ?? ""
                    elide: Text.ElideRight
                    color: c.ink
                    font.family: look.name.font
                    font.pixelSize: look.name.size + 3
                    font.weight: look.cursor.weight
                }
                Text {
                    id: qrAccount
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: pass.qr?.account ?? ""
                    elide: Text.ElideRight
                    color: c.muted
                    font.family: look.name.font
                    font.pixelSize: look.name.size
                }
                Text {
                    id: qrMeta
                    textFormat: Text.PlainText
                    text: pass.qr?.meta ?? ""
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }
                Text {
                    id: qrQuestion
                    Layout.topMargin: 8
                    textFormat: Text.PlainText
                    text: "Save to which entry?"
                    color: c.ink
                    font.family: look.name.font
                    font.pixelSize: look.name.size
                }
            }

            // Holds focus after Tab, where the plain letter keys act on the cursor row and / returns to the query.
            Item {
                id: results
                visible: pass.mode !== "new"
                Layout.fillWidth: true
                implicitHeight: list.implicitHeight + 16
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
                        pass.startNew();
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
                    y: 8
                    // Paper's rows run edge to edge; the others sit inset as tiles.
                    x: look.voice === "plain" ? 8 : look.voice === "bracket" ? 10 : 0
                    width: parent.width - 2 * x

                    // An empty store, or nothing matched, shows the keys that still work.
                    Text {
                        textFormat: Text.PlainText
                        visible: pass.listed && rows.length === 0
                        leftPadding: 20
                        topPadding: 11
                        bottomPadding: 11
                        text: look.keyText("n") + " " + look.tabText("new entry") + " · " + look.keyText("q") + " " + look.tabText("from qr") + " · " + look.keyText("esc") + " " + look.tabText("close")
                        color: c.muted
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }

                    Repeater {
                        id: rowRepeater
                        model: rows

                        Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: index === pass.selected
                            readonly property var runs: P.segments(modelData)
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
                                return otpTag.visible ? otpTag.text : "";
                            }
                            width: list.width
                            implicitHeight: row.implicitHeight + (look.voice === "caps" ? 22 : 20)
                            radius: look.cursor.radius
                            color: isCurrent ? look.cursor.fill : "transparent"

                            RowLayout {
                                id: row
                                anchors.fill: parent
                                anchors.leftMargin: look.voice === "caps" ? 20 : 12
                                anchors.rightMargin: anchors.leftMargin
                                spacing: look.voice === "plain" ? 12 : 14

                                Text {
                                    visible: look.slot !== "icon"
                                    textFormat: Text.PlainText
                                    text: look.slot === "number" ? look.number(index) : "▸"
                                    color: look.slot === "number" ? (isCurrent ? look.cursor.text : c.muted) : isCurrent ? look.cursor.marker : "transparent"
                                    font.family: look.slot === "number" ? look.name.font : fonts.ui
                                    font.pixelSize: look.slot === "number" ? 13 : 15
                                    font.bold: look.slot === "number" && isCurrent
                                }

                                // Artboard's tile holds the entry's first letter.
                                Rectangle {
                                    visible: look.slot === "icon"
                                    implicitWidth: look.tile.size
                                    implicitHeight: look.tile.size
                                    radius: look.tile.radius
                                    color: look.tile.fill
                                    Text {
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: L.line(rowItem.modelData.leaf).charAt(0).toUpperCase()
                                        color: c.ink
                                        font.family: fonts.mono
                                        font.pixelSize: 15
                                    }
                                }

                                // A shown password, in mono, in place of the name.
                                Text {
                                    id: revealedText
                                    visible: rowItem.revealed
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: rowItem.revealed ? pass.revealText : ""
                                    elide: Text.ElideRight
                                    color: rowItem.isCurrent ? look.cursor.text : look.name.color
                                    font.family: fonts.mono
                                    font.pixelSize: look.name.size
                                }

                                Row {
                                    visible: !rowItem.revealed
                                    Layout.fillWidth: true
                                    clip: true

                                    Repeater {
                                        id: runRepeater
                                        model: rowItem.runs

                                        Text {
                                            required property var modelData
                                            textFormat: Text.PlainText
                                            text: look.title(modelData.text)
                                            color: rowItem.isCurrent ? (modelData.folder ? look.cursor.detail : look.cursor.text) : modelData.folder ? c.muted : look.name.color
                                            font.family: look.name.font
                                            font.pixelSize: look.name.size
                                            font.weight: rowItem.isCurrent ? look.cursor.weight : look.name.weight
                                            font.letterSpacing: look.name.spacing
                                            font.underline: modelData.hit
                                        }
                                    }
                                }

                                Text {
                                    id: otpTag
                                    visible: rowItem.revealed || rowItem.modelData.otp
                                    textFormat: Text.PlainText
                                    text: rowItem.revealed ? "10s" : "OTP"
                                    color: rowItem.isCurrent ? look.cursor.detail : look.small.color
                                    font.family: look.small.font
                                    font.pixelSize: look.small.size
                                    font.letterSpacing: look.small.spacing
                                }
                            }
                        }
                    }
                    Text {
                        id: deleteLine
                        visible: pass.mode === "delete"
                        textFormat: Text.PlainText
                        leftPadding: 20
                        topPadding: 8
                        bottomPadding: 3
                        text: P.deleteText(look, pass.deleting).question + "  " + P.deleteText(look, pass.deleting).keys.map(k => k.key + " " + k.word).join(" · ")
                        color: c.danger
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }
                }
            }

            // The new-entry card: a path tagged new or exists, and the password it will get, h and l changing its length.
            ColumnLayout {
                visible: pass.mode === "new"
                Layout.fillWidth: true
                Layout.margins: 20
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        color: "transparent"
                        border.width: 1
                        border.color: newPath.activeFocus ? c.ink : c.line

                        TextInput {
                            id: newPath
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: c.ink
                            font.family: fonts.mono
                            font.pixelSize: 15
                            clip: true
                            Keys.onPressed: event => pass.newKey(event, false)
                        }

                        Text {
                            visible: newPath.text === ""
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12
                            text: "folder/name"
                            color: c.muted
                            font.family: fonts.mono
                            font.pixelSize: 15
                        }
                    }

                    Text {
                        id: tagText
                        textFormat: Text.PlainText
                        text: look.tabText(pass.pathTag)
                        color: pass.pathTag === "exists" ? c.danger : look.small.color
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }
                }

                // Holds focus after Tab, where h and l shorten and lengthen the password.
                Rectangle {
                    id: lengthBox
                    Layout.fillWidth: true
                    implicitHeight: 40
                    color: activeFocus ? look.cursor.fill : "transparent"
                    radius: look.cursor.radius
                    Keys.onPressed: event => pass.newKey(event, true)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Text {
                            id: preview
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: pass.generated
                            elide: Text.ElideRight
                            color: lengthBox.activeFocus ? look.cursor.text : c.ink
                            font.family: fonts.mono
                            font.pixelSize: 15
                        }
                        Text {
                            id: lengthText
                            textFormat: Text.PlainText
                            text: pass.length + " · " + look.keyText("h") + "/" + look.keyText("l")
                            color: lengthBox.activeFocus ? look.cursor.detail : look.small.color
                            font.family: look.small.font
                            font.pixelSize: look.small.size
                            font.letterSpacing: look.small.spacing
                        }
                    }
                }
            }

            Rule {}

            // The key strip as the launcher's legend draws it: chips in Artboard, tracked caps in Paper, brackets in Blueprint.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: look.voice === "plain" ? 14 : look.voice === "bracket" ? 22 : 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: look.voice === "plain" ? 10 : 12
                Layout.bottomMargin: look.voice === "bracket" ? 14 : Layout.topMargin
                spacing: look.legend("").chips ? 8 : 14

                Repeater {
                    id: keyRepeater
                    model: P.passKeys(look)

                    Rectangle {
                        id: keyPair
                        required property var modelData
                        readonly property string keyLabel: keyText.text
                        readonly property string wordLabel: wordText.text
                        width: pair.implicitWidth + (look.legend("").chips ? 14 : 0)
                        height: pair.implicitHeight + (look.legend("").chips ? 6 : 0)
                        radius: 6
                        color: look.chip.fill

                        Row {
                            id: pair
                            anchors.centerIn: parent
                            spacing: look.legend("").chips ? 6 : 5

                            Text {
                                id: keyText
                                textFormat: Text.PlainText
                                text: keyPair.modelData.key
                                color: look.chip.key
                                font.family: fonts.mono
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                                font.bold: true
                            }
                            Text {
                                id: wordText
                                visible: text !== ""
                                textFormat: Text.PlainText
                                text: keyPair.modelData.word
                                color: c.muted
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                            }
                        }
                    }
                }
            }
        }
    }

    // Blueprint's caret: a glowing accent block the height of the query.
    Component {
        id: blockCaret

        Rectangle {
            width: 11
            height: input.font.pixelSize
            color: look.prompt.color
            // Qt hides only its own caret when the query loses focus, so a delegate follows cursorVisible itself.
            visible: input.cursorVisible

            RectangularShadow {
                anchors.fill: parent
                z: -1
                blur: 9.6
                color: Qt.alpha(look.prompt.color, 0.8)
            }
        }
    }

    // A rule across the card: solid, or dashed in Blueprint.
    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: look.rule.dashed ? "transparent" : look.rule.color

        Root.Dashed {
            visible: look.rule.dashed
            anchors.fill: parent
            color: look.rule.color
        }
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib/dekho.mjs" as D
import "lib/dekho-releases.mjs" as R
import "lib/dekho-starting.mjs" as S

// The release list over the page it was opened from, the no-releases card, and Starting while a playback buffers in its own user unit.
FocusScope {
    id: page

    required property var dekho

    readonly property var c: dekho.c
    readonly property var tones: dekho.tones
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property var words: R.releasesText()
    readonly property string bodyFont: fonts.ui ?? ""
    readonly property string bin: Quickshell.shellDir + "/bin/dots-dekho-play"

    // "" when closed, else "list", "none" or "starting".
    property string mode: ""
    // What is played: id, kind, title, and a series' season, episode, name and air date.
    property var target: ({})
    // The page beneath, which gets the keys back on close.
    property Item under: null
    property var items: []
    // Auto first, once the releases are in; Auto with none to choose from would play nothing.
    readonly property var rows: asking || items.length === 0 ? [] : R.rows(items, filter)
    // What Ctrl+F's field holds; only the releases whose name contains it are listed after Auto.
    readonly property string filter: filterField.text
    // The field shows once Ctrl+F opens it, and stays while it holds text.
    property bool filterOpen: false
    property bool asking: false
    property int row: 0
    property string asked: ""
    property var events: []
    property string session: ""
    property var playArgs: []
    // Esc while systemd-run is still starting the unit stops it once it has started.
    property bool cancelled: false
    // The last playing event, kept for checks once Starting has gone.
    property var playing: null
    readonly property var st: R.starting(events)
    // Played, and Starting waits on mpv's window, which can take up to a minute to map.
    readonly property bool opening: mode === "starting" && st.playing
    // Why a play failed before it played, on one line: an error event's text, else a non-zero exit's code. "" while it goes well.
    readonly property string failure: {
        for (const e of events) {
            if (e.event === "error")
                return D.title(e.text) || "dekho could not start playback";
            if (e.event === "exit" && e.code !== 0)
                return "dekho stopped with code " + e.code;
        }
        return "";
    }
    readonly property var failKeys: [["r", "try again"], ["esc", "back"]]
    readonly property bool tv: target.kind === "tv"
    readonly property string episodeTag: tv && target.season ? "S" + target.season + " E" + target.episode : ""
    readonly property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")

    signal search

    visible: mode !== ""

    // The fail box stays on the card; the toast says it again where the keys are not.
    onFailureChanged: {
        if (failure !== "" && mode === "starting")
            dekho.toast("Could not start: " + failure);
    }

    // Enter on an episode, or a movie: its releases, best first.
    function choose(t, from) {
        target = t;
        under = from;
        playing = null;
        mode = "list";
        forceActiveFocus();
        ask();
    }

    function ask() {
        const t = target;
        const key = t.kind + " " + t.id + " " + (t.season ?? "") + " " + (t.episode ?? "") + " " + Date.now();
        asked = key;
        asking = true;
        items = [];
        row = 0;
        filterField.text = "";
        filterOpen = false;
        mode = "list";
        dekho.api(["api", "releases", "--id", String(t.id), "--kind", t.kind].concat(t.kind === "tv" ? ["-s", String(t.season), "-e", String(t.episode)] : []), answer => {
            if (page.asked !== key)
                return;
            page.asking = false;
            page.items = answer && Array.isArray(answer.items) ? R.rank(answer.items) : [];
            if (page.items.length === 0)
                page.mode = "none";
        });
    }

    // Continue watching: the title where it stopped, without a list.
    function resume(item, from) {
        target = item;
        under = from;
        playing = null;
        forceActiveFocus();
        start(["--id", String(item.id), "--kind", item.kind, "--resume"]);
    }

    function start(args) {
        events = [];
        cancelled = false;
        session = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dekho/session-" + Date.now() + ".ndjson";
        playArgs = args;
        mode = "starting";
        starter.running = true;
        dekho.follow(session, target.kind === "tv" ? target.title : "");
    }

    // r on a failed start runs the same play again, in a new session; the old tail would follow the old file.
    function retry() {
        tail.running = false;
        start(playArgs);
    }

    // Ctrl+F: the filter field, with the keys.
    function openFilter() {
        filterOpen = true;
        filterField.forceActiveFocus();
    }

    function move(by) {
        row = Math.max(0, Math.min(rows.length - 1, row + by));
        listView.reveal(row);
    }

    // A click on a row moves the cursor there and does what Enter does.
    function pick(at) {
        row = at;
        listView.reveal(at);
        stream();
    }

    function stream() {
        const r = rows[row];
        if (!r)
            return;
        // The filter field may hold the focus, and Starting takes its keys from the page's own item.
        keys.forceActiveFocus();
        start(R.playArgs(target, r));
    }

    function close() {
        keys.forceActiveFocus();
        mode = "";
        asked = "";
        if (under)
            under.forceActiveFocus();
    }

    function cancel() {
        tail.running = false;
        dekho.unfollow();
        if (starter.running)
            cancelled = true;
        else
            stopper.running = true;
        close();
    }

    function heard(line) {
        const e = D.answer(line);
        if (!e || mode !== "starting")
            return;
        events = events.concat([e]);
        if (e.event === "playing")
            playing = e;
        else if (opening && (e.event === "ended" || e.event === "exit"))
            opened();
    }

    // The wait on mpv ends: its window mapped, or mpv already quit, which a window up for less than one 500 ms poll would not show, or 120 s passed.
    function opened() {
        tail.running = false;
        close();
    }

    function drawnRows() {
        const out = [];
        for (let i = 0; i < rowRepeater.count; i++)
            out.push(rowRepeater.itemAt(i).drawn());
        return out;
    }

    function drawnSteps() {
        const out = [];
        for (let i = 0; i < stepRepeater.count; i++)
            out.push(stepRepeater.itemAt(i).drawn());
        return out;
    }

    function state() {
        return {
            releases: {
                mode: mode,
                shown: visible && card.height > 0,
                header: tagText.text,
                heading: headText.text,
                count: countText.text,
                heads: [headQuality.text, headSize.text, headSeeders.text, headAudio.text],
                cursor: row,
                rows: drawnRows(),
                filter: {
                    text: filterField.text,
                    shown: filterBox.visible,
                    focused: filterField.activeFocus,
                    family: filterField.font.family
                },
                noMatch: {
                    text: noMatchText.text,
                    shown: noMatchText.visible
                },
                none: {
                    head: noneHead.text,
                    why: noneWhy.text,
                    shown: noneBox.visible
                },
                starting: {
                    release: releaseText.text,
                    percent: percentText.text,
                    amount: amountText.text,
                    fill: track.width > 0 ? fill.width / track.width : 0,
                    steps: drawnSteps(),
                    peers: peersText.text,
                    down: downText.text,
                    up: upText.text,
                    shown: startBox.visible,
                    fail: {
                        shown: failBox.visible,
                        text: failText.text,
                        lines: failText.lineCount,
                        truncated: failText.truncated,
                        keys: Array.from({
                            length: keyRepeater.count
                        }, (_, i) => keyRepeater.itemAt(i).drawn())
                    }
                },
                playing: playing,
                session: session,
                look: {
                    cardRadius: cardFill.radius,
                    tagFill: String(tagBox.color),
                    ink: String(c.ink),
                    accent: String(c.accent),
                    barFill: String(fill.color),
                    barRadius: fill.radius,
                    cursorFill: rowRepeater.count ? String(rowRepeater.itemAt(row).color) : "",
                    cursorRadius: rowRepeater.count ? rowRepeater.itemAt(row).radius : -1,
                    markRadius: stepRepeater.count ? stepRepeater.itemAt(0).markRadius : -1
                }
            }
        };
    }

    // A series' name goes with the run, so a Dekho opened mid-play splits its label as this one does.
    Process {
        id: starter
        command: [page.bin, "--session", page.session].concat(page.target && page.target.kind === "tv" ? ["--show", page.target.title] : []).concat(page.playArgs)
        onExited: {
            if (page.cancelled)
                stopper.running = true;
            else if (page.mode === "starting")
                tail.running = true;
        }
    }

    // tail ends with the App, even one killed outright, by watching qs's pid; the unit does not, so closing Dekho never stops a film. Where tail polls, its 1 s default drew the buffers in bursts, so it polls every 0.1 s.
    Process {
        id: tail
        command: ["sh", "-c", "exec tail --pid=\"$PPID\" -n +1 -s 0.1 -F \"$1\"", "sh", page.session]
        stdout: SplitParser {
            onRead: line => page.heard(line)
        }
    }

    Process {
        id: stopper
        command: [page.bin, "--stop"]
    }

    // Starting closes once niri lists the film's mpv window, asked every 500 ms only while it waits, or after 120 s.
    Tick {
        interval: 500
        repeat: true
        triggeredOnStart: true
        running: page.opening
        onTriggered: {
            if (!mpvProbe.running)
                mpvProbe.running = true;
        }
    }
    Tick {
        interval: 120000
        running: page.opening
        onTriggered: page.opened()
    }
    // The windows' JSON on its first line, then the pids in the film's unit, so a trailer's mpv window, in a unit of its own, does not count.
    Process {
        id: mpvProbe
        command: ["sh", "-c", "niri msg -j windows; echo; cg=$(systemctl --user show -p ControlGroup --value \"$1.service\"); [ -z \"$cg\" ] || cat \"/sys/fs/cgroup$cg/cgroup.procs\" 2>/dev/null", "sh", Quickshell.env("DOTS_DEKHO_UNIT") || "dekho-play"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                if (page.opening && S.mpvMapped(lines[0], lines.slice(1).filter(l => l !== "").map(Number)))
                    page.opened();
            }
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text;
            if (page.mode === "starting") {
                if (k === Qt.Key_Escape)
                    page.cancel();
                else if (t === "r" && page.failure !== "")
                    page.retry();
            } else if (k === Qt.Key_Escape)
                page.close();
            else if (page.mode === "none" && t === "r")
                page.ask();
            else if (page.mode === "none" && t === "/") {
                page.close();
                page.search();
            } else if (page.mode === "list" && page.rows.length > 0 && k === Qt.Key_F && (event.modifiers & Qt.ControlModifier))
                page.openFilter();
            else if (page.mode === "list" && (t === "j" || k === Qt.Key_Down))
                page.move(1);
            else if (page.mode === "list" && (t === "k" || k === Qt.Key_Up))
                page.move(-1);
            else if (page.mode === "list" && (k === Qt.Key_Return || k === Qt.Key_Enter))
                page.stream();
            event.accepted = true;
        }
    }

    // The page beneath, dimmed in the paper colour.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(page.c.paper ?? "white", 0.62)
        radius: 14
    }

    // The overlay takes every click and wheel, so none reaches the page beneath; the rows' own click areas and the list's wheel sit above it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: event => event.accepted = true
    }

    Item {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: page.mode === "starting" ? 164 : 134
        width: page.mode === "starting" ? 560 : page.mode === "none" ? 600 : 900
        height: body.implicitHeight

        // A rounded card ringed in the accent.
        Rectangle {
            id: cardFill
            anchors.fill: parent
            radius: 14
            color: page.c.surface ?? "white"
            border.width: 1.5
            border.color: page.c.accent ?? "black"
        }

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                spacing: 12

                Rectangle {
                    id: tagBox
                    implicitWidth: tagText.implicitWidth + 18
                    implicitHeight: tagText.implicitHeight + 4
                    radius: 8
                    color: page.look.label.fill

                    Text {
                        id: tagText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: page.mode === "starting" ? page.words.starting : page.words.release
                        color: page.look.label.color ?? "black"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
                Text {
                    id: headText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: [D.title(page.target.title), page.episodeTag, page.mode === "starting" ? "" : D.title(page.target.name)].filter(p => p).join(" · ")
                    color: page.c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Item {
                    id: filterBox
                    visible: page.mode === "list" && (page.filterOpen || filterField.text !== "")
                    Layout.preferredWidth: 180
                    implicitHeight: filterField.implicitHeight + 6

                    TextInput {
                        id: filterField
                        anchors.left: parent.left
                        anchors.right: parent.right
                        clip: true
                        color: page.c.ink ?? "black"
                        selectionColor: page.c.accent ?? "red"
                        selectedTextColor: page.c.surface ?? "white"
                        font.family: page.bodyFont
                        font.pixelSize: 13
                        onTextChanged: page.row = 0
                        Keys.onPressed: event => {
                            const k = event.key;
                            if (k === Qt.Key_Escape) {
                                if (text !== "")
                                    text = "";
                                else
                                    page.close();
                            } else if (k === Qt.Key_Down)
                                page.move(1);
                            else if (k === Qt.Key_Up)
                                page.move(-1);
                            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                                page.stream();
                            else if (!(k === Qt.Key_F && (event.modifiers & Qt.ControlModifier)))
                                return;
                            event.accepted = true;
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: page.c.accent ?? "gray"
                    }
                }
                Rectangle {
                    visible: page.mode === "list"
                    implicitWidth: countText.implicitWidth + 18
                    implicitHeight: countText.implicitHeight + 6
                    radius: 8
                    color: page.look.tile.fill

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: page.asking ? "" : page.words.count(Math.max(0, page.rows.length - 1))
                        color: page.c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
            }

            Rule {
                Layout.fillWidth: true
            }

            // The list: a column per thing asked for, the cursor on the best.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.topMargin: 10
                Layout.bottomMargin: 8
                visible: page.mode === "list"
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    Layout.topMargin: 4
                    Layout.bottomMargin: 8
                    spacing: 12

                    Head {
                        id: headQuality
                        Layout.fillWidth: true
                        text: page.words.columns[0]
                    }
                    Head {
                        id: headSize
                        Layout.preferredWidth: 90
                        horizontalAlignment: Text.AlignRight
                        text: page.words.columns[1]
                    }
                    Head {
                        id: headSeeders
                        Layout.preferredWidth: 90
                        horizontalAlignment: Text.AlignRight
                        text: page.words.columns[2]
                    }
                    Head {
                        id: headAudio
                        Layout.preferredWidth: 150
                        text: page.words.columns[3]
                    }
                }

                Flickable {
                    id: listView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(listColumn.implicitHeight, 420)
                    contentHeight: listColumn.implicitHeight
                    interactive: false
                    clip: true

                    // Under the rows, the wheel scrolls the list and leaves the cursor where it is.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: event => listView.contentY = D.wheeled(listView.contentY, event.angleDelta.y, listView.contentHeight, listView.height)
                    }

                    function reveal(i) {
                        const r = rowRepeater.itemAt(i);
                        if (!r)
                            return;
                        if (r.y < contentY)
                            contentY = r.y;
                        else if (r.y + r.height > contentY + height)
                            contentY = r.y + r.height - height;
                    }

                    Column {
                        id: listColumn
                        width: listView.width

                        Repeater {
                            id: rowRepeater
                            model: page.rows

                            ReleaseRow {
                                width: listColumn.width
                            }
                        }
                    }
                }
                Text {
                    id: noMatchText
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    Layout.topMargin: 8
                    visible: page.filter !== "" && page.rows.length === 1
                    textFormat: Text.PlainText
                    text: page.words.noMatch(D.title(page.filter))
                    color: page.c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // No releases: what happened and the keys that might help.
            ColumnLayout {
                id: noneBox
                Layout.fillWidth: true
                Layout.margins: 20
                visible: page.mode === "none"
                spacing: 14

                Text {
                    id: noneHead
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: page.words.none
                    color: page.c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    id: noneWhy
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: page.words.noneWhy(page.target.kind) + (page.target.air_date === page.today ? " " + page.words.noneToday : "")
                    color: page.c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: 13
                    lineHeight: 1.5
                    wrapMode: Text.Wrap
                }
                Rule {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                }
                Text {
                    textFormat: Text.PlainText
                    text: page.words.tryHead
                    color: page.c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 11
                }
                Repeater {
                    model: page.words.tries(page.target.kind)

                    Row {
                        required property var modelData
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: page.look.keyText(modelData[0])
                            color: page.c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: modelData[1]
                            color: page.c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: 13
                        }
                    }
                }
            }

            // A start that failed: the error on one line, laid out as No releases is.
            ColumnLayout {
                id: failBox
                Layout.fillWidth: true
                Layout.margins: 20
                visible: page.mode === "starting" && page.failure !== ""

                Text {
                    id: failText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: page.failure
                    color: page.c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // Starting: progress to what mpv needs, the steps, and the swarm.
            ColumnLayout {
                id: startBox
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 20
                Layout.bottomMargin: 22
                visible: page.mode === "starting" && page.failure === ""
                spacing: 18

                Text {
                    id: releaseText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: D.title(page.st.release)
                    color: page.c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        id: track
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 4
                        color: page.c.line ?? "gray"

                        Rectangle {
                            id: fill
                            width: track.width * page.st.progress
                            height: parent.height
                            radius: track.radius
                            color: page.c.accent ?? "red"
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            id: percentText
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: page.st.percent
                            color: page.c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                        }
                        Text {
                            id: amountText
                            textFormat: Text.PlainText
                            text: page.st.amount
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        id: stepRepeater
                        model: S.steps(page.st)

                        StepRow {}
                    }
                }
                Rule {
                    Layout.fillWidth: true
                }
                Row {
                    Layout.fillWidth: true
                    spacing: 24

                    Stat {
                        id: peersText
                        text: page.st.peers
                    }
                    Stat {
                        id: downText
                        text: page.st.down
                    }
                    Stat {
                        id: upText
                        text: page.st.up
                    }
                }
            }

            Rule {
                Layout.fillWidth: true
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                spacing: 8

                Repeater {
                    id: keyRepeater
                    model: page.look.keys(page.mode === "starting" ? (page.failure !== "" ? page.failKeys : page.words.startKeys) : page.mode === "none" ? page.words.noneKeys : page.words.keys)

                    Rectangle {
                        required property var modelData

                        function drawn() {
                            return [keyName.text, keyWord.text];
                        }

                        implicitWidth: keyPair.implicitWidth + 14
                        implicitHeight: keyPair.implicitHeight + 6
                        radius: 6
                        color: "transparent"

                        Row {
                            id: keyPair
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                id: keyName
                                textFormat: Text.PlainText
                                text: modelData.key
                                color: page.c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                            Text {
                                id: keyWord
                                textFormat: Text.PlainText
                                text: modelData.word
                                color: page.c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }

    component Rule: Rectangle {
        implicitHeight: 1
        color: page.c.line ?? "gray"
    }

    component Head: Text {
        textFormat: Text.PlainText
        color: page.c.muted ?? "gray"
        font.family: page.bodyFont
        font.pixelSize: 11
    }

    component Stat: Text {
        textFormat: Text.PlainText
        color: page.c.ink ?? "black"
        font.family: page.bodyFont
        font.pixelSize: 12
    }

    // One release: quality and its name, size, seeders and audio; the cursor's row is tinted and ringed in the accent.
    component ReleaseRow: Rectangle {
        id: rel

        required property var modelData
        required property int index
        readonly property bool auto: modelData.auto === true
        readonly property bool cursor: page.row === index
        readonly property color soft: page.c.muted ?? "gray"

        function drawn() {
            return {
                quality: qualityText.text,
                name: nameText.text,
                lines: nameText.lineCount,
                truncated: nameText.truncated,
                size: sizeText.text,
                seeders: seedersText.text,
                audio: audioText.text,
                audioLines: audioText.lineCount,
                best: bestBox.visible ? bestText.text : "",
                auto: auto,
                cursor: cursor
            };
        }

        height: 40
        radius: 10
        color: cursor ? page.look.label.fill : "transparent"
        border.width: cursor ? 1.5 : 0
        border.color: page.c.accent ?? "blue"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    id: qualityText
                    textFormat: Text.PlainText
                    text: rel.auto ? page.words.auto : D.title(rel.modelData.quality)
                    color: rel.cursor ? page.tones.deep : page.c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Rectangle {
                    id: bestBox
                    // The best release is the first after Auto, which a filter may have removed.
                    visible: !rel.auto && rel.modelData.hash === page.items[0].hash
                    implicitWidth: bestText.implicitWidth + 16
                    implicitHeight: bestText.implicitHeight + 4
                    radius: 8
                    color: page.c.ink ?? "black"

                    Text {
                        id: bestText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: page.words.best
                        color: page.tones.card
                        font.family: page.bodyFont
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
                Text {
                    id: nameText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: D.title(rel.modelData.title)
                    color: rel.soft
                    font.family: page.bodyFont
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
            Text {
                id: sizeText
                Layout.preferredWidth: 90
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: D.title(rel.modelData.size)
                color: rel.soft
                font.family: page.bodyFont
                font.pixelSize: 12
            }
            Text {
                id: seedersText
                Layout.preferredWidth: 90
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: String(rel.modelData.seeders ?? "")
                color: rel.soft
                font.family: page.bodyFont
                font.pixelSize: 12
            }
            Text {
                id: audioText
                Layout.preferredWidth: 150
                textFormat: Text.PlainText
                text: D.title(rel.modelData.audio)
                color: rel.soft
                font.family: page.bodyFont
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Click {
            name: "release:" + rel.index
            onTapped: page.pick(rel.index)
        }
    }

    // A step: filled with a tick once done, ringed in the accent while current, an outline while still to come.
    component StepRow: RowLayout {
        id: step

        required property var modelData
        readonly property bool done: modelData.state === "done"
        readonly property bool current: modelData.state === "current"
        readonly property real markRadius: mark.radius

        function drawn() {
            return {
                text: stepText.text,
                state: modelData.state
            };
        }

        spacing: 12

        Rectangle {
            id: mark
            implicitWidth: 16
            implicitHeight: 16
            radius: 8
            color: step.done ? page.c.accent ?? "black" : "transparent"
            border.width: step.done ? 0 : step.current ? 2 : 1.5
            border.color: (step.current ? page.c.accent : page.c.line) ?? "gray"

            FilesIcon {
                anchors.centerIn: parent
                visible: step.done
                size: 9
                box: 9
                stroke: 1.5
                path: "M1.5 4.6L3.5 6.6L7.5 2.4"
                color: page.tones.card
            }
        }
        Text {
            id: stepText
            textFormat: Text.PlainText
            text: step.modelData.text
            color: (step.done || step.current ? page.c.ink : page.c.muted) ?? "black"
            font.family: page.bodyFont
            font.pixelSize: 14
            font.weight: step.current ? Font.Medium : Font.Normal
        }
    }
}

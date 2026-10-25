import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "lib/dekho.mjs" as D
import "lib/dekho-releases.mjs" as R
import "lib/dekho-starting.mjs" as S

// The release list over the page it was opened from, the no-releases card, and Starting while a playback buffers in its own user unit.
FocusScope {
    id: page

    required property var dekho

    readonly property var c: dekho.c
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property string voice: dekho.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property var words: R.releasesText(voice)
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""
    readonly property string bin: Quickshell.shellDir + "/../bin/dots-dekho-play"

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
                    chamfer: chamfer.visible,
                    shadow: hardShadow.visible,
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

    Process {
        id: starter
        command: [page.bin, "--session", page.session].concat(page.playArgs)
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

    // Starting closes once niri lists mpv's window, asked every 500 ms only while it waits, or after 120 s.
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
    Process {
        id: mpvProbe
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (page.opening && S.mpvMapped(text))
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

    // The page beneath, dimmed in each board's paper.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(page.c.paper ?? "white", plain ? 0.62 : 0.72)
        radius: plain ? 14 : 0
    }

    Item {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: page.mode === "starting" ? 164 : 134
        width: page.mode === "starting" ? 560 : page.mode === "none" ? 600 : 900
        height: body.implicitHeight

        // Paper's hard shadow, Artboard's rounded card ringed in its accent, Blueprint's cut corners.
        Rectangle {
            id: hardShadow
            x: 6
            y: 6
            width: parent.width
            height: parent.height
            visible: page.caps
            color: page.c.ink ?? "black"
        }
        Rectangle {
            id: cardFill
            anchors.fill: parent
            visible: !page.bracket
            radius: page.plain ? 14 : 0
            color: page.c.surface ?? "white"
            border.width: 1.5
            border.color: (page.plain ? page.c.accent : page.c.ink) ?? "black"
        }
        Shape {
            id: chamfer
            anchors.fill: parent
            visible: page.bracket
            preferredRendererType: Shape.GeometryRenderer

            ShapePath {
                strokeColor: page.c.accent ?? "cyan"
                strokeWidth: 1
                fillColor: page.c.surface ?? "black"
                PathPolyline {
                    path: [Qt.point(16.5, 0.5), Qt.point(card.width - 0.5, 0.5), Qt.point(card.width - 0.5, card.height - 16.5), Qt.point(card.width - 16.5, card.height - 0.5), Qt.point(0.5, card.height - 0.5), Qt.point(0.5, 16.5), Qt.point(16.5, 0.5)]
                }
            }
        }

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: plain ? 56 : -1
                Layout.leftMargin: bracket ? 22 : plain ? 18 : 16
                Layout.rightMargin: bracket ? 22 : plain ? 18 : 16
                Layout.topMargin: plain ? 0 : bracket ? 12 : 14
                Layout.bottomMargin: plain ? 0 : bracket ? 10 : 14
                spacing: bracket ? 6 : 12

                Rectangle {
                    id: tagBox
                    implicitWidth: tagText.implicitWidth + (bracket ? 0 : plain ? 18 : 14)
                    implicitHeight: tagText.implicitHeight + (bracket ? 0 : 4)
                    radius: plain ? 8 : 0
                    color: page.caps ? page.c.ink ?? "black" : page.plain ? page.look.label.fill : "transparent"

                    Text {
                        id: tagText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: page.mode === "starting" ? page.words.starting : page.words.release
                        color: (page.caps ? page.c.surface : page.c.accent) ?? "black"
                        font.family: page.bodyFont
                        font.pixelSize: page.plain ? 12 : 10
                        font.weight: page.plain ? Font.Medium : page.bracket ? Font.Bold : Font.Normal
                        font.letterSpacing: page.plain ? 0 : 1.4
                    }
                }
                Text {
                    visible: page.bracket
                    textFormat: Text.PlainText
                    text: "//"
                    color: page.c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 10
                }
                Text {
                    id: headText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: [D.title(page.target.title), page.episodeTag, page.mode === "starting" ? "" : D.title(page.target.name)].filter(p => p).join(" · ")
                    color: page.c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: page.plain ? 16 : page.bracket ? 12 : 15
                    font.weight: page.plain ? Font.Medium : Font.Normal
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
                        font.pixelSize: page.bracket ? 12 : 13
                        onTextChanged: page.row = 0
                        Keys.onPressed: event => {
                            const k = event.key;
                            if (k === Qt.Key_Escape) {
                                if (text !== "")
                                    text = "";
                                else
                                    page.close();
                            } else if (event.text === "j" || k === Qt.Key_Down)
                                page.move(1);
                            else if (event.text === "k" || k === Qt.Key_Up)
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
                    implicitWidth: countText.implicitWidth + (plain ? 18 : 0)
                    implicitHeight: countText.implicitHeight + (plain ? 6 : 0)
                    radius: 8
                    color: plain ? page.look.tile.fill : "transparent"

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: page.asking ? "" : page.words.count(Math.max(0, page.rows.length - 1))
                        color: page.c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: page.bracket ? 10 : 11
                        font.weight: page.plain ? Font.Medium : Font.Normal
                        font.letterSpacing: page.bracket ? 1.6 : 0
                    }
                }
            }

            Rule {
                Layout.fillWidth: true
                dashed: bracket
                color: page.c.line ?? "gray"
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
                    font.family: (page.caps ? page.fonts.display : page.bodyFont) ?? ""
                    font.pixelSize: page.caps ? 25 : page.plain ? 18 : 16
                    font.weight: page.caps ? Font.Normal : Font.Bold
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
                    dashed: page.bracket
                    color: page.c.line ?? "gray"
                }
                Text {
                    textFormat: Text.PlainText
                    text: page.words.tryHead
                    color: page.c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: page.plain ? 11 : 10
                    font.letterSpacing: page.plain ? 0 : 1.4
                }
                Repeater {
                    model: page.words.tries(page.target.kind)

                    Row {
                        required property var modelData
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: page.look.keyText(modelData[0])
                            color: (page.bracket ? page.c.accent : page.c.ink) ?? "black"
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
                    text: page.words.up(page.failure)
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
                    font.letterSpacing: page.bracket ? 0.7 : 0
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
                        radius: page.plain ? 4 : 0
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
                            text: page.words.up(page.st.percent)
                            color: page.c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.letterSpacing: page.bracket ? 0.7 : 0
                        }
                        Text {
                            id: amountText
                            textFormat: Text.PlainText
                            text: page.words.up(page.st.amount)
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.letterSpacing: page.bracket ? 0.7 : 0
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
                    dashed: page.bracket
                    color: page.c.line ?? "gray"
                }
                Row {
                    Layout.fillWidth: true
                    spacing: 24

                    Stat {
                        id: peersText
                        text: page.words.up(page.st.peers)
                    }
                    Stat {
                        id: downText
                        text: page.words.up(page.st.down)
                    }
                    Stat {
                        id: upText
                        text: page.words.up(page.st.up)
                    }
                }
            }

            Rule {
                Layout.fillWidth: true
                dashed: page.bracket
                color: (page.caps ? page.c.ink : page.c.line) ?? "gray"
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: plain ? 14 : 16
                Layout.rightMargin: plain ? 14 : 16
                Layout.topMargin: plain ? 10 : 11
                Layout.bottomMargin: plain ? 10 : 11
                spacing: plain ? 8 : 16

                Repeater {
                    id: keyRepeater
                    model: page.look.keys(page.mode === "starting" ? (page.failure !== "" ? page.failKeys : page.words.startKeys) : page.mode === "none" ? page.words.noneKeys : page.words.keys)

                    Rectangle {
                        required property var modelData

                        function drawn() {
                            return [keyName.text, keyWord.text];
                        }

                        implicitWidth: keyPair.implicitWidth + (page.plain ? 14 : 0)
                        implicitHeight: keyPair.implicitHeight + (page.plain ? 6 : 0)
                        radius: 6
                        color: page.plain ? page.look.tile.fill : "transparent"

                        Row {
                            id: keyPair
                            anchors.centerIn: parent
                            spacing: page.bracket ? 8 : 6

                            Text {
                                id: keyName
                                textFormat: Text.PlainText
                                text: modelData.key
                                color: (page.bracket ? page.c.accent : page.c.ink) ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: page.caps ? 10 : 11
                                font.weight: page.plain ? Font.Medium : Font.Bold
                                font.letterSpacing: page.caps ? 1 : page.bracket ? 1.5 : 0
                            }
                            Text {
                                id: keyWord
                                textFormat: Text.PlainText
                                text: modelData.word
                                color: page.c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: page.caps ? 10 : 11
                                font.letterSpacing: page.caps ? 1 : page.bracket ? 1.5 : 0
                            }
                        }
                    }
                }
            }
        }
    }

    component Rule: Item {
        property bool dashed: false
        property color color: "black"
        implicitHeight: 1

        Rectangle {
            anchors.fill: parent
            visible: !parent.dashed
            color: parent.color
        }
        Dashed {
            anchors.fill: parent
            visible: parent.dashed
            color: parent.color
        }
    }

    component Head: Text {
        textFormat: Text.PlainText
        color: page.c.muted ?? "gray"
        font.family: page.bodyFont
        font.pixelSize: page.caps ? 10 : 11
        font.letterSpacing: page.plain ? 0 : 1.4
    }

    component Stat: Text {
        textFormat: Text.PlainText
        color: page.c.ink ?? "black"
        font.family: page.bodyFont
        font.pixelSize: 12
        font.letterSpacing: page.bracket ? 0.7 : 0
    }

    // One release: quality and its name, size, seeders and audio; the cursor's row inverts in Paper and Blueprint, Artboard tints and rings it.
    component ReleaseRow: Rectangle {
        id: rel

        required property var modelData
        required property int index
        readonly property bool auto: modelData.auto === true
        readonly property bool cursor: page.row === index
        readonly property bool inverse: cursor && !page.plain
        readonly property color fore: inverse ? page.c.surface ?? "white" : page.c.ink ?? "black"
        readonly property color soft: inverse ? (page.caps ? page.c.line : page.c.surface) ?? "white" : page.c.muted ?? "gray"

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
        radius: page.plain ? 10 : 0
        color: cursor ? (page.plain ? page.look.label.fill : page.bracket ? page.c.accent : page.c.ink) ?? "black" : "transparent"
        border.width: cursor && page.plain ? 1.5 : 0
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
                    color: rel.cursor && page.plain ? "#2638C9" : rel.fore
                    font.family: page.bodyFont
                    font.pixelSize: page.plain ? 14 : 13
                    font.weight: rel.inverse && page.bracket ? Font.Bold : Font.Medium
                }
                Rectangle {
                    id: bestBox
                    // The best release is the first after Auto, which a filter may have removed.
                    visible: !rel.auto && rel.modelData.hash === page.items[0].hash
                    implicitWidth: bestText.implicitWidth + (page.bracket ? 0 : page.plain ? 16 : 12)
                    implicitHeight: bestText.implicitHeight + (page.bracket ? 0 : page.plain ? 4 : 2)
                    radius: page.plain ? 8 : 0
                    color: page.bracket ? "transparent" : (page.plain ? page.c.ink : rel.inverse ? page.c.surface : page.c.ink) ?? "black"

                    Text {
                        id: bestText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: page.words.best
                        color: (page.bracket ? rel.fore : page.plain ? "white" : rel.inverse ? page.c.ink : page.c.surface) ?? "white"
                        font.family: page.bodyFont
                        font.pixelSize: page.plain ? 11 : 10
                        font.weight: page.caps ? Font.Normal : page.plain ? Font.Medium : Font.Bold
                        font.letterSpacing: page.plain ? 0 : 1.4
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
                font.letterSpacing: page.bracket ? 0.7 : 0
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
                font.letterSpacing: page.bracket ? 0.7 : 0
            }
            Text {
                id: audioText
                Layout.preferredWidth: 150
                textFormat: Text.PlainText
                text: D.title(rel.modelData.audio)
                color: rel.soft
                font.family: page.bodyFont
                font.pixelSize: 12
                font.letterSpacing: page.bracket ? 0.7 : 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }
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
            radius: page.plain ? 8 : 0
            color: step.done ? (page.caps ? page.c.ink : page.c.accent) ?? "black" : "transparent"
            border.width: step.done ? 0 : step.current ? (page.bracket ? 1 : 2) : page.bracket ? 1 : 1.5
            border.color: (step.current ? page.c.accent : page.plain ? page.c.line : page.c.muted) ?? "gray"

            FilesIcon {
                anchors.centerIn: parent
                visible: step.done
                size: 9
                box: page.plain ? 9 : 16
                stroke: page.plain ? 1.5 : 2.6
                path: page.plain ? "M1.5 4.6L3.5 6.6L7.5 2.4" : "M3.5 8.5L6.5 11.5L12.5 4.5"
                color: (page.plain ? "white" : page.c.surface) ?? "white"
            }
        }
        Text {
            id: stepText
            textFormat: Text.PlainText
            text: step.modelData.text
            color: (step.done || step.current ? page.c.ink : page.c.muted) ?? "black"
            font.family: page.bodyFont
            font.pixelSize: page.plain ? 14 : 13
            font.weight: step.current ? Font.Medium : Font.Normal
        }
    }
}

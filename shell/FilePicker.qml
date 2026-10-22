import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/voice.mjs" as L
import "lib/picker.mjs" as P

// The file picker any app's open dialog gets, drawn by the shell for bin/dots-portal: places, the folder's rows and a key strip in each theme's voice; it loads on a request and unloads 30 s after it closes.
Item {
    id: picker

    required property var theme
    // The desktop entries, which name the asking app.
    required property var apps
    property bool shown: false
    property int opens: 0
    property var openMs: null
    // When the request line came in, or -1 once the card's first frame is swapped.
    property real openT0: -1
    // The request from the Portal service, with its answer function, while it shows.
    property var request: null
    // The request as the card draws it, kept while its close still plays; open mode reads only its app and folder so far.
    property var seen: null
    readonly property string mode: seen?.mode ?? ""
    readonly property bool multiple: seen?.multiple ?? false
    readonly property var filters: seen?.filters ?? []
    readonly property int filter: seen?.filter ?? 0
    readonly property string name: seen?.name ?? ""
    readonly property string accept: seen?.accept ?? ""
    property string folder: ""
    property var rows: []
    property bool listed: false
    // A folder change while a listing runs asks for one more after it.
    property bool stale: false
    property int selected: 0
    property var pins: []
    readonly property bool busy: request !== null || lister.running

    readonly property string home: Quickshell.env("HOME")
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property string voice: look.voice
    readonly property bool caps: voice === "caps"
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property string appText: P.oneLine(P.appName(apps, seen?.app ?? ""))
    readonly property var places: [
        { path: home, label: "Home" },
        { path: home + "/Downloads", label: "Downloads" },
        { path: home + "/Codes", label: "Codes" },
        { path: home + "/Pictures", label: "Pictures" }
    ]
    readonly property Root.Motion motion: Root.Motion {
        shown: picker.shown
        tokens: picker.theme.tokens
        onDrawingChanged: if (!drawing)
            picker.seen = null
    }

    function show(r) {
        request = r;
        seen = r;
        openT0 = r.t0;
        openMs = null;
        opens += 1;
        bookmarksFile.reload();
        enter(r.folder.charAt(0) === "/" ? r.folder.replace(/\/+$/, "") || "/" : home);
        shown = true;
        keyTarget.forceActiveFocus();
    }

    function reply(text) {
        const r = request;
        request = null;
        shown = false;
        r?.answer(text);
    }

    // Esc, or another surface opening, cancels, so the app never waits on a card nobody sees.
    function close() {
        if (request)
            reply(P.answerLine(1, []));
    }

    // The app went away on its own, so there is nothing to answer.
    function dismiss() {
        request = null;
        shown = false;
    }

    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function pathOf(row) {
        return (folder === "/" ? "" : folder) + "/" + row.name;
    }

    function enter(path) {
        folder = path;
        selected = 0;
        listed = false;
        list();
    }

    function up() {
        if (folder !== "/")
            enter(folder.slice(0, folder.lastIndexOf("/")) || "/");
    }

    function list() {
        if (lister.running) {
            stale = true;
            return;
        }
        lister.command = ["python3", "-c", lister.script, folder];
        lister.running = true;
    }

    function move(by) {
        selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }

    // Enter answers a file and opens a folder.
    function choose() {
        const row = rows[selected];
        if (!row)
            return;
        if (row.dir)
            enter(pathOf(row));
        else
            reply(P.answerLine(0, [pathOf(row)]));
    }

    function tilde(path) {
        return path === home ? "~" : path.indexOf(home + "/") === 0 ? "~" + path.slice(home.length) : path;
    }

    function state() {
        const drawn = [];
        for (let i = 0; i < rowList.count; i++) {
            const item = rowList.itemAtIndex(i);
            if (item)
                drawn.push(item.drawn());
        }
        const shownPlaces = [];
        for (let i = 0; i < placeRepeater.count; i++)
            shownPlaces.push(placeRepeater.itemAt(i).drawn());
        const keys = [];
        for (let i = 0; i < keyRepeater.count; i++)
            keys.push((keyRepeater.itemAt(i).keyLabel + " " + keyRepeater.itemAt(i).wordLabel).trim());
        return JSON.stringify({
            loaded: true,
            open: shown,
            mode: mode,
            app: appText,
            title: P.oneLine(seen?.title ?? ""),
            heading: headingLabel.text,
            headingTruncated: headingLabel.truncated,
            headingLines: headingLabel.lineCount,
            folder: folder,
            path: pathLabel.text,
            count: countLabel.text,
            listed: listed,
            rows: drawn,
            selected: selected,
            places: shownPlaces,
            hint: keys.join(" · "),
            busy: busy,
            openMs: openMs,
            opens: opens,
            settled: motion.settled,
            drawing: picker.visible,
            cardBox: card.drawnBox(),
            keyboard: picker.Window.active
        });
    }

    onSelectedChanged: rowList.positionViewAtIndex(selected, ListView.Contain)

    // One JSON array of the folder's entries off the render loop: names as they are spelt, a folder with how many entries it holds; dotfiles stay hidden.
    Process {
        id: lister
        readonly property string script: "import json, os, sys\n" + "out = []\n" + "for e in os.scandir(sys.argv[1]):\n" + "    if e.name.startswith('.'):\n" + "        continue\n" + "    try:\n" + "        st = e.stat()\n" + "        d = e.is_dir()\n" + "        n = 0\n" + "        if d:\n" + "            try:\n" + "                n = sum(1 for x in os.scandir(e.path) if not x.name.startswith('.'))\n" + "            except OSError:\n" + "                pass\n" + "        out.append({'name': e.name, 'dir': d, 'size': st.st_size, 'mtime': st.st_mtime * 1000, 'count': n})\n" + "    except OSError:\n" + "        pass\n" + "print(json.dumps(out, ensure_ascii=False))\n"
        stdout: StdioCollector {
            id: listOut
        }
        onExited: {
            if (picker.stale) {
                picker.stale = false;
                Qt.callLater(picker.list);
                return;
            }
            let entries = [];
            try {
                entries = JSON.parse(listOut.text);
            } catch (e) {
                entries = [];
            }
            picker.rows = P.sortRows(entries);
            picker.selected = 0;
            picker.listed = true;
        }
    }

    FileView {
        id: bookmarksFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || picker.home + "/.config") + "/gtk-3.0/bookmarks"
        printErrors: false
        onLoaded: picker.pins = P.parseBookmarks(text())
        onLoadFailed: picker.pins = []
    }

    Component.onCompleted: Root.State.loaded.push("picker")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "picker")

    visible: motion.drawing

    // Up and Down move the cursor; letters are left free for the filter.
    Item {
        id: keyTarget
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Down)
                picker.move(1);
            else if (event.key === Qt.Key_Up)
                picker.move(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                picker.choose();
            else if (event.key === Qt.Key_Right) {
                if (picker.rows[picker.selected]?.dir)
                    picker.choose();
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backspace)
                picker.up();
            else if (event.key === Qt.Key_Escape)
                picker.close();
            else
                return;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(c.paper, card.style.wash)
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 3)
        width: Math.min(1080, parent.width - 32)
        height: Math.min(620, parent.height - 32)
        tokens: picker.theme.tokens
        label: headingLabel.text
        motion: picker.motion

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The heading in the launcher's label idiom: Paper's ink chip, Artboard's pill, Blueprint's header line.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 16
                Layout.bottomMargin: 14
                spacing: 12

                Rectangle {
                    readonly property bool boxed: look.label.kind !== "header"
                    implicitWidth: headingLabel.width + (boxed ? 16 : 0)
                    implicitHeight: headingLabel.implicitHeight + (boxed ? 6 : 0)
                    radius: look.label.kind === "pill" ? 8 : 0
                    color: boxed ? look.label.fill : "transparent"

                    Text {
                        id: headingLabel
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, card.width - 80)
                        textFormat: Text.PlainText
                        text: P.headingText(picker.voice, picker.appText)
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        color: look.label.kind === "header" ? look.small.color : look.label.color
                        font.family: look.label.kind === "header" ? look.small.font : fonts.ui
                        font.pixelSize: look.label.kind === "pill" ? 12 : 11
                        font.weight: look.label.kind === "pill" ? Font.Medium : Font.Normal
                        font.letterSpacing: plain ? 0 : 1.4
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            Rule {}

            // The folder, from ~, and how many rows it holds.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                spacing: 10

                Text {
                    visible: bracket
                    textFormat: Text.PlainText
                    text: "> FOLDER"
                    color: c.accent
                    font.family: fonts.mono
                    font.pixelSize: 12
                    font.letterSpacing: 1.4
                }
                Text {
                    id: pathLabel
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: P.oneLine(picker.tilde(picker.folder))
                    maximumLineCount: 1
                    elide: Text.ElideMiddle
                    color: c.ink
                    font.family: fonts.mono
                    font.pixelSize: 13
                }
                Text {
                    id: countLabel
                    textFormat: Text.PlainText
                    text: picker.rows.length + (plain ? " items" : " ITEMS")
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size + 1
                    font.letterSpacing: look.small.spacing
                }
            }

            Rule {}

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Home, Downloads, Codes and Pictures, then the GTK bookmarks as pins.
                Column {
                    Layout.preferredWidth: 200
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    leftPadding: 8
                    rightPadding: 8
                    spacing: 0

                    Repeater {
                        id: placeRepeater
                        model: picker.places.concat(picker.pins)

                        Column {
                            id: placeItem
                            required property var modelData
                            required property int index
                            readonly property bool here: modelData.path === picker.folder
                            function drawn() {
                                return (numberText.visible ? numberText.text + " " : "") + labelText.text;
                            }
                            width: 184

                            Text {
                                visible: placeItem.index === 0 || placeItem.index === picker.places.length
                                topPadding: placeItem.index === 0 ? 4 : 10
                                bottomPadding: 6
                                leftPadding: 10
                                textFormat: Text.PlainText
                                text: placeItem.index === 0 ? (plain ? "Places" : "PLACES") : (plain ? "Pins" : "PINS  " + picker.pins.length)
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                            }

                            Rectangle {
                                width: parent.width
                                height: 32
                                radius: plain ? 8 : 0
                                color: placeItem.here && plain ? look.tile.fill : "transparent"

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 10
                                    width: parent.width - 20
                                    spacing: 10

                                    Text {
                                        id: numberText
                                        visible: bracket
                                        textFormat: Text.PlainText
                                        text: placeItem.here ? "▸" : look.number(placeItem.index)
                                        color: placeItem.here ? c.accent : c.muted
                                        font.family: fonts.mono
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        id: labelText
                                        width: parent.width - (numberText.visible ? numberText.width + 10 : 0)
                                        textFormat: Text.PlainText
                                        text: bracket ? P.oneLine(placeItem.modelData.label).toUpperCase() : P.oneLine(placeItem.modelData.label)
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                        color: placeItem.here ? (bracket ? c.accent : c.ink) : c.muted
                                        font.family: bracket ? fonts.mono : fonts.ui
                                        font.pixelSize: 14
                                        font.weight: placeItem.here ? Font.Medium : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 1
                    color: look.rule.color
                }

                // The rows: folders first, each with its size or item count and when it changed.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 8
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        Layout.bottomMargin: 6
                        spacing: 12

                        Item {
                            implicitWidth: 16
                        }
                        Head {
                            Layout.fillWidth: true
                            text: plain ? "Name ↑" : "NAME"
                        }
                        Head {
                            Layout.preferredWidth: 90
                            horizontalAlignment: Text.AlignRight
                            text: plain ? "Size" : "SIZE"
                        }
                        Head {
                            Layout.preferredWidth: 130
                            horizontalAlignment: Text.AlignRight
                            text: plain ? "Modified" : "MODIFIED"
                        }
                    }

                    ListView {
                        id: rowList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: picker.rows
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: index === picker.selected
                            readonly property color ink: isCurrent ? look.cursor.text : c.ink
                            readonly property color dim: isCurrent ? look.cursor.detail : c.muted
                            // The row as drawn, for the state function.
                            function drawn() {
                                return {
                                    name: nameText.text,
                                    dir: modelData.dir,
                                    size: sizeLabel.text,
                                    modified: dateLabel.text,
                                    elided: nameText.truncated,
                                    lines: nameText.lineCount
                                };
                            }
                            width: rowList.width
                            height: 34
                            radius: look.cursor.radius
                            color: isCurrent ? look.cursor.fill : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                // Paper and Blueprint mark the cursor row; Artboard draws a folder or a page.
                                Item {
                                    implicitWidth: 16
                                    implicitHeight: 16

                                    Text {
                                        visible: !plain
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: "▸"
                                        color: rowItem.isCurrent ? look.cursor.marker === "transparent" ? look.cursor.text : look.cursor.marker : "transparent"
                                        font.family: fonts.ui
                                        font.pixelSize: 14
                                    }
                                    Rectangle {
                                        visible: plain
                                        anchors.centerIn: parent
                                        width: rowItem.modelData.dir ? 14 : 11
                                        height: rowItem.modelData.dir ? 10 : 13
                                        radius: 2
                                        color: "transparent"
                                        border.width: 1.3
                                        border.color: rowItem.ink
                                    }
                                }
                                Text {
                                    id: nameText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: P.oneLine(rowItem.modelData.name) + (rowItem.modelData.dir ? "/" : "")
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: rowItem.ink
                                    font.family: bracket ? fonts.mono : fonts.ui
                                    font.pixelSize: 14
                                    font.weight: rowItem.modelData.dir || rowItem.isCurrent ? Font.Medium : Font.Normal
                                }
                                Text {
                                    id: sizeLabel
                                    Layout.preferredWidth: 90
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: P.sizeText(rowItem.modelData)
                                    color: rowItem.dim
                                    font.family: fonts.mono
                                    font.pixelSize: 12
                                }
                                Text {
                                    id: dateLabel
                                    Layout.preferredWidth: 130
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: P.dateText(picker.voice, rowItem.modelData.mtime, Date.now())
                                    color: rowItem.dim
                                    font.family: fonts.mono
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 1
                    color: look.rule.color
                }

                // The cursor file's preview goes here.
                Item {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                }
            }

            Rule {}

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                spacing: plain ? 8 : 16

                Repeater {
                    id: keyRepeater
                    model: P.pickerKeys(picker.voice)

                    Rectangle {
                        id: keyPair
                        required property var modelData
                        readonly property string keyLabel: keyText.text
                        readonly property string wordLabel: wordText.text
                        width: pair.implicitWidth + (plain ? 14 : 0)
                        height: pair.implicitHeight + (plain ? 6 : 0)
                        radius: 6
                        color: look.chip.fill

                        Row {
                            id: pair
                            anchors.centerIn: parent
                            spacing: plain ? 6 : 5

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

    component Head: Text {
        textFormat: Text.PlainText
        color: look.small.color
        font.family: look.small.font
        font.pixelSize: look.small.size
        font.letterSpacing: look.small.spacing
    }
}

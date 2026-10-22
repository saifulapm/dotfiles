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
    // Every entry of the folder, dotfiles too, so ctrl+h, the query and the filter never relist.
    property var entries: []
    readonly property var allPlaces: places.concat(pins)
    property string query: ""
    readonly property var matches: P.placeMatches(allPlaces, query)
    property bool hidden: false
    property int filterAt: 0
    readonly property var currentFilter: filters[filterAt] ?? null
    readonly property string filterName: P.oneLine(currentFilter?.name ?? "")
    // A query that matches places narrows them and leaves the rows alone.
    readonly property var rows: P.shownRows(entries, {
        hidden: hidden,
        filter: currentFilter,
        query: matches.length > 0 ? "" : query
    })
    property bool listed: false
    // A folder change while a listing runs asks for one more after it.
    property bool stale: false
    // The row to put the cursor on once the listing lands: the folder just left.
    property string landOn: ""
    property int selected: 0
    property var pins: []
    // "list" or "places": where Up, Down and Enter act.
    property string side: "list"
    property int placeAt: 0
    property bool typingPath: false
    property string typed: ""
    readonly property var split: P.splitPath(typed, home, folder)
    // The typed path's parent as last listed, and whether that listing worked.
    property string pathFolder: ""
    property var pathEntries: []
    property bool pathOk: false
    property bool pathStale: false
    readonly property var choices: pathFolder === split.parent ? P.completions(pathEntries, split.tail) : []
    property int choice: 0
    readonly property var cursorRow: rows[selected] ?? null
    readonly property bool previewing: !typingPath && cursorRow !== null && !cursorRow.dir
    readonly property bool preview: previewing && previewImage.status === Image.Ready
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
        hidden = false;
        side = "list";
        typingPath = false;
        filterAt = r.filter >= 0 && r.filter < r.filters.length ? r.filter : 0;
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

    // Walking to a folder clears the query; a query that opened a place keeps it.
    function enter(path, keepQuery) {
        if (!keepQuery)
            query = "";
        folder = path;
        selected = 0;
        landOn = "";
        listed = false;
        list();
    }

    function up() {
        if (folder === "/")
            return;
        const left = folder.slice(folder.lastIndexOf("/") + 1);
        enter(folder.slice(0, folder.lastIndexOf("/")) || "/");
        landOn = left;
    }

    // Exactly one place matching opens it; otherwise the query narrows places or rows by binding.
    function setQuery(q) {
        query = q;
        selected = 0;
        if (matches.length === 1 && allPlaces[matches[0].index].path !== folder)
            enter(allPlaces[matches[0].index].path, true);
    }

    function setTyped(t) {
        typed = t;
        choice = 0;
        completeList();
    }

    function completeList() {
        if (completer.running) {
            pathStale = true;
            return;
        }
        if (pathFolder === split.parent && pathOk)
            return;
        completer.asked = split.parent;
        completer.command = ["python3", "-c", lister.script, split.parent];
        completer.running = true;
    }

    function togglePath() {
        typingPath = !typingPath;
        if (typingPath)
            setTyped("");
    }

    // Tab puts the cursor row's name in place of the begun one.
    function completePath() {
        const c = choices[choice];
        if (c)
            setTyped((typed === "~" ? "~/" : typed.slice(0, typed.length - split.tail.length)) + c.name + "/");
    }

    // Enter goes to the typed folder when it is one, else to the cursor row.
    function goPath() {
        const base = split.parent === "/" ? "" : split.parent;
        let to = "";
        if (pathFolder === split.parent && pathOk && split.tail === "")
            to = split.parent;
        else if (pathEntries.some(e => e.dir && e.name === split.tail) && pathFolder === split.parent)
            to = base + "/" + split.tail;
        else if (choices[choice])
            to = base + "/" + choices[choice].name;
        if (to === "")
            return;
        typingPath = false;
        enter(to);
    }

    function cycleFilter() {
        if (filters.length > 1)
            filterAt = (filterAt + 1) % filters.length;
    }

    function toSide() {
        side = side === "list" ? "places" : "list";
        if (side === "places") {
            const here = allPlaces.findIndex(p => p.path === folder);
            placeAt = here >= 0 ? here : 0;
        }
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
        if (typingPath)
            choice = Math.max(0, Math.min(choices.length - 1, choice + by));
        else if (side === "places")
            placeAt = Math.max(0, Math.min(allPlaces.length - 1, placeAt + by));
        else
            selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }

    // Enter answers a file and opens a folder or the place under the cursor.
    function choose() {
        if (typingPath)
            return goPath();
        if (side === "places")
            return enter(allPlaces[placeAt].path);
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
        const lit = [];
        for (let i = 0; i < placeRepeater.count; i++) {
            shownPlaces.push(placeRepeater.itemAt(i).drawn());
            if (placeRepeater.itemAt(i).hit)
                lit.push(placeRepeater.itemAt(i).drawn());
        }
        const done = [];
        for (let i = 0; i < completionRepeater.count; i++)
            done.push(completionRepeater.itemAt(i).drawn());
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
            matches: lit,
            focus: side,
            typed: typedLabel.text,
            prompt: promptLabel.text,
            match: matchLabel.text,
            hidden: hidden,
            pathMode: typingPath,
            completionHead: typingPath ? completionHeadLabel.text : "",
            completions: typingPath ? done : [],
            choice: choice,
            previewShown: previewName.visible,
            preview: preview,
            previewName: previewName.text,
            previewDims: previewDims.text,
            previewDetail: previewDetail.text,
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
    onRowsChanged: if (selected >= rows.length)
        selected = Math.max(0, rows.length - 1)

    // One JSON array of the folder's entries off the render loop: names as they are spelt, dotfiles too, a folder with how many visible entries it holds, a file with its guessed mime type for the app's filters.
    Process {
        id: lister
        readonly property string script: "import json, mimetypes, os, sys\n" + "out = []\n" + "for e in os.scandir(sys.argv[1]):\n" + "    try:\n" + "        st = e.stat()\n" + "        d = e.is_dir()\n" + "        n = 0\n" + "        if d:\n" + "            try:\n" + "                n = sum(1 for x in os.scandir(e.path) if not x.name.startswith('.'))\n" + "            except OSError:\n" + "                pass\n" + "        m = '' if d else (mimetypes.guess_type(e.name)[0] or '')\n" + "        out.append({'name': e.name, 'dir': d, 'size': st.st_size, 'mtime': st.st_mtime * 1000, 'count': n, 'mime': m})\n" + "    except OSError:\n" + "        pass\n" + "print(json.dumps(out, ensure_ascii=False))\n"
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
            picker.entries = entries;
            const back = picker.rows.findIndex(r => r.name === picker.landOn);
            picker.selected = back >= 0 ? back : 0;
            picker.listed = true;
        }
    }

    // The typed path's parent, listed by the same script, for the completions.
    Process {
        id: completer
        property string asked: ""
        stdout: StdioCollector {
            id: completeOut
        }
        onExited: code => {
            if (picker.pathStale) {
                picker.pathStale = false;
                Qt.callLater(picker.completeList);
                return;
            }
            let found = [];
            try {
                found = JSON.parse(completeOut.text);
            } catch (e) {
                found = [];
            }
            picker.pathEntries = Array.isArray(found) ? found : [];
            picker.pathOk = code === 0;
            picker.pathFolder = asked;
            if (asked !== picker.split.parent)
                Qt.callLater(picker.completeList);
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

    // Up and Down move the cursor of the list, the places or the completions; letters type the query or the path.
    Item {
        id: keyTarget
        Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (ctrl && event.key === Qt.Key_L)
                picker.togglePath();
            else if (ctrl && event.key === Qt.Key_H)
                picker.hidden = !picker.hidden;
            else if (event.key === Qt.Key_Down)
                picker.move(1);
            else if (event.key === Qt.Key_Up)
                picker.move(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                picker.choose();
            else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)))
                picker.cycleFilter();
            else if (event.key === Qt.Key_Tab) {
                if (picker.typingPath)
                    picker.completePath();
                else
                    picker.toSide();
            } else if (event.key === Qt.Key_Escape) {
                if (picker.typingPath)
                    picker.typingPath = false;
                else
                    picker.close();
            } else if (picker.typingPath) {
                if (event.key === Qt.Key_Backspace)
                    picker.setTyped(picker.typed.slice(0, -1));
                else if (!ctrl && event.text.length > 0 && event.text.charCodeAt(0) >= 32)
                    picker.setTyped(picker.typed + event.text);
                else
                    return;
            } else if (event.key === Qt.Key_Right) {
                if (picker.side === "list" && picker.cursorRow?.dir)
                    picker.choose();
            } else if (event.key === Qt.Key_Backspace) {
                if (picker.query !== "")
                    picker.setQuery(picker.query.slice(0, -1));
                else
                    picker.up();
            } else if (event.key === Qt.Key_Left)
                picker.up();
            else if (!ctrl && event.text.length > 0 && event.text.charCodeAt(0) >= 32)
                picker.setQuery(picker.query + event.text);
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

                // ctrl+l turns the query into the path, with a focus ring, as every theme board draws it.
                Text {
                    id: promptLabel
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: bracket ? (picker.typingPath ? "> PATH" : ">") : picker.typingPath ? (plain ? "path" : "PATH") : ""
                    color: bracket ? c.accent : look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size + 1
                    font.letterSpacing: look.small.spacing
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: typedLabel.implicitHeight + 8
                    radius: plain ? 6 : 0
                    color: "transparent"
                    border.width: picker.typingPath ? 2 : 0
                    border.color: c.accent

                    Text {
                        id: typedLabel
                        anchors.verticalCenter: parent.verticalCenter
                        x: picker.typingPath ? 8 : 0
                        width: parent.width - 2 * x
                        textFormat: Text.PlainText
                        text: P.oneLine(picker.typingPath ? picker.typed : picker.query)
                        maximumLineCount: 1
                        elide: Text.ElideLeft
                        color: c.ink
                        font.family: picker.typingPath || bracket ? fonts.mono : fonts.ui
                        font.pixelSize: picker.typingPath ? 15 : 20
                    }
                }
                Text {
                    id: matchLabel
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: picker.typingPath ? P.matchText(picker.voice, "path", picker.choices.length, "") : picker.matches.length > 0 ? P.matchText(picker.voice, "places", picker.matches.length, P.oneLine(picker.allPlaces[picker.matches[0].index].label)) : ""
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size + 1
                    font.letterSpacing: look.small.spacing
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
                    text: picker.typingPath && plain ? "typing a path" : P.countText(picker.voice, picker.rows.length, picker.filterName, picker.hidden)
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
                        model: picker.allPlaces

                        Column {
                            id: placeItem
                            required property var modelData
                            required property int index
                            readonly property bool here: modelData.path === picker.folder
                            readonly property var hit: picker.matches.find(m => m.index === index) ?? null
                            readonly property bool atCursor: picker.side === "places" && picker.placeAt === index
                            readonly property bool lit: hit !== null || (here && picker.matches.length === 0)
                            function drawn() {
                                return (numberText.visible ? numberText.text + " " : "") + labelText.drawn();
                            }
                            // Blueprint's caps are for its own places; a pin is a folder name and keeps its case.
                            readonly property string label: bracket && index < picker.places.length ? P.oneLine(modelData.label).toUpperCase() : P.oneLine(modelData.label)
                            readonly property int marks: hit ? hit.length : 0
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
                                radius: plain ? 8 : look.cursor.radius
                                color: placeItem.atCursor ? look.cursor.fill : placeItem.here && plain ? look.tile.fill : "transparent"

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
                                    Marked {
                                        id: labelText
                                        width: parent.width - (numberText.visible ? numberText.width + 10 : 0)
                                        mark: placeItem.label.slice(0, placeItem.marks)
                                        rest: placeItem.label.slice(placeItem.marks)
                                        tint: placeItem.atCursor ? look.cursor.text : placeItem.lit ? (bracket ? c.accent : c.ink) : c.muted
                                        family: bracket ? fonts.mono : fonts.ui
                                        weight: placeItem.here ? Font.Medium : Font.Normal
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

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                    ListView {
                        id: rowList
                        anchors.fill: parent
                        // The list dims behind the completions while a path is typed.
                        opacity: picker.typingPath ? 0.3 : 1
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

                    // The folders the typed path completes to, over the list: the begun name underlined, the first row holding the cursor.
                    Rectangle {
                        visible: picker.typingPath
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Math.min(parent.height, completionColumn.implicitHeight + 12)
                        radius: look.cursor.radius
                        color: c.paper
                        border.width: 1
                        border.color: c.ink
                        clip: true

                        Column {
                            id: completionColumn
                            x: 6
                            y: 6
                            width: parent.width - 12

                            Text {
                                id: completionHeadLabel
                                width: parent.width
                                leftPadding: 12
                                topPadding: 4
                                bottomPadding: 6
                                textFormat: Text.PlainText
                                text: P.completionHead(picker.voice, picker.choices.length, P.oneLine(picker.tilde(picker.split.parent)), P.oneLine(picker.split.tail))
                                maximumLineCount: 1
                                elide: Text.ElideMiddle
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                            }

                            Repeater {
                                id: completionRepeater
                                model: picker.choices

                                Rectangle {
                                    id: completionItem
                                    required property var modelData
                                    required property int index
                                    readonly property bool isCurrent: index === picker.choice
                                    // Paper lists the whole path with its date, Artboard the name with the path, Blueprint the name with DIR.
                                    readonly property string lead: picker.caps ? P.oneLine(picker.tilde(picker.split.parent === "/" ? "/" : picker.split.parent + "/")) : ""
                                    readonly property string name: P.oneLine(modelData.name)
                                    function drawn() {
                                        return {
                                            name: completionName.drawn(),
                                            detail: completionDetail.text
                                        };
                                    }
                                    width: parent.width
                                    height: 32
                                    radius: look.cursor.radius
                                    color: isCurrent ? look.cursor.fill : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        Marked {
                                            id: completionName
                                            Layout.fillWidth: true
                                            lead: completionItem.lead
                                            mark: completionItem.name.slice(0, picker.split.tail.length)
                                            rest: completionItem.name.slice(picker.split.tail.length) + (picker.plain ? "" : "/")
                                            tint: completionItem.isCurrent ? look.cursor.text : c.ink
                                            family: fonts.mono
                                            size: 13
                                        }
                                        Text {
                                            id: completionDetail
                                            textFormat: Text.PlainText
                                            text: picker.plain ? P.oneLine(picker.tilde((picker.split.parent === "/" ? "" : picker.split.parent) + "/" + completionItem.modelData.name)) : picker.bracket ? "DIR" : P.dateText(picker.voice, completionItem.modelData.mtime, Date.now())
                                            Layout.maximumWidth: 280
                                            maximumLineCount: 1
                                            elide: Text.ElideMiddle
                                            color: completionItem.isCurrent ? look.cursor.detail : c.muted
                                            font.family: fonts.mono
                                            font.pixelSize: 12
                                        }
                                    }
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

                // The cursor file: its picture when Qt decodes it, then its name, size, kind and date; hidden while a path is typed.
                Item {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true

                    Column {
                        visible: picker.previewing
                        x: 18
                        y: 18
                        width: parent.width - 36
                        spacing: 8

                        Image {
                            id: previewImage
                            // Sized by hand: PreserveAspectFit makes Qt decode to fill the bound, scaling a small image up and losing its size.
                            readonly property real fit: Math.min(1, parent.width / Math.max(1, implicitWidth), 186 / Math.max(1, implicitHeight))
                            width: implicitWidth * fit
                            height: implicitHeight * fit
                            asynchronous: true
                            cache: false
                            // A bound keeps a 12 MP photo from decoding whole; without a fill mode Qt never scales up, so an image within 1024 px reads its true size.
                            sourceSize.width: 1024
                            sourceSize.height: 1024
                            source: picker.previewing ? "file://" + picker.pathOf(picker.cursorRow).split("/").map(encodeURIComponent).join("/") : ""
                        }
                        Text {
                            id: previewName
                            width: parent.width
                            textFormat: Text.PlainText
                            text: picker.cursorRow ? P.oneLine(picker.cursorRow.name) : ""
                            maximumLineCount: 1
                            elide: Text.ElideMiddle
                            color: c.ink
                            font.family: bracket ? fonts.mono : fonts.ui
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }
                        Text {
                            id: previewDims
                            visible: text !== ""
                            textFormat: Text.PlainText
                            text: picker.cursorRow ? P.previewText(picker.voice, picker.cursorRow, picker.preview ? previewImage.implicitWidth : 0, previewImage.implicitHeight).dims : ""
                            color: c.ink
                            font.family: fonts.mono
                            font.pixelSize: 15
                        }
                        Text {
                            id: previewDetail
                            textFormat: Text.PlainText
                            text: picker.cursorRow ? P.previewText(picker.voice, picker.cursorRow, 0, 0).detail : ""
                            color: c.muted
                            font.family: fonts.mono
                            font.pixelSize: 12
                        }
                        Text {
                            id: previewDate
                            textFormat: Text.PlainText
                            text: picker.cursorRow ? P.stampText(picker.voice, picker.cursorRow.mtime) : ""
                            color: c.muted
                            font.family: fonts.mono
                            font.pixelSize: 12
                        }
                    }
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
                    model: picker.typingPath ? P.pathKeys(picker.voice) : P.pickerKeys(picker.voice)

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

    // A name with its matched letters underlined, in three plain texts so a file's name never reads as markup; the end elides.
    component Marked: RowLayout {
        id: markedRow
        property string lead: ""
        property string mark: ""
        property string rest: ""
        property color tint: c.ink
        property string family: fonts.ui
        property int size: 14
        property int weight: Font.Normal
        // As drawn, the underlined letters between <u> and </u>.
        function drawn() {
            return leadText.text + (markText.text !== "" && markText.font.underline ? "<u>" + markText.text + "</u>" : markText.text) + restText.text;
        }
        spacing: 0

        Text {
            id: leadText
            visible: text !== ""
            textFormat: Text.PlainText
            text: markedRow.lead
            color: markedRow.tint
            font.family: markedRow.family
            font.pixelSize: markedRow.size
            font.weight: markedRow.weight
        }
        Text {
            id: markText
            visible: text !== ""
            textFormat: Text.PlainText
            text: markedRow.mark
            color: markedRow.tint
            font.family: markedRow.family
            font.pixelSize: markedRow.size
            font.weight: markedRow.weight
            font.underline: true
        }
        Text {
            id: restText
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: markedRow.rest
            maximumLineCount: 1
            elide: Text.ElideRight
            color: markedRow.tint
            font.family: markedRow.family
            font.pixelSize: markedRow.size
            font.weight: markedRow.weight
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

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/voice.mjs" as L
import "lib/picker.mjs" as P
import "lib/files.mjs" as F

// The file picker any app's open dialog gets, drawn by the shell for bin/dots-portal: places, the folder's rows and a key strip; it loads on a request and unloads 30 s after it closes.
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
    readonly property bool saving: mode === "save"
    readonly property bool multiple: seen?.multiple ?? false
    readonly property bool choosingFolder: mode === "folder"
    // The marked files' names; a folder change clears them, so a name is enough.
    property var marked: []
    readonly property var filters: seen?.filters ?? []
    readonly property int filter: seen?.filter ?? 0
    readonly property string name: seen?.name ?? ""
    readonly property string accept: seen?.accept ?? ""
    // The save field: the app's suggested name, then what is typed; typed characters go here, not to the query.
    property string saveName: ""
    // "exists" while the replace question shows, else why the last Enter refused the name, until the next edit.
    property string notice: ""
    readonly property bool asking: notice === "exists"
    property string folder: ""
    // Every entry of the folder, dotfiles too, so ctrl+h, the query and the filter never relist.
    property var entries: []
    readonly property var allPlaces: places.concat(pins)
    property string query: ""
    readonly property var matches: P.placeMatches(allPlaces, query)
    property bool hidden: false
    // ctrl+, cycles date, name and size; every request opens on date, newest first, or on DOTS_PICKER_SORT's, which checks that walk rows by name set.
    property string sort: P.SORT_FIRST
    property int filterAt: 0
    readonly property var currentFilter: filters[filterAt] ?? null
    readonly property string filterName: P.oneLine(currentFilter?.name ?? "")
    // A query that matches places narrows them and leaves the rows alone.
    readonly property var rows: P.shownRows(entries, {
        hidden: hidden,
        filter: currentFilter,
        query: matches.length > 0 ? "" : query,
        folders: choosingFolder,
        sort: sort
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
    // Enter came before the typed path's folder was listed, so it goes once the listing lands.
    property bool goPending: false
    // Up and Down (as -1 and 1) and Enter (as "enter") that came before the folder shown was listed act in order on its rows once they land; any other key drops them.
    property var held: []
    readonly property var choices: pathFolder === split.parent ? P.completions(pathEntries, split.tail) : []
    property int choice: 0
    readonly property var cursorRow: rows[selected] ?? null
    readonly property bool previewing: !saving && !choosingFolder && !typingPath && cursorRow !== null && !cursorRow.dir
    readonly property bool preview: previewing && previewImage.status === Image.Ready
    readonly property string cursorPath: previewing ? pathOf(cursorRow) : ""
    // The size the header reader last found, and for which file; a file it has not read yet draws no dimensions line.
    property var dims: ({
            path: "",
            width: 0,
            height: 0
        })
    property bool sizeStale: false
    readonly property var meta: previewing ? P.previewText(cursorRow, dims.path === cursorPath ? dims.width : 0, dims.height) : null
    onCursorPathChanged: measure()
    readonly property bool busy: request !== null || lister.running

    readonly property string home: Quickshell.env("HOME")
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
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
        sort = Quickshell.env("DOTS_PICKER_SORT") || P.SORT_FIRST;
        side = "list";
        typingPath = false;
        held = [];
        notice = "";
        dims = {
            path: "",
            width: 0,
            height: 0
        };
        saveName = P.oneLine(r.name);
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
        marked = [];
        selected = saving ? -1 : 0;
        landOn = saving ? saveName : "";
        // The last folder's rows go with it, so no key acts on them here and no card draws them.
        entries = [];
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
        goPending = false;
        completeList();
    }

    function completeList() {
        if (completer.running) {
            pathStale = true;
            return;
        }
        // A listing that ran stale leaves no exit to send an Enter typed during it, so a parent already listed sends it here.
        if (pathFolder === split.parent && pathOk) {
            if (goPending && typingPath) {
                goPending = false;
                goPath();
            }
            return;
        }
        completer.asked = split.parent;
        completer.command = ["python3", "-c", P.LIST_SCRIPT, split.parent];
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
        if (completer.running || pathFolder !== split.parent) {
            goPending = true;
            return;
        }
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

    // The cursor sits on the file the name would replace, and on no row otherwise, so Enter saves unless Up or Down picked a folder.
    function setName(n) {
        saveName = P.nameText(n);
        notice = "";
        selected = rows.findIndex(r => !r.dir && r.name === saveName);
    }

    // Enter asks first about a name already there, and answers nothing for a name it refuses.
    function save() {
        const problem = P.saveProblem(saveName, entries);
        if (problem !== "")
            notice = problem;
        else
            reply(P.answerLine(0, [pathOf({ name: saveName })]));
    }

    // The cursor stays on its row through the new order; a save with no row under it keeps none.
    function cycleSort() {
        const name = selected >= 0 && cursorRow ? cursorRow.name : null;
        sort = P.nextSort(sort, choosingFolder);
        if (name !== null)
            selected = Math.max(0, rows.findIndex(r => r.name === name));
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
        lister.command = ["python3", "-c", P.LIST_SCRIPT, folder];
        lister.running = true;
    }

    // One header read at a time; a cursor that moved on during it asks again for the file it rests on.
    function measure() {
        if (sizer.running) {
            sizeStale = true;
            return;
        }
        if (cursorPath === "" || dims.path === cursorPath)
            return;
        sizer.asked = cursorPath;
        sizer.command = ["python3", "-c", P.SIZE_SCRIPT, cursorPath];
        sizer.running = true;
    }

    function move(by) {
        if (typingPath)
            choice = Math.max(0, Math.min(choices.length - 1, choice + by));
        else if (side === "places")
            placeAt = Math.max(0, Math.min(allPlaces.length - 1, placeAt + by));
        else if (!listed)
            held = held.concat([by]);
        else {
            selected = Math.max(0, Math.min(rows.length - 1, selected + by));
            if (saving && cursorRow && !cursorRow.dir) {
                saveName = P.nameText(cursorRow.name);
                notice = "";
            }
        }
    }

    // Enter answers a file and opens a folder or the place under the cursor.
    function choose() {
        if (typingPath)
            return goPath();
        if (side === "places")
            return enter(allPlaces[placeAt].path);
        if (!listed) {
            held = held.concat(["enter"]);
            return;
        }
        const row = rows[selected];
        // A name that is not UTF-8 shows with U+FFFD, so its path names no file to answer or enter.
        if (row?.undecodable)
            return;
        if (saving && !row?.dir)
            return save();
        if (!row)
            return;
        if (P.answersMarked(multiple, marked, row))
            return chooseAll();
        if (row.dir)
            enter(pathOf(row));
        else
            reply(P.answerLine(0, [pathOf(row)]));
    }

    // ctrl+Enter answers the folder shown, which enter() sets before its listing runs, or the marked files; false leaves it to Enter.
    function chooseAll() {
        if (choosingFolder)
            reply(P.answerLine(0, [folder]));
        else if (multiple && marked.length > 0)
            reply(P.answerLine(0, P.markedPaths(entries, marked, folder)));
        else
            return false;
        return true;
    }

    // A click on a row does what the keys do there: the cursor moves to it, Shift and Ctrl mark, a save names the file. Behind the replace question, the path field or an unlisted folder it changes nothing, as the keys.
    function clickRow(i, mods) {
        if (asking || typingPath || !listed || !rows[i])
            return false;
        side = "list";
        const r = F.clicked(rows, marked, selected, i, mods, (m, row) => multiple ? P.toggleMark(m, row) : m);
        marked = r.marked;
        selected = r.selected;
        if (saving && !cursorRow.dir) {
            saveName = P.nameText(cursorRow.name);
            notice = "";
        }
        return true;
    }

    // A double click is Enter on the row the first click selected.
    function openRow(i) {
        if (clickRow(i, {}))
            choose();
    }

    // A click on a place opens it as Enter does, a folder still listing too, so a stuck listing can be left.
    function openPlace(i) {
        if (asking || typingPath)
            return;
        side = "places";
        placeAt = i;
        choose();
    }

    function tilde(path) {
        return path === home ? "~" : path.indexOf(home + "/") === 0 ? "~" + path.slice(home.length) : path;
    }

    // Where an item draws, in the card's own coordinates.
    function box(item) {
        if (!item.visible)
            return null;
        const p = item.mapToItem(card, 0, 0);
        return {
            x: p.x,
            y: p.y,
            width: item.width,
            height: item.height
        };
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
        const lines = [];
        for (let i = 0; i < metaRepeater.count; i++)
            lines.push(metaRepeater.itemAt(i).drawn());
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
            marked: marked,
            focus: saving && side === "list" && !typingPath && !asking ? "name" : side,
            name: saving && !typingPath ? typedLabel.text : "",
            question: asking && noticeLabel.visible,
            notice: notice,
            typed: typedLabel.text,
            prompt: promptLabel.text,
            match: matchLabel.text,
            chip: chipLabel.visible ? chipLabel.text : "",
            heads: [nameHead.text, sizeHead.text, dateHead.text],
            cardSize: [card.width, card.height],
            boxes: {
                heading: box(headingLabel),
                query: box(typedLabel),
                match: box(matchLabel),
                chip: box(chipLabel),
                path: box(pathLabel),
                count: box(countLabel)
            },
            hidden: hidden,
            sort: sort,
            pathMode: typingPath,
            completionHead: typingPath ? completionHeadLabel.text : "",
            completions: typingPath ? done : [],
            choice: choice,
            previewShown: previewName.visible,
            preview: preview,
            previewName: previewName.text,
            previewBadge: badgeBox.visible ? badgeLabel.text : "",
            previewNameFont: [previewName.font.family, previewName.font.pixelSize],
            previewLines: lines,
            previewDims: lines.length > 0 && lines[0].indexOf(" × ") > 0 ? lines[0] : "",
            foot: footLabel.visible ? footLabel.text : "",
            hint: (noticeLabel.visible ? [noticeLabel.text] : []).concat(keys).join(" · "),
            busy: busy,            openMs: openMs,
            opens: opens,
            settled: motion.settled,
            drawing: picker.visible,
            cardBox: card.drawnBox(),
            keyboard: picker.Window.active
        });
    }

    onSelectedChanged: rowList.positionViewAtIndex(selected, ListView.Contain)
    onRowsChanged: if (selected >= rows.length)
        selected = saving ? -1 : Math.max(0, rows.length - 1)

    // The folder's entries, listed off the render loop.
    Process {
        id: lister
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
            picker.selected = back >= 0 ? back : picker.saving ? -1 : 0;
            picker.listed = true;
            // An Enter here that opens a folder holds the keys after it again, for that folder's rows.
            const keys = picker.held;
            picker.held = [];
            for (const k of keys) {
                if (k === "enter")
                    picker.choose();
                else
                    picker.move(k);
            }
        }
    }

    // The cursor file's width and height from its header, read off the render loop.
    Process {
        id: sizer
        property string asked: ""
        stdout: StdioCollector {
            id: sizeOut
        }
        onExited: {
            if (picker.sizeStale) {
                picker.sizeStale = false;
                Qt.callLater(picker.measure);
                return;
            }
            const wh = sizeOut.text.trim().split(" ").map(Number);
            picker.dims = {
                path: asked,
                width: wh.length === 2 && wh[0] > 0 ? wh[0] : 0,
                height: wh.length === 2 && wh[1] > 0 ? wh[1] : 0
            };
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
            else if (picker.goPending && picker.typingPath) {
                picker.goPending = false;
                picker.goPath();
            }
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
            // The replace question takes only Enter, which replaces, and Esc, which keeps the file.
            if (picker.asking) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    picker.notice = "";
                    picker.reply(P.answerLine(0, [picker.pathOf({ name: picker.saveName })]));
                } else if (event.key === Qt.Key_Escape)
                    picker.notice = "";
                event.accepted = true;
                return;
            }
            if (![Qt.Key_Return, Qt.Key_Enter, Qt.Key_Up, Qt.Key_Down].includes(event.key))
                picker.held = [];
            const onList = !picker.typingPath && picker.side === "list";
            if (ctrl && event.key === Qt.Key_L)
                picker.togglePath();
            else if (ctrl && event.key === Qt.Key_Space) {
                if (picker.multiple && onList)
                    picker.marked = P.toggleMark(picker.marked, picker.cursorRow);
            } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !picker.typingPath) {
                if (!picker.chooseAll())
                    picker.choose();
            }
            else if (ctrl && event.key === Qt.Key_H)
                picker.hidden = !picker.hidden;
            else if (ctrl && event.key === Qt.Key_Comma && !picker.typingPath)
                picker.cycleSort();
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
            } else if (picker.saving && event.key === Qt.Key_Backspace)
                picker.setName(picker.saveName.slice(0, -1));
            else if (picker.saving && !ctrl && event.text.length > 0 && event.text.charCodeAt(0) >= 32)
                picker.setName(picker.saveName + event.text);
            else if (event.key === Qt.Key_Right) {
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
        color: card.wash
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 3)
        width: Math.min(1080, parent.width - 32)
        height: Math.min(620, parent.height - 32)
        tokens: picker.theme.tokens
        motion: picker.motion

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The heading on the label's pill.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 16
                Layout.bottomMargin: 14
                spacing: 12

                Rectangle {
                    implicitWidth: headingLabel.width + 16
                    implicitHeight: headingLabel.implicitHeight + 6
                    radius: 8
                    color: look.label.fill

                    Text {
                        id: headingLabel
                        anchors.centerIn: parent
                        // Under half the card, so a 200-character app name elides and the query and its chips stay inside.
                        width: Math.min(implicitWidth, Math.round(card.width * 0.45) - 16)
                        textFormat: Text.PlainText
                        text: P.headingText(picker.appText, picker.mode, picker.multiple)
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                // ctrl+l turns the query into the path, with a focus ring.
                Text {
                    id: promptLabel
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: picker.typingPath ? "path" : picker.saving ? "Name" : ""
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size + 1
                    font.letterSpacing: look.small.spacing
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: typedLabel.implicitHeight + 8
                    radius: 6
                    color: "transparent"
                    border.width: picker.typingPath || picker.saving ? 2 : 0
                    border.color: c.accent

                    Text {
                        id: typedLabel
                        anchors.verticalCenter: parent.verticalCenter
                        x: picker.typingPath || picker.saving ? 8 : 0
                        width: parent.width - 2 * x
                        textFormat: Text.PlainText
                        // The save name is stripped as it is typed and drawn as is, so a space typed last still shows.
                        text: picker.typingPath ? P.oneLine(picker.typed) : picker.saving ? picker.saveName : P.oneLine(picker.query)
                        maximumLineCount: 1
                        elide: Text.ElideLeft
                        color: c.ink
                        font.family: picker.typingPath ? fonts.mono : fonts.ui
                        font.pixelSize: picker.typingPath || picker.saving ? 15 : 20
                    }
                }
                Text {
                    id: matchLabel
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: picker.typingPath ? P.matchText("path", picker.choices.length, "") : picker.matches.length > 0 ? P.matchText("places", picker.matches.length, P.oneLine(picker.allPlaces[picker.matches[0].index].label)) : ""
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size + 1
                    font.letterSpacing: look.small.spacing
                }
                Text {
                    id: chipLabel
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: P.chipText(picker.mode, picker.marked.length)
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
                    text: picker.typingPath ? "typing a path" : P.countText(picker.rows.length, picker.filterName, picker.hidden, picker.mode)
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
                                return labelText.drawn();
                            }
                            readonly property string label: P.oneLine(modelData.label)
                            readonly property int marks: hit ? hit.length : 0
                            width: 184

                            Text {
                                visible: placeItem.index === 0 || placeItem.index === picker.places.length
                                topPadding: placeItem.index === 0 ? 4 : 10
                                bottomPadding: 6
                                leftPadding: 10
                                textFormat: Text.PlainText
                                text: placeItem.index === 0 ? "Places" : "Pins"
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                            }

                            Rectangle {
                                width: parent.width
                                height: 32
                                radius: 8
                                color: placeItem.atCursor ? look.cursor.fill : placeItem.here ? look.tile.fill : "transparent"

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 10
                                    width: parent.width - 20
                                    spacing: 10

                                    Marked {
                                        id: labelText
                                        width: parent.width
                                        mark: placeItem.label.slice(0, placeItem.marks)
                                        rest: placeItem.label.slice(placeItem.marks)
                                        tint: placeItem.atCursor ? look.cursor.text : placeItem.lit ? c.ink : c.muted
                                        family: fonts.ui
                                        weight: placeItem.here ? Font.Medium : Font.Normal
                                    }
                                }

                                // A click on a place opens it, as Enter does.
                                Root.Click {
                                    name: "picker-place:" + placeItem.index
                                    onTapped: picker.openPlace(placeItem.index)
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                    implicitWidth: 1
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
                        // The column the rows sort by is arrowed: names A to Z, the largest and the newest first.
                        Head {
                            id: nameHead
                            Layout.fillWidth: true
                            text: picker.sort === "name" ? "Name ↑" : "Name"
                        }
                        // A folder request lists folders, so the column counts their items.
                        Head {
                            id: sizeHead
                            Layout.preferredWidth: 90
                            horizontalAlignment: Text.AlignRight
                            text: picker.choosingFolder ? "Items" : picker.sort === "size" ? "Size ↓" : "Size"
                        }
                        Head {
                            id: dateHead
                            Layout.preferredWidth: 130
                            horizontalAlignment: Text.AlignRight
                            text: picker.sort === "modified" ? "Modified ↓" : "Modified"
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
                            readonly property bool isMarked: !modelData.dir && picker.marked.indexOf(modelData.name) >= 0
                            readonly property color ink: isCurrent ? look.cursor.text : c.ink
                            readonly property color dim: isCurrent ? look.cursor.detail : c.muted
                            // The row as drawn, for the state function.
                            function drawn() {
                                return {
                                    name: nameText.text,
                                    dir: modelData.dir,
                                    size: sizeLabel.text,
                                    tag: tagLabel.visible ? tagLabel.text : "",
                                    marked: markLabel.visible,
                                    mark: markLabel.visible ? markLabel.text : "",
                                    // The name's colour and the one under it: the row's fill, or the card's where the row draws none.
                                    ink: String(nameText.color),
                                    behind: rowItem.color.a > 0 ? String(rowItem.color) : String(card.style.fill),
                                    modified: dateLabel.text,
                                    elided: nameText.truncated,
                                    lines: nameText.lineCount
                                };
                            }
                            width: rowList.width
                            height: 34
                            radius: look.cursor.radius
                            // Only the cursor row is filled; a marked row shows its mark and keeps the list's colours, as every board draws it.
                            color: isCurrent ? look.cursor.fill : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                // A folder or a page; a marked file shows a tick instead.
                                Item {
                                    implicitWidth: 16
                                    implicitHeight: 16

                                    Text {
                                        id: markLabel
                                        visible: rowItem.isMarked
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: "✓"
                                        color: rowItem.isCurrent ? look.cursor.text : c.ink
                                        font.family: fonts.ui
                                        font.pixelSize: 14
                                        font.bold: true
                                    }
                                    Rectangle {
                                        visible: !rowItem.isMarked
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
                                    font.family: fonts.ui
                                    font.pixelSize: 14
                                    font.weight: rowItem.modelData.dir || rowItem.isCurrent ? Font.Medium : Font.Normal
                                }
                                // The file a save would replace.
                                Text {
                                    id: tagLabel
                                    visible: picker.saving && !rowItem.modelData.dir && rowItem.modelData.name === picker.saveName
                                    textFormat: Text.PlainText
                                    text: "· exists"
                                    color: rowItem.isCurrent ? look.cursor.text : c.danger
                                    font.family: look.small.font
                                    font.pixelSize: look.small.size
                                    font.letterSpacing: look.small.spacing
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
                                    text: P.dateText(rowItem.modelData.mtime, Date.now())
                                    color: rowItem.dim
                                    font.family: fonts.mono
                                    font.pixelSize: 12
                                }
                            }

                            // A click selects the row, Shift and Ctrl mark; a double click does Enter on it. Qt's own double-click interval tells the two apart.
                            MouseArea {
                                objectName: "click:picker-row:" + rowItem.index
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => picker.clickRow(rowItem.index, {
                                    ctrl: (mouse.modifiers & Qt.ControlModifier) !== 0,
                                    shift: (mouse.modifiers & Qt.ShiftModifier) !== 0
                                })
                                onDoubleClicked: picker.openRow(rowItem.index)
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
                                text: P.completionHead(picker.choices.length, P.oneLine(picker.tilde(picker.split.parent)), P.oneLine(picker.split.tail))
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
                                    // The name, with the folder's path beside it.
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
                                            mark: completionItem.name.slice(0, picker.split.tail.length)
                                            rest: completionItem.name.slice(picker.split.tail.length)
                                            tint: completionItem.isCurrent ? look.cursor.text : c.ink
                                            family: fonts.mono
                                            size: 13
                                        }
                                        Text {
                                            id: completionDetail
                                            textFormat: Text.PlainText
                                            text: P.oneLine(picker.tilde((picker.split.parent === "/" ? "" : picker.split.parent) + "/" + completionItem.modelData.name))
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

                Item {
                    visible: !picker.saving && !picker.choosingFolder
                    Layout.fillHeight: true
                    implicitWidth: 1
                }

                // The cursor file: its picture when Qt decodes it, its name, then its meta lines; hidden while a path is typed, and gone in save mode.
                Item {
                    visible: !picker.saving && !picker.choosingFolder
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true

                    Column {
                        visible: picker.previewing
                        x: 18
                        y: 18
                        width: parent.width - 36
                        spacing: 8

                        // The badge sits on the picture's corner, or alone when Qt draws no picture.
                        Item {
                            width: parent.width
                            height: picker.preview ? previewImage.height : badgeBox.visible ? badgeBox.height : 0

                            Image {
                                id: previewImage
                                // Sized by hand: PreserveAspectFit makes Qt decode to fill the bound, scaling a small image up.
                                readonly property real fit: Math.min(1, parent.width / Math.max(1, implicitWidth), 186 / Math.max(1, implicitHeight))
                                width: implicitWidth * fit
                                height: implicitHeight * fit
                                asynchronous: true
                                cache: false
                                // A bound keeps a 12 MP photo from decoding whole; the dimensions line reads the header, not this.
                                sourceSize.width: 1024
                                sourceSize.height: 1024
                                source: picker.previewing ? "file://" + picker.cursorPath.split("/").map(encodeURIComponent).join("/") : ""
                            }
                            Rectangle {
                                id: badgeBox
                                visible: badgeLabel.text !== ""
                                x: picker.preview ? 8 : 0
                                y: picker.preview ? parent.height - height - 8 : 0
                                width: badgeLabel.implicitWidth + 14
                                height: badgeLabel.implicitHeight + 4
                                radius: 6
                                color: picker.preview ? c.paper : look.tile.fill

                                Text {
                                    id: badgeLabel
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: P.oneLine(picker.meta?.badge ?? "")
                                    color: c.ink
                                    font.family: fonts.ui
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }
                        }
                        // The name keeps its case.
                        Text {
                            id: previewName
                            width: parent.width
                            textFormat: Text.PlainText
                            text: picker.cursorRow ? P.oneLine(picker.cursorRow.name) : ""
                            maximumLineCount: 1
                            elide: Text.ElideMiddle
                            color: c.ink
                            font.family: fonts.ui
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }
                        // The values alone, one a line.
                        Repeater {
                            id: metaRepeater
                            model: picker.meta?.lines ?? []

                            Text {
                                id: metaValue
                                required property string modelData
                                function drawn() {
                                    return metaValue.text;
                                }
                                width: Math.min(implicitWidth, parent.width)
                                textFormat: Text.PlainText
                                text: modelData
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                color: c.muted
                                font.family: fonts.mono
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            Rule {}

            // How many files ctrl+Enter opens, or the folder it chooses, in the slot above the key strip.
            Text {
                id: footLabel
                visible: text !== "" && !picker.typingPath && !picker.saving
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 12
                textFormat: Text.PlainText
                text: P.oneLine(P.footText(picker.mode, picker.marked.length, picker.tilde(picker.folder)))
                maximumLineCount: 1
                elide: Text.ElideMiddle
                color: c.ink
                font.family: look.small.font
                font.pixelSize: look.small.size + 1
                font.letterSpacing: look.small.spacing
                font.bold: true
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                spacing: 8

                // The replace question or a refusal, in the error colour, in place of the strip.
                Text {
                    id: noticeLabel
                    visible: picker.notice !== ""
                    textFormat: Text.PlainText
                    text: P.oneLine(P.saveNotice(picker.notice, picker.saveName).say)
                    color: c.danger
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                    font.bold: true
                }

                Repeater {
                    id: keyRepeater
                    model: picker.notice !== "" ? P.saveNotice(picker.notice, picker.saveName).keys : picker.typingPath ? P.pathKeys() : P.pickerKeys(picker.mode, picker.multiple, picker.sort)

                    KeyPair {
                        id: keyPair
                        theme: picker.theme
                        look: picker.look
                    }
                }
            }
        }
    }

    // The 1 px slot between a card's parts; it draws no line, so the card reads as one piece.
    component Rule: Item {
        Layout.fillWidth: true
        implicitHeight: 1
    }

    // A name with its matched letters underlined, in three plain texts so a file's name never reads as markup; the end elides.
    component Marked: RowLayout {
        id: markedRow
        property string mark: ""
        property string rest: ""
        property color tint: c.ink
        property string family: fonts.ui
        property int size: 14
        property int weight: Font.Normal
        // As drawn, the underlined letters between <u> and </u>.
        function drawn() {
            return (markText.text !== "" && markText.font.underline ? "<u>" + markText.text + "</u>" : markText.text) + restText.text;
        }
        spacing: 0

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

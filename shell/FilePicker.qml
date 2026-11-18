import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as IT
import "lib/picker.mjs" as P
import "lib/files.mjs" as F

// The file picker any app's open dialog gets, drawn by the shell for bin/dots-portal inside the island as board 9: the asking app's header with the filter field, the places, the path as pills, 44 px rows, and Cancel beside Open N, Save or Choose this folder. It takes the island over whatever shows, loads on a request and unloads 30 s after it closes.
Item {
    id: picker

    required property var theme
    // The desktop entries, which name the asking app.
    required property var apps
    property bool shown: false
    property int opens: 0
    property var openMs: null
    // When the request line came in, or -1 once the picker's first frame is swapped.
    property real openT0: -1
    // The request from the Portal service, with its answer function, while it shows.
    property var request: null
    // The request as the picker draws it, kept after the answer while the island morphs away.
    property var seen: null
    // The surface this picker returns to, as its chip's words; the surfaces' window sets it.
    property string chip: ""
    // True once the island has come to rest on the picker; the surfaces' window sets it.
    property bool settled: false
    // The island reports this as its takeover while the picker shows, and grows to this width for it (board 9).
    readonly property string name: "picker"
    readonly property int wantWidth: 960
    // One height for every mode and listing, so the island holds still while rows land and the save line swaps.
    implicitHeight: 600
    readonly property string mode: seen?.mode ?? ""
    readonly property bool saving: mode === "save"
    readonly property bool multiple: seen?.multiple ?? false
    readonly property bool choosingFolder: mode === "folder"
    // The marked files' names; a folder change clears them, so a name is enough.
    property var marked: []
    readonly property var filters: seen?.filters ?? []
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
    readonly property bool preview: previewing && (previewLoader.item?.ready ?? false)
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
    // A request still unanswered or a listing still running keeps the picker loaded; it is not named busy, since the island reads a surface's busy as content still moving.
    readonly property bool pending: request !== null || lister.running

    readonly property string home: Quickshell.env("HOME")
    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, and the tones lifted to read on it.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? IT.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property string appText: P.oneLine(P.appName(apps, seen?.app ?? ""))
    readonly property string appIcon: P.appIcon(apps, seen?.app ?? "")
    // Board 9's places; the GTK bookmarks follow them, and drives are not places.
    readonly property var places: [
        { path: home, label: "Home", glyph: 0xF02DC },
        { path: home + "/Downloads", label: "Downloads", glyph: 0xF01DA },
        { path: home + "/Documents", label: "Documents", glyph: 0xF0219 },
        { path: home + "/Pictures", label: "Pictures", glyph: 0xF02E9 },
        { path: home + "/Codes", label: "Codes", glyph: 0xF0169 }
    ]
    // The footer's buttons: Keep and a red Replace while the replace question shows, else Cancel and the mode's inverted button.
    readonly property var buttonModel: asking ? [
        { text: "Keep", click: "picker-keep", inverted: false, red: false },
        { text: "Replace", click: "picker-replace", inverted: true, red: true }
    ] : [
        { text: "Cancel", click: "picker-cancel", inverted: false, red: false },
        { text: P.primaryText(mode, marked.length), click: "picker-primary", inverted: true, red: false }
    ]

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

    // Esc, Cancel or a click outside cancels, so the app never waits on a picker nobody sees.
    function close() {
        if (request)
            reply(P.answerLine(1, []));
    }

    // The app went away on its own, so there is nothing to answer; the island goes back to what it covered.
    function dismiss() {
        request = null;
        shown = false;
    }

    // A click outside does what Esc does, one level: the replace question, then the path field, then the request.
    function stepBack() {
        if (asking)
            keep();
        else if (typingPath)
            typingPath = false;
        else
            close();
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
        // The last folder's rows go with it, so no key acts on them here and nothing draws them.
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

    // Keep drops the question and leaves the name in its field; Replace answers it.
    function keep() {
        notice = "";
    }

    function replace() {
        notice = "";
        reply(P.answerLine(0, [pathOf({ name: saveName })]));
    }

    // The inverted button: Open answers the marked files or does Enter's work on the cursor row, Save saves, Choose this folder answers the folder shown.
    function primary() {
        if (saving)
            save();
        else if (!chooseAll())
            choose();
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

    // A footer button does what its words say; behind the path field Cancel still cancels and the rest wait, as the keys.
    function press(click) {
        if (click === "picker-keep")
            keep();
        else if (click === "picker-replace")
            replace();
        else if (click === "picker-cancel")
            close();
        else if (!typingPath)
            primary();
    }

    function tilde(path) {
        return path === home ? "~" : path.indexOf(home + "/") === 0 ? "~" + path.slice(home.length) : path;
    }

    // Where an item draws, in the picker's own coordinates.
    function box(item) {
        if (!item || !item.visible)
            return null;
        const p = item.mapToItem(picker, 0, 0);
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
        const pills = [];
        for (let i = 0; i < pillRepeater.count; i++)
            pills.push(pillRepeater.itemAt(i).text);
        const buttons = [];
        for (let i = 0; i < buttonRepeater.count; i++)
            buttons.push(buttonRepeater.itemAt(i).drawn());
        const pv = previewLoader.item ? previewLoader.item.drawn() : { shown: false, name: "", badge: "", font: ["", 0], lines: [] };
        const nameLabel = nameLoader.item?.label ?? null;
        return JSON.stringify({
            loaded: true,
            open: shown,
            mode: mode,
            app: appText,
            title: P.oneLine(seen?.title ?? ""),
            heading: headingLabel.text,
            headingTruncated: headingLabel.truncated,
            headingLines: headingLabel.lineCount,
            // The surface the picker returns to, as its header's chip draws it, or null over the resting island.
            chip: chipBox.visible ? chipLabel.text : null,
            appIcon: appImage.visible ? appImage.source.toString() : "",
            folder: folder,
            path: P.oneLine(tilde(folder)),
            pills: pills,
            sortText: sortLabel.text,
            count: countLabel.text,
            listed: listed,
            rows: drawn,
            selected: selected,
            places: shownPlaces,
            matches: lit,
            marked: marked,
            focus: saving && side === "list" && !typingPath && !asking ? "name" : side,
            saveField: !!nameLabel && nameLabel.visible,
            name: nameLabel ? nameLabel.text : "",
            question: asking && lineLabel.visible,
            notice: notice,
            line: lineLabel.visible ? lineLabel.text : "",
            typed: typedLabel.text,
            prompt: promptLabel.text,
            match: matchLabel.text,
            buttons: buttons,
            danger: String(tones.danger),
            accent: String(tones.accent),
            foot: footLabel.visible ? footLabel.text : "",
            cardSize: [picker.width, picker.height],
            boxes: {
                heading: box(headingLabel),
                query: box(typedLabel),
                match: box(matchLabel),
                chip: box(chipLabel),
                path: box(pillRow),
                count: box(countLabel)
            },
            hidden: hidden,
            sort: sort,
            pathMode: typingPath,
            completionHead: typingPath ? completionHeadLabel.text : "",
            completions: typingPath ? done : [],
            choice: choice,
            previewShown: pv.shown,
            preview: preview,
            previewName: pv.name,
            previewBadge: pv.badge,
            previewNameFont: pv.font,
            previewLines: pv.lines,
            previewDims: pv.lines.length > 0 && pv.lines[0].indexOf(" × ") > 0 ? pv.lines[0] : "",
            pending: pending,            openMs: openMs,
            opens: opens,
            settled: picker.settled,
            drawing: picker.visible,
            keyboard: keyTarget.activeFocus,
            width: picker.width
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

    // Up and Down move the cursor of the list, the places or the completions; letters type the query, the path or the name.
    Item {
        id: keyTarget
        Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            // The replace question takes only Enter, which replaces, and Esc, which keeps the file.
            if (picker.asking) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    picker.replace();
                else if (event.key === Qt.Key_Escape)
                    picker.keep();
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
            } else if (event.key === Qt.Key_Escape)
                picker.stepBack();
            else if (picker.typingPath) {
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

    // A press anywhere on the picker is on its card, so the surfaces' window never takes it for a click outside.
    Item {
        objectName: "card"
        anchors.fill: parent
    }

    ColumnLayout {
        x: 16
        y: 16
        width: parent.width - 32
        height: parent.height - 32
        spacing: 0

        // The asking app's circle, what it wants, the surface it returns to, and the filter field.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 12

            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: 18
                color: Qt.alpha(picker.on, 0.12)

                Image {
                    id: appImage
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    visible: picker.appIcon !== "" && status === Image.Ready
                    source: picker.appIcon
                    sourceSize.width: 44
                    sourceSize.height: 44
                    asynchronous: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: !appImage.visible
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(0xF024B)
                    color: picker.on
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 17
                }
            }

            Text {
                id: headingLabel
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: P.headingText(picker.appText, picker.mode)
                maximumLineCount: 1
                elide: Text.ElideRight
                color: picker.on
                font.family: picker.fonts.ui ?? ""
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            // The surface under the picker, which comes back once it is answered.
            Rectangle {
                id: chipBox
                visible: picker.chip !== ""
                implicitWidth: chipLabel.implicitWidth + 16
                implicitHeight: 22
                radius: 11
                color: Qt.alpha(picker.on, 0.08)

                Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: picker.chip
                    color: picker.tones.muted
                    font.family: picker.fonts.ui ?? ""
                    font.pixelSize: 11
                }
            }

            // The query, or the path after ctrl+l; a save types its name in the footer, so its field shows only for a path.
            Rectangle {
                visible: !picker.saving || picker.typingPath
                implicitWidth: 300
                implicitHeight: 36
                radius: 10
                color: Qt.alpha(picker.on, 0.08)
                border.width: picker.typingPath ? 1 : 0
                border.color: picker.tones.accent

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        id: promptLabel
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: picker.typingPath ? "path" : ""
                        color: picker.tones.muted
                        font.family: picker.fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: typedLabel.implicitHeight

                        Text {
                            id: typedLabel
                            width: parent.width
                            textFormat: Text.PlainText
                            text: picker.typingPath ? P.oneLine(picker.typed) : P.oneLine(picker.query)
                            maximumLineCount: 1
                            elide: Text.ElideLeft
                            color: picker.on
                            font.family: picker.typingPath ? picker.fonts.mono ?? "" : picker.fonts.ui ?? ""
                            font.pixelSize: 13
                        }
                        Text {
                            visible: typedLabel.text === ""
                            textFormat: Text.PlainText
                            text: "Filter"
                            color: picker.tones.muted
                            font.family: picker.fonts.ui ?? ""
                            font.pixelSize: 13
                        }
                    }
                    Text {
                        id: matchLabel
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: picker.typingPath ? P.matchText("path", picker.choices.length, "") : picker.matches.length > 0 ? P.matchText("places", picker.matches.length, P.oneLine(picker.allPlaces[picker.matches[0].index].label)) : ""
                        color: picker.tones.muted
                        font.family: picker.fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 14
            spacing: 12

            // Home, Downloads, Documents, Pictures and Codes, then the GTK bookmarks.
            Column {
                Layout.preferredWidth: 180
                Layout.fillHeight: true
                spacing: 2

                Repeater {
                    id: placeRepeater
                    model: picker.allPlaces

                    Rectangle {
                        id: placeItem
                        required property var modelData
                        required property int index
                        readonly property bool here: modelData.path === picker.folder
                        readonly property var hit: picker.matches.find(m => m.index === index) ?? null
                        readonly property bool atCursor: picker.side === "places" && picker.placeAt === index
                        readonly property bool lit: hit !== null || (here && picker.matches.length === 0)
                        readonly property string label: P.oneLine(modelData.label)
                        readonly property int marks: hit ? hit.length : 0
                        function drawn() {
                            return labelText.drawn();
                        }
                        width: 180
                        height: 34
                        radius: 10
                        color: placeItem.atCursor ? Qt.alpha(picker.on, 0.14) : placeItem.here ? Qt.alpha(picker.on, 0.07) : "transparent"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            width: parent.width - 20
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                textFormat: Text.PlainText
                                // The bookmarks after the five places draw a bookmark.
                                text: String.fromCodePoint(placeItem.modelData.glyph ?? 0xF00C0)
                                color: placeItem.lit ? picker.on : picker.tones.muted
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 14
                            }
                            Marked {
                                id: labelText
                                width: parent.width - 26
                                anchors.verticalCenter: parent.verticalCenter
                                mark: placeItem.label.slice(0, placeItem.marks)
                                rest: placeItem.label.slice(placeItem.marks)
                                tint: placeItem.lit || placeItem.atCursor ? picker.on : picker.tones.muted
                                weight: placeItem.here ? Font.Bold : Font.Normal
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

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // The folder as pills, then how many rows it holds and the sort, on the right.
                RowLayout {
                    Layout.fillWidth: true
                    // A layout fills by default, which would split the height with the rows.
                    Layout.fillHeight: false
                    Layout.preferredHeight: 28
                    spacing: 10

                    // A deep path keeps its last pills in view.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Row {
                            id: pillRow
                            x: Math.min(0, parent.width - width)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Repeater {
                                id: pillRepeater
                                model: P.pathPills(picker.folder, picker.home)

                                Rectangle {
                                    id: pill
                                    required property var modelData
                                    required property int index
                                    readonly property bool last: index === pillRepeater.count - 1
                                    readonly property string text: pillText.text
                                    implicitWidth: pillText.implicitWidth + 20
                                    implicitHeight: 26
                                    radius: 13
                                    color: Qt.alpha(picker.on, last ? 0.14 : 0.07)

                                    Text {
                                        id: pillText
                                        anchors.centerIn: parent
                                        width: Math.min(implicitWidth, 220)
                                        textFormat: Text.PlainText
                                        text: P.oneLine(pill.modelData.label)
                                        maximumLineCount: 1
                                        elide: Text.ElideMiddle
                                        color: pill.last ? picker.on : picker.tones.muted
                                        font.family: picker.fonts.ui ?? ""
                                        font.pixelSize: 12
                                        font.weight: pill.last ? Font.Bold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        id: countLabel
                        textFormat: Text.PlainText
                        text: picker.typingPath ? "typing a path" : P.countText(picker.rows.length, picker.filterName, picker.hidden, picker.mode)
                        color: picker.tones.muted
                        font.family: picker.fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                    Text {
                        id: sortLabel
                        textFormat: Text.PlainText
                        text: P.sortText(picker.sort)
                        color: picker.on
                        font.family: picker.fonts.ui ?? ""
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // The rows: folders first, each with its size or item count and when it changed.
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
                                // The row as drawn, for the state function.
                                function drawn() {
                                    return {
                                        name: nameText.text,
                                        dir: modelData.dir,
                                        size: sizeLabel.text,
                                        tag: tagLabel.visible ? tagLabel.text : "",
                                        marked: markBox.visible,
                                        mark: markBox.visible ? markLabel.text : "",
                                        icon: String(typeIcon.color),
                                        bold: nameText.font.weight >= Font.Bold,
                                        // The name's colour and the one under it: the row's fill, or the island's where the row draws none.
                                        ink: String(nameText.color),
                                        behind: rowItem.color.a > 0 ? String(rowItem.color) : String(picker.fill),
                                        modified: dateLabel.text,
                                        elided: nameText.truncated,
                                        lines: nameText.lineCount,
                                        h: rowItem.height
                                    };
                                }
                                width: rowList.width
                                height: 44
                                radius: 12
                                color: isCurrent ? Qt.alpha(picker.on, 0.12) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    // A round mark on a picked file.
                                    Item {
                                        implicitWidth: 18
                                        implicitHeight: 18

                                        Rectangle {
                                            id: markBox
                                            visible: rowItem.isMarked
                                            anchors.fill: parent
                                            radius: 9
                                            color: picker.on

                                            Text {
                                                id: markLabel
                                                anchors.centerIn: parent
                                                textFormat: Text.PlainText
                                                text: "✓"
                                                color: picker.fill
                                                font.family: picker.fonts.ui ?? ""
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                        }
                                    }
                                    // A folder in the accent, or a page.
                                    Text {
                                        id: typeIcon
                                        Layout.preferredWidth: 18
                                        textFormat: Text.PlainText
                                        text: String.fromCodePoint(rowItem.modelData.dir ? 0xF024B : 0xF0214)
                                        color: rowItem.modelData.dir ? picker.tones.accent : picker.tones.muted
                                        font.family: "Symbols Nerd Font Mono"
                                        font.pixelSize: 16
                                    }
                                    Text {
                                        id: nameText
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: P.oneLine(rowItem.modelData.name) + (rowItem.modelData.dir ? "/" : "")
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                        color: picker.on
                                        font.family: picker.fonts.ui ?? ""
                                        font.pixelSize: 13
                                        font.weight: rowItem.modelData.dir ? Font.Bold : Font.Normal
                                    }
                                    // The file a save would replace.
                                    Text {
                                        id: tagLabel
                                        visible: picker.saving && !rowItem.modelData.dir && rowItem.modelData.name === picker.saveName
                                        textFormat: Text.PlainText
                                        text: "· exists"
                                        color: picker.tones.danger
                                        font.family: picker.fonts.ui ?? ""
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        id: sizeLabel
                                        Layout.preferredWidth: 72
                                        horizontalAlignment: Text.AlignRight
                                        textFormat: Text.PlainText
                                        text: P.sizeText(rowItem.modelData)
                                        color: picker.tones.muted
                                        font.family: picker.fonts.ui ?? ""
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        id: dateLabel
                                        Layout.preferredWidth: 84
                                        horizontalAlignment: Text.AlignRight
                                        textFormat: Text.PlainText
                                        text: P.dateText(rowItem.modelData.mtime, Date.now())
                                        color: picker.tones.muted
                                        font.family: picker.fonts.ui ?? ""
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
                            radius: 12
                            color: picker.fill
                            border.width: 1
                            border.color: Qt.alpha(picker.on, 0.16)
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
                                    color: picker.tones.muted
                                    font.family: picker.fonts.ui ?? ""
                                    font.pixelSize: 12
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
                                        radius: 10
                                        color: isCurrent ? Qt.alpha(picker.on, 0.12) : "transparent"

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
                                                family: picker.fonts.mono ?? ""
                                            }
                                            Text {
                                                id: completionDetail
                                                textFormat: Text.PlainText
                                                text: P.oneLine(picker.tilde((picker.split.parent === "/" ? "" : picker.split.parent) + "/" + completionItem.modelData.name))
                                                Layout.maximumWidth: 280
                                                maximumLineCount: 1
                                                elide: Text.ElideMiddle
                                                color: picker.tones.muted
                                                font.family: picker.fonts.mono ?? ""
                                                font.pixelSize: 12
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The cursor file, beside the rows, in open mode only: its picture when Qt decodes it, its name, then its meta lines.
                    Loader {
                        id: previewLoader
                        active: picker.mode === "open"
                        visible: active
                        Layout.preferredWidth: 200
                        Layout.fillHeight: true
                        sourceComponent: Preview {}
                    }
                }
            }
        }

        // The count and the buttons; a save puts its name field here, and the replace question beside it.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.topMargin: 14
            spacing: 8

            Loader {
                id: nameLoader
                active: picker.saving
                visible: active
                Layout.preferredWidth: 360
                Layout.preferredHeight: 36
                sourceComponent: NameField {}
            }
            Text {
                id: footLabel
                visible: text !== "" && !picker.saving
                textFormat: Text.PlainText
                text: P.footText(picker.mode, picker.marked.length)
                color: picker.on
                font.family: picker.fonts.ui ?? ""
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            // The replace question, or why the name was refused, in the danger tone.
            Text {
                id: lineLabel
                visible: picker.notice !== ""
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: P.oneLine(P.saveNotice(picker.notice, picker.saveName))
                maximumLineCount: 1
                elide: Text.ElideMiddle
                color: picker.tones.danger
                font.family: picker.fonts.ui ?? ""
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            Item {
                visible: !lineLabel.visible
                Layout.fillWidth: true
            }
            Repeater {
                id: buttonRepeater
                model: picker.buttonModel

                PickerButton {}
            }
        }
    }

    // A quiet button is a faint fill with the island's text; the primary is inverted, the island's text as its fill, and Replace takes the danger tone for its fill.
    component PickerButton: Rectangle {
        id: button
        required property var modelData
        function drawn() {
            return {
                text: buttonLabel.text,
                inverted: button.modelData.inverted,
                fill: String(button.color),
                ink: String(buttonLabel.color)
            };
        }
        implicitWidth: buttonLabel.implicitWidth + 28
        implicitHeight: 34
        radius: 10
        color: modelData.red ? picker.tones.danger : modelData.inverted ? picker.on : Qt.alpha(picker.on, 0.1)

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: button.modelData.text
            color: button.modelData.inverted ? picker.fill : picker.on
            font.family: picker.fonts.ui ?? ""
            font.pixelSize: 13
            font.weight: Font.Bold
        }
        Root.Click {
            name: button.modelData.click
            onTapped: picker.press(button.modelData.click)
        }
    }

    // The save name as typed, with a caret at its end while the keys type into it.
    component NameField: Rectangle {
        readonly property alias label: nameText
        radius: 10
        color: Qt.alpha(picker.on, 0.08)
        border.width: picker.side === "list" && !picker.typingPath && !picker.asking ? 1 : 0
        border.color: picker.tones.accent

        Text {
            id: nameText
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            width: Math.min(implicitWidth, parent.width - 26)
            textFormat: Text.PlainText
            // The save name is stripped as it is typed and drawn as is, so a space typed last still shows.
            text: picker.saveName
            maximumLineCount: 1
            elide: Text.ElideLeft
            color: picker.on
            font.family: picker.fonts.ui ?? ""
            font.pixelSize: 13
        }
        Rectangle {
            visible: parent.border.width > 0
            x: nameText.x + nameText.width + 1
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 16
            color: picker.on
        }
        Text {
            visible: picker.saveName === ""
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            textFormat: Text.PlainText
            text: "Name"
            color: picker.tones.muted
            font.family: picker.fonts.ui ?? ""
            font.pixelSize: 13
        }
    }

    component Preview: Item {
        readonly property bool ready: previewImage.status === Image.Ready
        // The preview as drawn, for the state function.
        function drawn() {
            const lines = [];
            for (let i = 0; i < metaRepeater.count; i++)
                lines.push(metaRepeater.itemAt(i).text);
            return {
                shown: previewName.visible,
                name: previewName.text,
                badge: badgeBox.visible ? badgeLabel.text : "",
                font: [previewName.font.family, previewName.font.pixelSize],
                lines: lines
            };
        }

        Column {
            visible: picker.previewing
            width: parent.width
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
                    source: picker.previewing && P.isPicture(picker.cursorRow.name) ? "file://" + picker.cursorPath.split("/").map(encodeURIComponent).join("/") : ""
                }
                Rectangle {
                    id: badgeBox
                    visible: badgeLabel.text !== ""
                    x: picker.preview ? 8 : 0
                    y: picker.preview ? parent.height - height - 8 : 0
                    width: badgeLabel.implicitWidth + 14
                    height: badgeLabel.implicitHeight + 4
                    radius: 6
                    color: picker.preview ? picker.fill : Qt.alpha(picker.on, 0.12)

                    Text {
                        id: badgeLabel
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: P.oneLine(picker.meta?.badge ?? "")
                        color: picker.on
                        font.family: picker.fonts.ui ?? ""
                        font.pixelSize: 11
                        font.weight: Font.Bold
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
                color: picker.on
                font.family: picker.fonts.ui ?? ""
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            // The values alone, one a line.
            Repeater {
                id: metaRepeater
                model: picker.meta?.lines ?? []

                Text {
                    required property string modelData
                    width: Math.min(implicitWidth, parent.width)
                    textFormat: Text.PlainText
                    text: modelData
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: picker.tones.muted
                    font.family: picker.fonts.ui ?? ""
                    font.pixelSize: 12
                }
            }
        }
    }

    // A name with its matched letters underlined, in three plain texts so a file's name never reads as markup; the end elides.
    component Marked: RowLayout {
        id: markedRow
        property string mark: ""
        property string rest: ""
        property color tint: picker.on
        property string family: picker.fonts.ui ?? ""
        property int size: 13
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
}

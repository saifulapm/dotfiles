//@ pragma AppId files
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "services" as Services
import "lib/files.mjs" as F
import "lib/picker.mjs" as P
import "lib/status.mjs" as Status
import "lib/voice.mjs" as L

// Files, an App: its own qs process started by bin/dots-files, a normal window in the shell's theme; the process ends with its window.
ShellRoot {
    id: app

    readonly property string home: Quickshell.env("HOME")
    property string folder: home
    // Process start to the window's first frame, set once.
    property var firstFrameMs: null
    property var entries: []
    property bool hidden: false
    // / starts a find: typed letters narrow the rows, or open the one place they start (#NYNGZ3NC).
    property bool finding: false
    property string query: ""
    // z jumps through zoxide: the typed words, the folder zoxide ranks first for them, and the words that answer is for.
    property bool jumping: false
    property string jumpQuery: ""
    property string jumpTo: ""
    property string jumpFor: ""
    // An Enter typed before zoxide answered the last words jumps once it does.
    property bool jumpGo: false
    // The cursor file's width and height, read from its header off the render loop.
    property var dims: ({
            path: "",
            width: 0,
            height: 0
        })
    property bool sizeStale: false
    // r turns the cursor row's name into a field; d and a ask in the bar above the keys.
    property bool renaming: false
    // The rename field's selection, for checks.
    property string renameSelected: ""
    property string asking: ""
    property var trashPaths: []
    // Why the last rename, folder or trash failed, on the status line until the next key.
    property string notice: ""
    // The mounted drives, and their drawn rows, which each drive's PlaceRow adds itself to for state().
    property FilesDrives drivesWatch: FilesDrives {
        voice: app.voice
        // A drive that would not eject stays listed, and the status line says why.
        onErrorChanged: if (error)
            app.notice = app.voice === "bracket" ? "! " + error.toUpperCase() : error
    }
    property var driveRows: []
    // y or x: what p pastes, and whether it copies or moves; the sources are named as they were yanked.
    property var yank: null
    // A drag from any app hovering the listing: the files it carries and the folder row under it, or -1 for the folder shown.
    property bool dropping: false
    property var dropPaths: []
    property int dropAt: -1
    readonly property string dropTarget: dropAt >= 0 && rows[dropAt] ? pathOf(rows[dropAt]) : folder
    property FilesOps ops: FilesOps {
        onEnded: last => app.opEnded(last)
    }
    readonly property var opFail: ops.failed ? F.failText(voice, {
            mode: ops.mode,
            to: ops.to,
            items: ops.items,
            failed: ops.failed
        }) : null
    // What a drag out carries: the rows, their paths, and the chip's image grabbed as it starts.
    property var dragRows: []
    readonly property var dragPaths: dragRows.map(r => pathOf(r))
    property url chipUrl: ""
    property bool dragging: false
    // False from leaving a folder until its rows are listed, so no key acts on the last folder's rows.
    property bool listed: false
    // A folder changed while it was being listed is listed again.
    property bool stale: false
    // The row the cursor lands on once the folder is listed: the folder just left, after h.
    property string landOn: ""
    property int selected: 0
    property var marked: []
    // Keys typed before the folder's rows landed, played on them once they do.
    property var held: []
    // A g waits for a second one: gg goes to the first row, as yazi's does.
    property bool gHeld: false
    // list or places: which pane j, k and Enter move in.
    property string side: "list"
    property int placeAt: 0
    property var pins: []

    readonly property var rows: P.shownRows(entries, {
        hidden: hidden,
        query: query
    })
    readonly property var cursorRow: rows[selected] ?? null
    readonly property string cursorPath: cursorRow && !cursorRow.dir ? pathOf(cursorRow) : ""
    readonly property bool cursorImage: cursorPath !== "" && String(cursorRow.mime || "").indexOf("image/") === 0
    readonly property var fixedPlaces: F.places(home).map(p => Object.assign({ group: "places" }, p))
    readonly property var trash: ({
            label: "Trash",
            path: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/Trash/files",
            group: "trash"
        })
    // Trash is drawn apart, at the foot of the column, and is last for the keys too.
    readonly property var allPlaces: fixedPlaces.concat(pins.map(p => ({
                label: p.label,
                path: p.path,
                group: "pinned"
            }))).concat(drivesWatch.drives).concat([trash])
    readonly property var status: F.statusText(voice, rows, marked, selected)
    // A stopped copy, then a drop, then a notice, then a drag, else the counts: what the status line says.
    readonly property var statusShown: ops.failed ? F.stoppedText(voice, ops.to, ops.copied.length, ops.items.length) : dropping ? F.dropText(voice, dropPaths, placeName(dropTarget)) : notice ? {
        counts: notice,
        at: status.at
    } : dragging ? F.dragText(voice, dragRows) : status

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property string voice: look.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property var head: F.headText(voice, home, folder)
    readonly property var boardLook: F.filesLook(voice)
    readonly property int markWidth: boardLook.mark === "bracket" ? 22 : boardLook.mark === "circle" ? 16 : 14
    // Paper tints the current place and the marked rows a shade off its surface; its paper token is that shade.
    readonly property color hereFill: plain ? look.cursor.fill : bracket ? Qt.alpha(c.accent ?? "red", 0.1) : c.paper ?? "white"

    function face(kind) {
        return (kind === "display" ? fonts.display : kind === "mono" ? fonts.mono : fonts.ui) ?? "";
    }

    // qs has no quit, so a child ends its parent: the process must not outlive the window.
    function quit() {
        ender.running = true;
    }

    function pathOf(row) {
        return (folder === "/" ? "" : folder) + "/" + row.name;
    }

    function enter(path) {
        finding = false;
        query = "";
        folder = path;
        marked = [];
        selected = 0;
        landOn = "";
        entries = [];
        listed = false;
        list();
        // Each folder opened ranks it in zoxide, as yazi's do.
        Quickshell.execDetached(["zoxide", "add", "--", path]);
    }

    function up() {
        if (folder === "/")
            return;
        const left = folder.slice(folder.lastIndexOf("/") + 1);
        enter(folder.slice(0, folder.lastIndexOf("/")) || "/");
        landOn = left;
    }

    function list() {
        // A relist of the same folder, after a paste or a trash, keeps the cursor on its row.
        if (!landOn && cursorRow)
            landOn = cursorRow.name;
        if (lister.running) {
            stale = true;
            return;
        }
        lister.command = ["python3", "-c", P.LIST_SCRIPT, folder];
        lister.running = true;
    }

    function move(by) {
        if (side === "places")
            placeAt = Math.max(0, Math.min(allPlaces.length - 1, placeAt + by));
        else
            selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }

    // l or Enter: into a folder, or the file opens in its default app.
    function choose() {
        if (side === "places") {
            side = "list";
            if (allPlaces[placeAt].path !== folder)
                enter(allPlaces[placeAt].path);
            return;
        }
        if (!cursorRow)
            return;
        if (cursorRow.dir)
            enter(pathOf(cursorRow));
        else if (!cursorRow.undecodable)
            Quickshell.execDetached(["gio", "open", pathOf(cursorRow)]);
    }

    function setQuery(q) {
        query = q;
        selected = 0;
        const at = F.findPlace(fixedPlaces.concat(pins), q);
        if (at < 0)
            return;
        // A find that names the folder already shown has found it: it ends, rather than narrowing to nothing.
        if (allPlaces[at].path === folder) {
            finding = false;
            query = "";
        } else
            enter(allPlaces[at].path);
    }

    function startJump() {
        jumping = true;
        jumpGo = false;
        setJump("");
    }

    function setJump(q) {
        jumpQuery = q;
        lookup();
    }

    // One zoxide query at a time; words typed during it are asked for once it ends.
    function lookup() {
        const words = F.jumpWords(jumpQuery);
        if (!words.length) {
            jumpTo = "";
            jumpFor = jumpQuery;
            return;
        }
        if (jumper.running)
            return;
        jumper.asked = jumpQuery;
        jumper.command = ["zoxide", "query", "--exclude", folder, "--"].concat(words);
        jumper.running = true;
    }

    // Enter: into the folder the words go to; with none, the bar stays for more words.
    function jump() {
        if (jumpFor !== jumpQuery) {
            jumpGo = true;
            return;
        }
        jumpGo = false;
        if (!jumpTo)
            return;
        jumping = false;
        enter(jumpTo);
    }

    // One header read at a time; a cursor that moved on during it asks again for the file it rests on.
    function measure() {
        if (sizer.running) {
            sizeStale = true;
            return;
        }
        if (!cursorImage || dims.path === cursorPath)
            return;
        sizer.asked = cursorPath;
        sizer.command = ["python3", "-c", P.SIZE_SCRIPT, cursorPath];
        sizer.running = true;
    }

    function startRename() {
        if (!listed || !cursorRow || cursorRow.undecodable)
            return;
        renaming = true;
    }

    function finishRename(name) {
        renaming = false;
        if (name === cursorRow.name)
            return;
        const why = F.nameProblem(name, entries);
        if (why) {
            notice = F.noticeText(voice, why, name);
            return;
        }
        doer.land = name;
        doer.command = ["python3", "-c", F.RENAME_SCRIPT, pathOf(cursorRow), pathOf({
                name: name
            })];
        doer.running = true;
    }

    function startTrash() {
        trashPaths = F.targets(rows, marked, folder, cursorRow);
        if (listed && trashPaths.length)
            asking = "trash";
    }

    function doTrash() {
        asking = "";
        doer.land = "";
        doer.command = ["trash-put", "--"].concat(trashPaths);
        doer.running = true;
        marked = [];
    }

    function finishMkdir(name) {
        asking = "";
        const why = F.nameProblem(name, entries);
        if (why) {
            notice = F.noticeText(voice, why, name);
            return;
        }
        doer.land = name;
        doer.command = ["mkdir", "--", pathOf({
                name: name
            })];
        doer.running = true;
    }

    // y and x remember the targets with their sizes, for the progress and the failure card.
    function yankTargets(how) {
        const paths = F.targets(rows, marked, folder, cursorRow);
        if (!listed || !paths.length)
            return;
        yank = {
            mode: how,
            from: folder,
            items: rows.filter(r => paths.indexOf(pathOf(r)) >= 0).map(r => ({
                        path: pathOf(r),
                        name: r.name,
                        size: r.size,
                        dir: r.dir
                    }))
        };
    }

    // A drive's label names a target inside it, as the failure board's "T7 Shield is full" does.
    function placeName(path) {
        const drive = drivesWatch.drives.find(d => path === d.path || path.indexOf(d.path + "/") === 0);
        return drive ? drive.label : F.folderName(home, path);
    }

    // A drop always copies, into the folder row under it or the folder shown; Files' own drag only onto another folder.
    function dropInto(paths, own) {
        const target = dropTarget;
        dropping = false;
        dropAt = -1;
        if (own && target === folder)
            return false;
        if (ops.running) {
            notice = F.noticeText(voice, "busy", "");
            return false;
        }
        return ops.start("copy", paths.map(p => ({
                    path: p,
                    name: p.slice(p.lastIndexOf("/") + 1),
                    size: null,
                    dir: false
                })), paths[0].slice(0, paths[0].lastIndexOf("/")) || "/", target, placeName(target));
    }

    function hoverDrop(y) {
        const i = rowList.indexAt(10, y + rowList.contentY);
        dropAt = i >= 0 && rows[i].dir ? i : -1;
    }

    function paste() {
        if (!yank || !listed)
            return;
        if (ops.running) {
            notice = F.noticeText(voice, "busy", "");
            return;
        }
        ops.start(yank.mode, yank.items, yank.from, folder, placeName(folder));
    }

    function opEnded(last) {
        if (last && last.event === "refused")
            notice = F.noticeText(voice, last.why === "into-itself" ? "itself" : "missing", last.src.slice(last.src.lastIndexOf("/") + 1));
        else if (last && last.event === "cancelled" && last.copied.length < ops.items.length && last.copied.length > 0) {
            const t = F.stoppedText(voice, ops.to, last.copied.length, ops.items.length);
            notice = t.counts + " · " + t.at;
        }
        if (last && last.event === "done" && ops.mode === "move")
            yank = null;
        if (folder === ops.target || folder === ops.from)
            list();
    }

    // Space marks the cursor row and steps down, as yazi's does.
    function mark() {
        marked = F.toggleMark(marked, cursorRow);
        move(1);
    }

    function toSide() {
        if (side === "places") {
            side = "list";
            return;
        }
        const here = allPlaces.findIndex(p => p.path === folder);
        placeAt = here >= 0 ? here : 0;
        side = "places";
    }

    // The keys that act on the listed rows; before they land, they wait for them.
    function rowKey(k) {
        if (side === "list" && !listed) {
            held = held.concat([k]);
            return;
        }
        if (k === "down")
            move(1);
        else if (k === "up")
            move(-1);
        else if (k === "top")
            move(-Infinity);
        else if (k === "bottom")
            move(Infinity);
        else if (k === "in")
            choose();
        else if (k === "out")
            up();
        else if (k === "mark")
            mark();
        // The other keys act on the rows, never on what the places' cursor rests on.
        else if (side !== "list")
            return;
        else if (k === "r")
            startRename();
        else if (k === "d")
            startTrash();
        else if (k === "a")
            asking = "mkdir";
        else if (k === "o")
            openWith.show(F.targets(rows, marked, folder, cursorRow));
        else if (k === "s") {
            const set = F.shareSet(rows, marked, folder, cursorRow);
            share.show(set.paths, set.bytes);
        } else if (k === "y")
            yankTargets("copy");
        else if (k === "x")
            yankTargets("move");
        else if (k === "p")
            paste();
    }

    // A press on a row readies its drag: the rows it carries and the chip that will follow the pointer.
    function pressRow(row) {
        const paths = F.dragPaths(rows, marked, folder, row);
        dragRows = rows.filter(r => paths.indexOf(pathOf(r)) >= 0);
        dragChip.grabToImage(r => app.chipUrl = r.url);
    }

    // The cursor row as drawn, for checks that read the window rather than the data.
    function drawnCursor() {
        const item = rowList.itemAtIndex(selected);
        return item ? item.drawn() : null;
    }

    onRowsChanged: if (selected >= rows.length)
        selected = Math.max(0, rows.length - 1)
    onCursorPathChanged: measure()
    // A drive that leaves while the cursor is on the last places would leave it past the end.
    onAllPlacesChanged: if (placeAt >= allPlaces.length)
        placeAt = allPlaces.length - 1
    onAskingChanged: if (asking === "mkdir") {
        mkdirField.text = "";
        mkdirField.forceActiveFocus();
    }

    Component.onCompleted: list()

    Services.Theme {
        id: theme
    }

    Process {
        id: ender
        // Its children first: qs dies on SIGTERM without ending them, which would leave the drives watch, or a copy (which then removes its partial file), running on.
        command: ["sh", "-c", "for p in $(pgrep -P $PPID); do [ \"$p\" = $$ ] || kill -TERM \"$p\"; done; kill -TERM $PPID"]
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() {
            app.quit();
        }
    }

    // The folder's entries, listed off the render loop.
    Process {
        id: lister
        stdout: StdioCollector {
            id: listOut
        }
        onExited: code => {
            if (app.stale) {
                app.stale = false;
                Qt.callLater(app.list);
                return;
            }
            // A folder that cannot be read lists as empty, and says why.
            if (code !== 0)
                app.notice = F.noticeText(app.voice, "unreadable", F.folderName(app.home, app.folder));
            let found = [];
            try {
                found = JSON.parse(listOut.text);
            } catch (e) {
                found = [];
            }
            app.entries = Array.isArray(found) ? found : [];
            const back = app.rows.findIndex(r => r.name === app.landOn);
            app.selected = back >= 0 ? back : 0;
            app.listed = true;
            // An l here that opened a folder holds the keys after it again, for that folder's rows.
            const keys = app.held;
            app.held = [];
            for (const k of keys)
                app.rowKey(k);
        }
    }

    Process {
        id: sizer
        property string asked: ""
        stdout: StdioCollector {
            id: sizeOut
        }
        onExited: {
            if (app.sizeStale) {
                app.sizeStale = false;
                Qt.callLater(app.measure);
                return;
            }
            const wh = sizeOut.text.trim().split(" ").map(Number);
            app.dims = {
                path: asked,
                width: wh.length === 2 && wh[0] > 0 ? wh[0] : 0,
                height: wh.length === 2 && wh[1] > 0 ? wh[1] : 0
            };
            Qt.callLater(app.measure);
        }
    }

    Process {
        id: jumper
        property string asked: ""
        stdout: StdioCollector {
            id: jumpOut
        }
        onExited: code => {
            if (!app.jumping)
                return;
            if (asked !== app.jumpQuery) {
                Qt.callLater(app.lookup);
                return;
            }
            // zoxide exits 1 when no folder matches.
            app.jumpTo = code === 0 ? jumpOut.text.trim() : "";
            app.jumpFor = asked;
            if (app.jumpGo)
                app.jump();
        }
    }

    // A rename, a new folder or a trash, then the folder listed again with the cursor on what it made.
    Process {
        id: doer
        property string land: ""
        stderr: StdioCollector {
            id: doerErr
        }
        onExited: code => {
            if (code !== 0)
                app.notice = app.voice === "bracket" ? "! " + P.oneLine(doerErr.text).toUpperCase() : P.oneLine(doerErr.text) || F.noticeText(app.voice, "failed", "");
            // The name it made may not match the find, which would hide it.
            app.query = "";
            app.landOn = land;
            app.list();
        }
    }

    FileView {
        id: bookmarksFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || app.home + "/.config") + "/gtk-3.0/bookmarks"
        printErrors: false
        onLoaded: app.pins = P.parseBookmarks(text())
        onLoadFailed: app.pins = []
    }

    FileView {
        id: uptime
        path: "/proc/uptime"
        blockAllReads: true
    }

    FileView {
        id: selfStat
        path: "/proc/self/stat"
        blockLoading: true
    }

    // Read at call time; blockAllReads, or text() after reload() is the previous call's RSS.
    FileView {
        id: procStatus
        path: "/proc/self/status"
        blockAllReads: true
    }

    IpcHandler {
        target: "files"

        function state(): string {
            procStatus.reload();
            return JSON.stringify({
                folder: app.folder,
                title: win.title,
                head: app.head,
                voice: app.voice,
                firstFrameMs: app.firstFrameMs,
                rssKiB: Status.rssKiB(procStatus.text()),
                listed: app.listed,
                openWith: openWith.state(),
                side: app.side,
                selected: app.selected,
                cursor: app.cursorRow ? app.cursorRow.name : null,
                rows: app.rows.map(r => r.name),
                dirs: app.rows.filter(r => r.dir).map(r => r.name),
                marked: app.marked,
                share: share.state(),
                places: app.allPlaces.map(p => p.group + ":" + p.label),
                placeAt: app.placeAt,
                op: {
                    running: app.ops.running,
                    dropping: app.dropping,
                    dropAt: app.dropAt >= 0 && app.rows[app.dropAt] ? app.rows[app.dropAt].name : null,
                    yank: app.yank ? app.yank.mode + " " + app.yank.items.length : "",
                    say: opSay.text,
                    progress: opProgress.text,
                    keys: opKeys.text,
                    shown: opSay.visible,
                    card: failCard.visible ? failCard.drawn() : null
                },
                drives: app.driveRows.slice().sort((a, b) => a.at - b.at).map(r => r.drawn()),
                driveError: app.drivesWatch.error,
                path: pathLead.text + pathName.text,
                pathParts: {
                    icon: pathIcon.path,
                    lead: pathLead.text,
                    leadColor: String(pathLead.color),
                    name: pathName.text,
                    nameWeight: pathName.font.weight
                },
                width: win.width,
                strip: stripRepeater.count ? stripRepeater.itemAt(0).drawn() : null,
                count: countLabel.text,
                finding: app.finding,
                query: app.query,
                jumping: app.jumping,
                hidden: app.hidden,
                renaming: app.renaming,
                renameSelected: app.renameSelected,
                asking: app.asking,
                ask: askText.visible ? askText.text : "",
                notice: app.notice,
                preview: {
                    shown: previewPane.visible,
                    name: previewName.text,
                    dims: previewDims.text,
                    kind: previewKind.text,
                    date: previewDate.text,
                    image: previewImage.status === Image.Ready
                },
                status: {
                    path: statusPath.text,
                    pathElided: statusPath.truncated,
                    counts: statusCounts.text,
                    at: statusAt.text
                },
                drawn: app.drawnCursor(),
                dragging: app.dragging,
                dragUris: F.uriList(app.dragPaths),
                chip: chipLabel.text
            });
        }

        // A row's box in the window, for a check that drags it.
        function box(name: string): string {
            const i = app.rows.findIndex(r => r.name === name);
            const item = i >= 0 ? rowList.itemAtIndex(i) : null;
            if (!item)
                return "null";
            const p = item.mapToItem(null, 0, 0);
            return JSON.stringify({ x: p.x, y: p.y, w: item.width, h: item.height });
        }

        // A row as drawn, its mark, icon and date face, for a check that reads rows off the cursor.
        function row(name: string): string {
            const i = app.rows.findIndex(r => r.name === name);
            const item = i >= 0 ? rowList.itemAtIndex(i) : null;
            return item ? JSON.stringify(item.drawn()) : "null";
        }

        // A place as drawn: its fill, label and icon.
        function place(label: string): string {
            const i = app.allPlaces.slice(0, -1).findIndex(p => p.label === label);
            const item = i >= 0 ? placeRepeater.itemAt(i) : label === app.trash.label ? trashRow : null;
            return item ? JSON.stringify(item.drawnLook()) : "null";
        }
    }

    FloatingWindow {
        id: win

        title: app.head.folder
        implicitWidth: 1200
        implicitHeight: 716
        color: c.surface ?? "white"

        Connections {
            target: win.contentItem.Window.window
            function onFrameSwapped() {
                if (app.firstFrameMs !== null)
                    return;
                uptime.reload();
                app.firstFrameMs = Status.processAgeMs(uptime.text(), selfStat.text());
            }
        }

        FilesShare {
            id: share
            // Above the column that is declared after it.
            z: 10
            c: app.c
            fonts: app.fonts
            look: app.look
            onClosed: keys.forceActiveFocus()
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                const k = event.key;
                const t = event.text;
                app.notice = "";
                // The failure card waits for r, s or esc; the copy waits with it.
                if (app.ops.failed) {
                    if (t === "r")
                        app.ops.answer("retry");
                    else if (t === "s")
                        app.ops.answer("skip");
                    else if (k === Qt.Key_Escape)
                        app.ops.answer("cancel");
                    event.accepted = true;
                    return;
                }
                if (app.ops.running && k === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                    app.ops.cancel();
                    event.accepted = true;
                    return;
                }
                if (app.asking === "trash") {
                    if (k === Qt.Key_Return || k === Qt.Key_Enter)
                        app.doTrash();
                    else if (k === Qt.Key_Escape)
                        app.asking = "";
                    event.accepted = true;
                    return;
                }
                if (app.finding) {
                    if (k === Qt.Key_Escape) {
                        app.finding = false;
                        app.setQuery("");
                    } else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                        app.finding = false;
                    else if (k === Qt.Key_Backspace)
                        app.setQuery(app.query.slice(0, -1));
                    else if (t !== "" && t.charCodeAt(0) >= 32)
                        app.setQuery(app.query + t);
                    event.accepted = true;
                    return;
                }
                if (app.jumping) {
                    if (k === Qt.Key_Escape)
                        app.jumping = false;
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                        app.jump();
                    else if (k === Qt.Key_Backspace)
                        app.setJump(app.jumpQuery.slice(0, -1));
                    else if (t !== "" && t.charCodeAt(0) >= 32)
                        app.setJump(app.jumpQuery + t);
                    event.accepted = true;
                    return;
                }
                const g = app.gHeld;
                app.gHeld = false;
                if (t === "g") {
                    if (g)
                        app.rowKey("top");
                    else
                        app.gHeld = true;
                }
                else if (t === "G")
                    app.rowKey("bottom");
                else if (t === "z")
                    app.startJump();
                else if (t === "/") {
                    // A new find starts empty, as yazi's and vim's do.
                    app.setQuery("");
                    app.finding = true;
                }
                else if (t === ".")
                    app.hidden = !app.hidden;
                else if (k === Qt.Key_Escape)
                    app.quit();
                else if (k === Qt.Key_Tab)
                    app.toSide();
                else if (t === "e" && app.side === "places" && app.allPlaces[app.placeAt].group === "drives")
                    app.drivesWatch.eject(app.allPlaces[app.placeAt].path);
                else if (t === "j" || k === Qt.Key_Down)
                    app.rowKey("down");
                else if (t === "k" || k === Qt.Key_Up)
                    app.rowKey("up");
                else if (t === "l" || k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter)
                    app.rowKey("in");
                else if (t === "h" || k === Qt.Key_Left || k === Qt.Key_Backspace)
                    app.rowKey("out");
                else if (k === Qt.Key_Space)
                    app.rowKey("mark");
                else if (t !== "" && "rdaosyxp".indexOf(t) >= 0)
                    app.rowKey(t);
                else
                    return;
                event.accepted = true;
            }
        }

        FilesOpenWith {
            id: openWith
            anchors.fill: parent
            look: app.look
            c: app.c
            fonts: app.fonts
            rowKeys: keys
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The header: Files' label, the folder in the theme's face, the key that opens it; Artboard pills the label in its accent and the key in grey.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: plain ? 51 : -1
                Layout.leftMargin: plain ? 18 : 14
                Layout.rightMargin: plain ? 18 : 14
                Layout.topMargin: plain ? 0 : 12
                Layout.bottomMargin: plain ? 0 : 12
                spacing: plain ? 12 : 10

                Rectangle {
                    implicitWidth: headLabel.implicitWidth + (plain ? 18 : 0)
                    implicitHeight: headLabel.implicitHeight + (plain ? 6 : 0)
                    radius: plain ? 8 : 0
                    color: plain ? look.label.fill : "transparent"

                    Text {
                        id: headLabel
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: app.head.label
                        color: plain ? c.accent ?? "blue" : look.small.color
                        font.family: look.small.font
                        font.pixelSize: plain ? 12 : 10
                        font.weight: plain ? Font.Medium : Font.Normal
                        font.letterSpacing: plain ? 0 : 1.4
                    }
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: app.head.folder
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: c.ink ?? "black"
                    font.family: app.face(boardLook.head.face)
                    font.pixelSize: boardLook.head.size
                    font.weight: boardLook.head.weight
                    font.letterSpacing: plain ? -0.14 : 0
                }
                Rectangle {
                    readonly property bool boxed: look.label.kind !== "header"
                    implicitWidth: chipText.implicitWidth + (plain ? 18 : boxed ? 14 : 0)
                    implicitHeight: chipText.implicitHeight + (plain ? 6 : boxed ? 4 : 0)
                    radius: plain ? 8 : 0
                    color: plain ? look.tile.fill : boxed ? look.label.fill : "transparent"

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: app.head.chip
                        color: plain ? c.muted ?? "gray" : parent.boxed ? look.label.color : c.accent ?? "red"
                        font.family: look.small.font
                        font.pixelSize: plain ? 11 : 10
                        font.weight: plain ? Font.Medium : bracket ? Font.Bold : Font.Normal
                        font.letterSpacing: plain ? 0 : bracket ? 1.2 : 1.4
                    }
                }
            }

            Rule {}

            // The folder from ~ after a folder icon, the lead muted and the name medium, and how many rows it holds.
            RowLayout {
                id: pathRow
                readonly property var parts: F.pathParts(app.home, app.folder)
                Layout.fillWidth: true
                Layout.preferredHeight: plain ? 37 : -1
                Layout.leftMargin: plain ? 20 : 16
                Layout.rightMargin: plain ? 20 : 16
                Layout.topMargin: plain ? 0 : 9
                Layout.bottomMargin: plain ? 0 : 9
                spacing: 10

                FilesIcon {
                    id: pathIcon
                    path: F.iconPath(app.voice, "folder")
                    stroke: boardLook.stroke
                    color: plain ? c.muted ?? "gray" : bracket ? c.accent ?? "red" : c.ink ?? "black"
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: pathName.implicitHeight

                    Text {
                        id: pathLead
                        width: Math.min(implicitWidth, Math.max(0, parent.width - Math.min(pathName.implicitWidth, parent.width / 2)))
                        textFormat: Text.PlainText
                        text: pathRow.parts.lead
                        maximumLineCount: 1
                        elide: Text.ElideLeft
                        color: c.muted ?? "gray"
                        font.family: fonts.mono ?? ""
                        font.pixelSize: 13
                    }
                    Text {
                        id: pathName
                        x: pathLead.width
                        width: Math.min(implicitWidth, parent.width - pathLead.width)
                        textFormat: Text.PlainText
                        text: pathRow.parts.name
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        color: c.ink ?? "black"
                        font.family: fonts.mono ?? ""
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }
                Text {
                    id: countLabel
                    textFormat: Text.PlainText
                    text: app.jumping ? F.jumpText(app.voice, app.home, app.jumpQuery, app.jumpFor === app.jumpQuery ? app.jumpTo : null) : app.finding || app.query ? F.findText(app.voice, app.query) : F.countText(app.voice, app.rows.length, app.hidden)
                    color: app.finding || app.jumping ? c.accent ?? "red" : look.small.color
                    font.family: look.small.font
                    font.pixelSize: bracket ? 10 : 11
                    font.letterSpacing: look.small.spacing
                }
            }

            Rule {}

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Home, Downloads, Codes, Pictures and Documents, the GTK bookmarks as PINNED, and Trash at the foot.
                ColumnLayout {
                    Layout.preferredWidth: 200
                    Layout.maximumWidth: 200
                    Layout.fillHeight: true
                    Layout.margins: 8
                    spacing: 0

                    Repeater {
                        id: placeRepeater
                        model: app.allPlaces.slice(0, -1)

                        PlaceRow {
                            required property var modelData
                            required property int index
                            place: modelData
                            at: index
                            heading: index === 0 ? "places" : modelData.group !== app.allPlaces[index - 1].group ? modelData.group : ""
                        }
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                    PlaceRow {
                        id: trashRow
                        place: app.trash
                        at: app.allPlaces.length - 1
                        heading: ""
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

                        // The mark's column and the icon's, as wide as the rows draw them.
                        Item {
                            implicitWidth: app.markWidth
                        }
                        Item {
                            implicitWidth: boardLook.tile ? 28 : 16
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
                            Layout.preferredWidth: 120
                            horizontalAlignment: Text.AlignRight
                            text: plain ? "Modified" : "MODIFIED"
                        }
                    }
                    // Paper and Blueprint rule the head off from the rows in the line colour.
                    Rectangle {
                        visible: !plain
                        Layout.fillWidth: true
                        Layout.bottomMargin: 2
                        implicitHeight: 1
                        color: c.line ?? "gray"
                    }

                    // The mouse is for dragging: a press on a row readies the drag, crossing the threshold starts it.
                    MouseArea {
                        id: dragArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        drag.target: dragOffer
                        onPressed: mouse => {
                            const i = rowList.indexAt(mouse.x, mouse.y + rowList.contentY);
                            if (i < 0) {
                                mouse.accepted = false;
                                return;
                            }
                            app.pressRow(app.rows[i]);
                        }

                    ListView {
                        id: rowList
                        anchors.fill: parent
                        clip: true
                        model: app.rows
                        currentIndex: app.selected
                        highlightMoveDuration: 0
                        boundsBehavior: Flickable.StopAtBounds
                        // The keys scroll it with the cursor; a flick would take the press a drag starts with.
                        interactive: false

                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: index === app.selected && app.side === "list"
                            readonly property bool isMarked: app.marked.indexOf(modelData.name) >= 0
                            readonly property bool dropHere: app.dropping && app.dropAt === index
                            // Artboard draws a marked row's name and icon in the cursor's deep blue too.
                            readonly property bool lit: isCurrent || (plain && isMarked)
                            readonly property color ink: lit ? look.cursor.text : c.ink ?? "black"
                            readonly property color dim: isCurrent ? look.cursor.detail : c.muted ?? "gray"
                            // A box or circle reads as the shape drawn, filled or empty; Blueprint's mark is its text.
                            function markDrawn() {
                                const filled = markBox.color.a > 0;
                                return markBox.radius * 2 >= markBox.width ? (filled ? "●" : "○") : (filled ? "■" : "□");
                            }
                            function drawn() {
                                return {
                                    name: nameText.text,
                                    lines: nameText.lineCount,
                                    elided: nameText.truncated,
                                    size: sizeLabel.text,
                                    dropHere: dropHere,
                                    modified: dateLabel.text,
                                    mark: markDrawn(),
                                    markFill: markBox.visible ? String(markBox.color) : "",
                                    icon: rowIcon.path,
                                    dateFont: {
                                        family: dateLabel.font.family,
                                        italic: dateLabel.font.italic,
                                        size: dateLabel.font.pixelSize
                                    }
                                };
                            }
                            width: rowList.width
                            height: boardLook.row
                            radius: plain ? 10 : look.cursor.radius
                            // The cursor row is filled; a marked row is tinted, as the marked board draws it.
                            color: dropHere ? Qt.alpha(c.accent ?? "red", 0.12) : isCurrent ? look.cursor.fill : isMarked ? app.hereFill : "transparent"
                            // The folder a drop will land in is outlined in the accent, as the drop board draws it; Artboard outlines its cursor row too.
                            border.width: dropHere ? 2 : plain && isCurrent ? 1.5 : 0
                            border.color: c.accent ?? "red"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                // Every row has its mark: Paper's box, filled ink with a tick when marked; Artboard's circle, filled accent; Blueprint's box, filled with its accent.
                                Item {
                                    implicitWidth: app.markWidth
                                    implicitHeight: 16

                                    Rectangle {
                                        id: markBox
                                        anchors.centerIn: parent
                                        width: plain ? 16 : 14
                                        height: width
                                        radius: plain ? 8 : 0
                                        color: !rowItem.isMarked ? "transparent" : plain || bracket ? c.accent ?? "blue" : c.ink ?? "black"
                                        border.width: rowItem.isMarked ? (plain || bracket ? 0 : 1) : plain ? 1.5 : 1
                                        // Artboard's empty circle is #B4BAC4, its dot grid's grey, which no token carries: the muted token at 45% on white lands within 10 of it.
                                        border.color: rowItem.isMarked ? c.ink ?? "black" : plain ? Qt.alpha(c.muted ?? "gray", 0.45) : rowItem.isCurrent ? look.cursor.detail : c.muted ?? "gray"

                                        FilesIcon {
                                            visible: rowItem.isMarked
                                            anchors.centerIn: parent
                                            path: F.iconPath(app.voice, "tick")
                                            box: plain ? 9 : 16
                                            size: plain ? 9 : 10
                                            stroke: plain ? 1.5 : 2.2 * 10 / 16
                                            color: c.surface ?? "white"
                                        }
                                    }
                                }
                                // The board's line icon, a folder or a page; Artboard sets it on a rounded tile.
                                Item {
                                    implicitWidth: boardLook.tile ? 28 : 16
                                    implicitHeight: implicitWidth

                                    Rectangle {
                                        visible: boardLook.tile
                                        anchors.fill: parent
                                        radius: 9
                                        color: rowItem.isCurrent || rowItem.isMarked ? c.surface ?? "white" : look.tile.fill
                                    }
                                    FilesIcon {
                                        id: rowIcon
                                        anchors.centerIn: parent
                                        path: F.iconPath(app.voice, F.rowIcon(rowItem.modelData))
                                        stroke: boardLook.stroke
                                        color: rowItem.lit ? look.cursor.text : plain ? c.muted ?? "gray" : bracket ? c.accent ?? "red" : c.ink ?? "black"
                                    }
                                }
                                Text {
                                    id: nameText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: P.oneLine(rowItem.modelData.name) + (rowItem.modelData.dir ? "/" : "")
                                    maximumLineCount: 1
                                    elide: Text.ElideMiddle
                                    color: rowItem.ink
                                    font.family: bracket ? fonts.mono ?? "" : fonts.ui ?? ""
                                    font.pixelSize: plain ? 14 : 13
                                    // Blueprint's cursor row is bold; Paper's keeps the weight of the row it fills, Artboard's is medium.
                                    font.weight: rowItem.isCurrent && bracket ? Font.Bold : rowItem.modelData.dir || (rowItem.isCurrent && plain) ? Font.Medium : Font.Normal
                                    opacity: renameLoader.active ? 0 : 1

                                    // r: the name becomes a field over itself, the part before the extension selected.
                                    Loader {
                                        id: renameLoader
                                        active: rowItem.isCurrent && app.renaming
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width

                                        sourceComponent: Row {
                                            spacing: 12

                                            Rectangle {
                                                width: Math.min(renameField.contentWidth + 18, renameLoader.width - renameHint.width - 12)
                                                height: 24
                                                color: c.surface ?? "white"
                                                border.width: 2
                                                border.color: c.accent ?? "red"

                                                TextInput {
                                                    id: renameField
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    clip: true
                                                    text: rowItem.modelData.name
                                                    color: c.ink ?? "black"
                                                    selectionColor: c.accent ?? "red"
                                                    selectedTextColor: c.surface ?? "white"
                                                    font.family: bracket ? fonts.mono ?? "" : fonts.ui ?? ""
                                                    font.pixelSize: 13
                                                    onSelectedTextChanged: app.renameSelected = selectedText
                                                    Component.onCompleted: {
                                                        select(0, F.stemLength(rowItem.modelData));
                                                        forceActiveFocus();
                                                    }
                                                    Keys.onPressed: event => {
                                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                                            app.finishRename(text);
                                                        else if (event.key === Qt.Key_Escape)
                                                            app.renaming = false;
                                                        else
                                                            return;
                                                        event.accepted = true;
                                                        keys.forceActiveFocus();
                                                    }
                                                }
                                            }
                                            Text {
                                                id: renameHint
                                                anchors.verticalCenter: parent.verticalCenter
                                                textFormat: Text.PlainText
                                                text: F.promptText(app.voice, [["↵", "save"], ["esc", "cancel"]])
                                                color: c.muted ?? "gray"
                                                font.family: look.small.font
                                                font.pixelSize: 11
                                            }
                                        }
                                    }
                                }
                                Text {
                                    id: sizeLabel
                                    Layout.preferredWidth: 90
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: rowItem.dropHere ? F.dropHere(app.voice) : F.sizeText(app.voice, rowItem.modelData)
                                    color: rowItem.dropHere ? c.accent ?? "red" : rowItem.dim
                                    font.family: fonts.mono ?? ""
                                    font.pixelSize: 12
                                    font.letterSpacing: bracket ? 0.7 : 0
                                }
                                // Paper sets the date in its display face, italic, as its board does.
                                Text {
                                    id: dateLabel
                                    Layout.preferredWidth: 120
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: F.dateText(app.voice, rowItem.modelData.mtime, Date.now())
                                    color: rowItem.dim
                                    font.family: app.face(boardLook.date.face)
                                    font.italic: boardLook.date.italic
                                    font.pixelSize: boardLook.date.size
                                    font.letterSpacing: bracket ? 0.7 : 0
                                }
                            }
                        }
                    }
                    }
                }

                // The cursor file: its picture when it is one, its size, kind and date; a narrow window has no room for it.
                Rectangle {
                    id: previewPane
                    visible: win.width >= 980 && app.cursorRow !== null
                    Layout.fillHeight: true
                    implicitWidth: 1
                    color: look.rule.color
                }
                // 280 px with its padding, as the boards draw it; Artboard's picture sits on a grey rounded tile, Blueprint's in an accent frame.
                ColumnLayout {
                    visible: previewPane.visible
                    Layout.preferredWidth: 244
                    Layout.maximumWidth: 244
                    Layout.fillHeight: true
                    Layout.margins: 18
                    Layout.topMargin: plain ? 16 : 18
                    spacing: plain ? 12 : 14

                    Head {
                        text: plain ? "Preview" : "PREVIEW"
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 186
                        radius: plain ? 10 : 0
                        color: plain ? look.tile.fill : "transparent"
                        border.width: plain ? 0 : 1
                        border.color: bracket ? c.accent ?? "red" : c.muted ?? "gray"
                        clip: true

                        Image {
                            id: previewImage
                            anchors.fill: parent
                            anchors.margins: 1
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            // Bounded, so a 12-megapixel photo decodes to a few MB.
                            sourceSize.width: 1024
                            sourceSize.height: 1024
                            source: app.cursorImage ? "file://" + app.cursorPath.split("/").map(encodeURIComponent).join("/") : ""
                        }
                        Text {
                            id: previewName
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 8
                            width: Math.min(implicitWidth, parent.width - 16)
                            textFormat: Text.PlainText
                            text: app.cursorRow ? P.oneLine(app.cursorRow.name) : ""
                            maximumLineCount: 1
                            elide: Text.ElideMiddle
                            color: plain ? c.ink ?? "black" : c.muted ?? "gray"
                            font.family: fonts.mono ?? ""
                            font.pixelSize: bracket ? 10 : 11
                            font.weight: plain ? Font.Medium : Font.Normal
                            font.letterSpacing: bracket ? 1.4 : 0

                            Rectangle {
                                z: -1
                                anchors.fill: parent
                                anchors.leftMargin: plain ? -7 : -6
                                anchors.rightMargin: plain ? -7 : -6
                                anchors.topMargin: -2
                                anchors.bottomMargin: -2
                                radius: plain ? 6 : 0
                                color: c.surface ?? "white"
                            }
                        }
                    }
                    Text {
                        id: previewDims
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: app.cursorRow ? F.previewMeta(app.voice, app.cursorRow, app.dims.path === app.cursorPath ? app.dims.width : 0, app.dims.height).dims : ""
                        color: c.ink ?? "black"
                        font.family: fonts.mono ?? ""
                        font.pixelSize: plain ? 15 : 14
                        font.weight: Font.Medium
                    }
                    Text {
                        id: previewKind
                        textFormat: Text.PlainText
                        text: app.cursorRow ? F.previewMeta(app.voice, app.cursorRow, 0, 0).kind : ""
                        color: c.muted ?? "gray"
                        font.family: fonts.mono ?? ""
                        font.pixelSize: 12
                        font.letterSpacing: bracket ? 0.7 : 0
                    }
                    Text {
                        id: previewDate
                        textFormat: Text.PlainText
                        text: app.cursorRow ? F.previewMeta(app.voice, app.cursorRow, 0, 0).date : ""
                        color: c.muted ?? "gray"
                        font.family: fonts.mono ?? ""
                        font.pixelSize: 12
                        font.letterSpacing: bracket ? 0.7 : 0
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            Rule {}

            // A running copy or move: what, from where, how far, and how to stop it.
            RowLayout {
                visible: app.ops.running && !app.ops.failed
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                spacing: 14

                Text {
                    id: opSay
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: app.ops.running ? F.opLine(app.voice, app.home, app.ops).say : ""
                    maximumLineCount: 1
                    elide: Text.ElideMiddle
                    color: c.ink ?? "black"
                    font.family: look.small.font
                    font.pixelSize: 12
                }
                Text {
                    id: opProgress
                    textFormat: Text.PlainText
                    text: app.ops.running ? F.opLine(app.voice, app.home, app.ops).progress : ""
                    color: c.accent ?? "red"
                    font.family: fonts.mono ?? ""
                    font.pixelSize: 12
                }
                Text {
                    id: opKeys
                    textFormat: Text.PlainText
                    text: app.ops.running ? F.opLine(app.voice, app.home, app.ops).keys : ""
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: 11
                }
            }

            Rule {
                visible: app.ops.running && !app.ops.failed
            }

            // The status line: the cursor's path, the counts beside it, and where the cursor is, muted at the right.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: plain ? 33 : -1
                Layout.leftMargin: plain ? 20 : 16
                Layout.rightMargin: plain ? 20 : 16
                Layout.topMargin: plain ? 0 : 8
                Layout.bottomMargin: plain ? 0 : 8
                spacing: 18

                // The path takes its whole width and gives way only when the row runs out; bound to its implicitWidth it stayed elided with room beside it (#KYZ754D8), so the measure is the text's own.
                TextMetrics {
                    id: pathMetrics
                    font: statusPath.font
                    text: statusPath.text
                }
                Text {
                    id: statusPath
                    Layout.fillWidth: true
                    Layout.preferredWidth: Math.ceil(pathMetrics.advanceWidth) + 1
                    Layout.maximumWidth: Math.ceil(pathMetrics.advanceWidth) + 1
                    Layout.minimumWidth: 40
                    textFormat: Text.PlainText
                    text: app.cursorRow ? P.oneLine(F.tilde(app.home, app.pathOf(app.cursorRow))) : ""
                    maximumLineCount: 1
                    elide: Text.ElideMiddle
                    color: c.ink ?? "black"
                    font.family: fonts.mono ?? ""
                    font.pixelSize: 12
                    font.letterSpacing: bracket ? 0.7 : 0
                }
                Text {
                    id: statusCounts
                    Layout.maximumWidth: win.width * 0.45
                    maximumLineCount: 1
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    text: app.statusShown.counts
                    color: app.notice || app.ops.failed ? c.danger ?? "red" : c.muted ?? "gray"
                    font.family: fonts.mono ?? ""
                    font.pixelSize: 12
                    font.letterSpacing: bracket ? 0.7 : 0
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    id: statusAt
                    Layout.maximumWidth: win.width * 0.25
                    maximumLineCount: 1
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    text: app.statusShown.at
                    color: c.muted ?? "gray"
                    font.family: fonts.mono ?? ""
                    font.pixelSize: 12
                    font.letterSpacing: bracket ? 0.7 : 0
                }
            }

            // The bar above the keys: d's question, or a's field for the new folder's name.
            RowLayout {
                visible: app.asking !== ""
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 6
                Layout.bottomMargin: 6
                spacing: 10

                Text {
                    id: askText
                    visible: app.asking === "trash"
                    textFormat: Text.PlainText
                    text: {
                        const a = F.trashAsk(app.voice, app.trashPaths.length);
                        return [a.say].concat(a.keys.map(k => k.key + " " + k.word)).join(" ");
                    }
                    color: c.danger ?? "red"
                    font.family: look.small.font
                    font.pixelSize: 12
                }
                Text {
                    visible: app.asking === "mkdir"
                    textFormat: Text.PlainText
                    text: plain ? "New folder" : bracket ? "> NEW FOLDER" : "NEW FOLDER"
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: 11
                }
                Rectangle {
                    visible: app.asking === "mkdir"
                    Layout.preferredWidth: 280
                    implicitHeight: 24
                    color: c.surface ?? "white"
                    border.width: 2
                    border.color: c.accent ?? "red"

                    TextInput {
                        id: mkdirField
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: c.ink ?? "black"
                        font.family: bracket ? fonts.mono ?? "" : fonts.ui ?? ""
                        font.pixelSize: 13
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                app.finishMkdir(text);
                            else if (event.key === Qt.Key_Escape)
                                app.asking = "";
                            else
                                return;
                            event.accepted = true;
                            keys.forceActiveFocus();
                        }
                    }
                }
                Text {
                    visible: app.asking === "mkdir"
                    textFormat: Text.PlainText
                    text: F.promptText(app.voice, [["↵", "make"], ["esc", "cancel"]])
                    color: c.muted ?? "gray"
                    font.family: look.small.font
                    font.pixelSize: 11
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            Rule {}

            // The keys, each with its word: Paper's in tracked caps, Artboard's on grey chips, Blueprint's bracketed in its accent.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: plain ? 14 : 16
                Layout.rightMargin: plain ? 14 : 16
                Layout.topMargin: plain ? 10 : 11
                Layout.bottomMargin: plain ? 10 : 11
                spacing: plain ? 8 : 16

                Repeater {
                    id: stripRepeater
                    model: app.dropping ? F.dropKeys(app.voice) : app.dragging ? F.dragKeys(app.voice) : F.keyStrip(app.voice)

                    Rectangle {
                        required property var modelData
                        // The pair as drawn, in the case the font draws it.
                        function drawn() {
                            const up = t => keyText.font.capitalization === Font.AllUppercase ? t.toUpperCase() : t;
                            return {
                                key: up(keyText.text),
                                word: up(wordText.text),
                                keyWeight: keyText.font.weight,
                                keyColor: String(keyText.color),
                                spacing: keyText.font.letterSpacing
                            };
                        }
                        implicitWidth: pair.implicitWidth + (boardLook.strip.chip ? 14 : 0)
                        implicitHeight: pair.implicitHeight + (boardLook.strip.chip ? 6 : 0)
                        radius: boardLook.strip.chip ? look.keyChip.radius : 0
                        color: boardLook.strip.chip ? look.keyChip.fill : "transparent"

                        Row {
                            id: pair
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                id: keyText
                                textFormat: Text.PlainText
                                text: modelData.key
                                color: bracket ? c.accent ?? "red" : c.ink ?? "black"
                                font.family: fonts.mono ?? ""
                                font.pixelSize: boardLook.strip.size
                                font.weight: boardLook.strip.keyWeight
                                font.letterSpacing: boardLook.strip.spacing
                                font.capitalization: boardLook.strip.caps ? Font.AllUppercase : Font.MixedCase
                            }
                            Text {
                                id: wordText
                                textFormat: Text.PlainText
                                text: modelData.word
                                color: c.muted ?? "gray"
                                font.family: fonts.mono ?? ""
                                font.pixelSize: boardLook.strip.size
                                font.letterSpacing: boardLook.strip.spacing
                                font.capitalization: keyText.font.capitalization
                            }
                        }
                    }
                }
            }
        }

        // Files from another app, or Files' own drag, over the listing: a folder row under the pointer is the target, else the folder shown; a drop anywhere else in the window is refused.
        DropArea {
            id: dropArea
            anchors.fill: parent
            function inList(drag) {
                const p = rowList.mapFromItem(dropArea, drag.x, drag.y);
                return p.x >= 0 && p.y >= 0 && p.x < rowList.width && p.y < rowList.height ? p : null;
            }
            // Files' own drag is a drop only over a folder row; over its own folder it is still a drag out.
            function hover(drag) {
                const p = inList(drag);
                if (p)
                    app.hoverDrop(p.y);
                else
                    app.dropAt = -1;
                app.dropping = p !== null && app.dropPaths.length > 0 && (drag.source !== dragOffer || app.dropAt >= 0);
            }
            onEntered: drag => {
                app.dropPaths = F.dropPaths(drag.urls.map(u => String(u)));
                if (!app.dropPaths.length) {
                    drag.accepted = false;
                    return;
                }
                hover(drag);
            }
            onPositionChanged: drag => hover(drag)
            onExited: {
                app.dropping = false;
                app.dropAt = -1;
            }
            onDropped: drop => {
                if (inList(drop) && app.dropInto(F.dropPaths(drop.urls.map(u => String(u))), drop.source === dragOffer))
                    drop.accept(Qt.CopyAction);
                app.dropping = false;
                app.dropAt = -1;
            }
        }

        // The copy-failure card over the window: the error, each file's fate, and r, s or esc.
        Rectangle {
            id: failCard
            function drawn() {
                const rows = [];
                for (let i = 0; i < failRows.count; i++) {
                    const row = failRows.itemAtIndex(i);
                    if (row)
                        rows.push(row.drawn());
                }
                return {
                    head: failHead.text,
                    title: failTitle.text,
                    why: failWhy.text,
                    rows: rows,
                    foot: failFoot.text,
                    keys: failKeys.text,
                    fits: failCard.height <= win.height
                };
            }
            visible: app.opFail !== null
            z: 20
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 48)
            height: failColumn.implicitHeight + 36
            color: c.surface ?? "white"
            radius: plain ? 12 : 0
            border.width: 1
            border.color: c.danger ?? "red"

            Column {
                id: failColumn
                x: 18
                y: 18
                width: parent.width - 36
                spacing: 10

                Text {
                    id: failHead
                    textFormat: Text.PlainText
                    text: app.opFail ? app.opFail.head : ""
                    color: c.danger ?? "red"
                    font.family: look.small.font
                    font.pixelSize: 10
                    font.letterSpacing: look.small.spacing
                }
                Text {
                    id: failTitle
                    width: parent.width
                    textFormat: Text.PlainText
                    text: app.opFail ? app.opFail.title : ""
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: c.ink ?? "black"
                    font.family: bracket ? fonts.mono ?? "" : fonts.display ?? ""
                    font.pixelSize: 20
                }
                Text {
                    id: failWhy
                    width: parent.width
                    textFormat: Text.PlainText
                    text: app.opFail ? app.opFail.why : ""
                    wrapMode: Text.Wrap
                    color: c.muted ?? "gray"
                    font.family: fonts.ui ?? ""
                    font.pixelSize: 12
                }
                // Up to eight rows show, scrolled to the one that stopped, so a drop of 500 files keeps the card inside the window.
                ListView {
                    id: failRows
                    width: parent.width
                    height: Math.min(contentHeight, 8 * 22)
                    clip: true
                    interactive: false
                    model: app.opFail ? app.opFail.rows : []
                    onCountChanged: if (app.ops.failed)
                        positionViewAtIndex(app.ops.failed.index, ListView.Contain)

                    delegate: Row {
                        id: failRow
                        required property var modelData
                        height: 22
                        function drawn() {
                            return {
                                name: failName.text,
                                state: failState.text,
                                lines: failName.lineCount
                            };
                        }
                        width: failRows.width
                        spacing: 10

                        Text {
                            width: 14
                            textFormat: Text.PlainText
                            text: failRow.modelData.stopped ? "!" : ""
                            color: c.danger ?? "red"
                            font.family: fonts.mono ?? ""
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                        Text {
                            id: failName
                            width: Math.min(implicitWidth, failColumn.width * 0.45)
                            textFormat: Text.PlainText
                            text: failRow.modelData.name
                            maximumLineCount: 1
                            elide: Text.ElideMiddle
                            color: c.ink ?? "black"
                            font.family: fonts.mono ?? ""
                            font.pixelSize: 12
                        }
                        Text {
                            id: failState
                            textFormat: Text.PlainText
                            text: failRow.modelData.state
                            color: failRow.modelData.stopped ? c.danger ?? "red" : c.muted ?? "gray"
                            font.family: look.small.font
                            font.pixelSize: 11
                        }
                    }
                }
                Text {
                    id: failFoot
                    width: parent.width
                    textFormat: Text.PlainText
                    text: app.opFail ? app.opFail.foot : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideMiddle
                    color: c.muted ?? "gray"
                    font.family: fonts.ui ?? ""
                    font.pixelSize: 11
                }
                Text {
                    id: failKeys
                    textFormat: Text.PlainText
                    text: app.opFail ? app.opFail.keys : ""
                    color: c.ink ?? "black"
                    font.family: look.small.font
                    font.pixelSize: 11
                }
            }
        }

        // What a row's MouseArea drags: the platform drag carries the files' URIs into any app, foot among them.
        Item {
            id: dragOffer
            Drag.active: dragArea.drag.active
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.mimeData: ({
                    "text/uri-list": F.uriList(app.dragPaths)
                })
            Drag.imageSource: app.chipUrl
            Drag.hotSpot.x: -14
            Drag.hotSpot.y: -18
            Drag.onDragStarted: app.dragging = true
            Drag.onDragFinished: app.dragging = false
        }

        // Out of sight: the drag image, a chip reading "3 files" with its count badge, is grabbed from here.
        Item {
            width: 0
            height: 0
            clip: true

            Rectangle {
                id: dragChip
                width: chipRow.implicitWidth + 20
                height: 30
                radius: plain ? 15 : 0
                color: c.surface ?? "white"
                border.width: 1
                border.color: c.ink ?? "black"

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        id: chipLabel
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: F.chipText(app.voice, app.dragRows.length)
                        color: c.ink ?? "black"
                        font.family: bracket ? fonts.mono ?? "" : fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: plain ? 9 : 0
                        color: c.accent ?? "red"

                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: String(app.dragRows.length)
                            color: c.surface ?? "white"
                            font.family: fonts.mono ?? ""
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: look.rule.color
    }

    component Head: Text {
        textFormat: Text.PlainText
        color: look.small.color
        font.family: look.small.font
        font.pixelSize: look.small.size
        font.letterSpacing: look.small.spacing
    }

    // One place: its group's head above the first of the group, then the row, lit where the folder is and filled under the cursor.
    component PlaceRow: ColumnLayout {
        id: placeRow
        property var place
        property int at
        property string heading
        readonly property bool here: place.path === app.folder
        readonly property bool atCursor: app.side === "places" && app.placeAt === at
        // A drive draws its size and an e badge, as the board does.
        readonly property bool drive: place.group === "drives"
        readonly property var driveText: F.driveText(app.voice)
        function drawn() {
            return {
                head: headText.visible ? headText.text : "",
                label: labelText.text,
                lines: labelText.lineCount,
                badge: badgeText.font.capitalization === Font.AllUppercase ? badgeText.text.toUpperCase() : badgeText.text
            };
        }
        // How the place is drawn, apart from drawn(), whose fields the drives check reads whole.
        function drawnLook() {
            return {
                fill: String(placeBox.color),
                label: labelText.text,
                labelColor: String(labelText.color),
                weight: labelText.font.weight,
                icon: placeIcon.path
            };
        }
        Layout.fillWidth: true
        spacing: 0

        Component.onCompleted: if (drive)
            app.driveRows = app.driveRows.concat([placeRow])
        Component.onDestruction: app.driveRows = app.driveRows.filter(r => r !== placeRow)

        Text {
            id: headText
            visible: placeRow.heading !== ""
            topPadding: placeRow.at === 0 ? 4 : 10
            bottomPadding: 6
            leftPadding: 12
            textFormat: Text.PlainText
            text: placeRow.drive ? placeRow.driveText.head : plain ? placeRow.heading.charAt(0).toUpperCase() + placeRow.heading.slice(1) : placeRow.heading.toUpperCase()
            color: look.small.color
            font.family: look.small.font
            font.pixelSize: look.small.size
            font.letterSpacing: look.small.spacing
        }
        // The current place is filled as its board does: Paper's paper shade, Artboard's tint, Blueprint's accent wash in an accent outline.
        Rectangle {
            id: placeBox
            readonly property color tint: placeRow.atCursor ? look.cursor.text : placeRow.here ? (plain ? look.cursor.text : bracket ? c.accent ?? "red" : c.ink ?? "black") : plain ? c.ink ?? "black" : c.muted ?? "gray"
            Layout.fillWidth: true
            implicitHeight: boardLook.row
            radius: plain ? 10 : look.cursor.radius
            color: placeRow.atCursor ? look.cursor.fill : placeRow.here ? app.hereFill : "transparent"
            border.width: bracket && placeRow.here && !placeRow.atCursor ? 1 : 0
            border.color: c.accent ?? "red"

            Item {
                id: placeIconBox
                anchors.verticalCenter: parent.verticalCenter
                x: placeRow.drive && plain ? 8 : 10
                width: boardLook.tile ? 28 : 16
                height: width

                Rectangle {
                    visible: boardLook.tile
                    anchors.fill: parent
                    radius: 9
                    color: placeRow.here || placeRow.atCursor ? c.surface ?? "white" : look.tile.fill
                }
                FilesIcon {
                    id: placeIcon
                    anchors.centerIn: parent
                    path: F.iconPath(app.voice, F.placeIcon(placeRow.place))
                    stroke: boardLook.stroke
                    // Artboard's idle icons are muted under ink labels.
                    color: plain && !placeRow.here && !placeRow.atCursor ? c.muted ?? "gray" : placeBox.tint
                }
            }
            Text {
                id: labelText
                anchors.verticalCenter: parent.verticalCenter
                x: placeIconBox.x + placeIconBox.width + (placeRow.drive ? 8 : 10)
                width: parent.width - x - 10 - (placeRow.drive ? badge.width + 8 : 0)
                textFormat: Text.PlainText
                // A pin is a folder's own name and keeps its case.
                text: P.oneLine(placeRow.place.label) + (placeRow.drive ? " · " + placeRow.place.size : "")
                maximumLineCount: 1
                elide: Text.ElideRight
                color: placeBox.tint
                font.family: bracket ? fonts.mono ?? "" : fonts.ui ?? ""
                font.pixelSize: placeRow.drive ? 12 : plain ? 14 : 13
                font.weight: placeRow.here ? (bracket ? Font.Bold : Font.Medium) : Font.Normal
            }
            // Paper's badge is boxed and in caps, Artboard's filled and rounded, Blueprint's boxed in the mono face.
            Rectangle {
                id: badge
                visible: placeRow.drive
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 10
                width: badgeText.implicitWidth + (plain ? 12 : 8)
                height: badgeText.implicitHeight + 2
                radius: plain ? 6 : 0
                color: plain ? Qt.alpha(c.ink ?? "black", 0.06) : "transparent"
                border.width: plain ? 0 : 1
                border.color: placeRow.atCursor ? look.cursor.text : c.muted ?? "gray"

                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: placeRow.driveText.badge
                    color: placeRow.atCursor ? look.cursor.text : c.muted ?? "gray"
                    font.family: bracket ? fonts.mono ?? "" : fonts.ui ?? ""
                    font.pixelSize: plain ? 11 : 10
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.capitalization: voice === "caps" ? Font.AllUppercase : Font.MixedCase
                }
            }
        }
    }
}

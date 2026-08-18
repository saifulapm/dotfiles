import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../components"
import "FilePickerModel.js" as Model
import "../../components/FilterKeys.js" as FilterKeys

// The shell's own file chooser: a themed overlay in the launcher/emoji picker's
// visual language, driven over IPC and answered through a FIFO.
//
// It is not just for our own scripts. bin/qshell-portal exports it as an
// xdg-desktop-portal FileChooser backend, so every portal-using app — Firefox,
// Electron apps, anything flatpaked — gets this window instead of the GTK one.
// That is the whole point: a file dialog that follows the theme.
//
// The request shape is the portal's, flattened to JSON:
//   {token, fifo, title, mode: "open"|"save"|"savefiles", multiple, directory,
//    path, name, filters: [{name, globs, mimes}], filterIndex, acceptLabel}
// and the answer written back to `fifo` is one JSON line:
//   {"response": 0, "paths": [...]} | {"response": 1}
// (0 = chosen, 1 = cancelled — the portal's own codes).
//
// Requests queue rather than collide: a second app asking while the card is up
// waits its turn instead of stealing the window or being refused.
//
// Keyboard model matches the emoji picker: every printable key is text (the
// filter, or the file name when saving), so navigation lives on the arrows.
Scope {
    id: pickerRoot

    required property var theme

    readonly property string home: Quickshell.env("HOME") || "/"

    // ------------------------------------------------------------- requests
    property var queue: []
    readonly property var request: queue.length > 0 ? queue[0] : null
    property bool opened: false

    readonly property string mode: request ? String(request.mode || "open") : "open"
    // "open" | "save" | "folder" — SaveFiles arrives as a folder pick and the
    // portal service fans the chosen directory back out over the app's names.
    readonly property bool saving: mode === "save"
    readonly property bool directoryMode: mode === "folder" || (request ? request.directory === true : false)
    readonly property bool multiple: request ? request.multiple === true : false
    readonly property string title: {
        if (!request)
            return "Select file";
        const given = String(request.title || "").trim();
        if (given !== "")
            return given;
        if (saving)
            return "Save file";
        return directoryMode ? "Select folder" : "Open file";
    }
    readonly property string acceptLabel: {
        if (request && String(request.acceptLabel || "") !== "")
            return String(request.acceptLabel).replace(/_/g, "");
        if (saving)
            return "Save";
        return directoryMode ? "Choose folder" : "Open";
    }
    readonly property var filters: request && request.filters instanceof Array ? request.filters : []
    readonly property var activeFilter: filters.length > 0 ? filters[Math.max(0, Math.min(filterIndex, filters.length - 1))] : null

    // ----------------------------------------------------------- navigation
    property string currentPath: home
    // The filter while opening, the file name while saving.
    property string query: ""
    // Which input printable keys edit: the query above, a typed path
    // (ctrl+L), or a new folder's name (ctrl+shift+N / the button).
    property string fieldMode: "query"
    property string pathInput: ""
    property string newFolderName: ""
    // Where the previous pick ended, for requests that name no start path.
    // In-memory on purpose: the picker's loader is never evicted, so this
    // lives as long as the shell.
    property string lastDir: ""
    property int cursor: 0
    property int filterIndex: 0
    property bool showHidden: false
    // "name" | "size" | "time" — applied in JS over the listed rows.
    property string sortField: "name"
    property bool sortReversed: false
    // path -> true, for the multi-select case. Selection is keyed by full
    // path on purpose: it survives navigating between directories, so one
    // multi-select can gather files from several folders.
    property var selection: ({})
    property int selectionCount: 0
    // Range selection: the anchor is the last explicitly chosen row (click,
    // ctrl+space, keyboard move — not hover), and anchorSelection is the
    // selection as it stood when the anchor was set. Shift-extending
    // recomputes selection = anchorSelection ∪ range(anchor..cursor), which
    // is what lets a shrinking range deselect what it no longer covers.
    property int anchor: 0
    property var anchorSelection: ({})
    // Two-step save-over-existing: the first Enter arms, the second finishes.
    property bool overwritePending: false
    // Last hover scene position: rows sliding under a stationary pointer
    // (wheel or keyboard scrolling) re-fire hover, and only a pointer that
    // actually moved may steal the cursor.
    property real hoverSceneX: -1
    property real hoverSceneY: -1
    // When a tap entered a folder: the second tap of a double-click lands on
    // a fresh delegate (or a mid-transition phantom row) and must be
    // swallowed, so double-click-a-folder descends once, not twice.
    property double tapNavMs: 0
    property var entries: []
    property double nowMs: Date.now()

    readonly property var crumbs: Model.crumbsFor(currentPath, home)
    readonly property var currentEntry: cursor >= 0 && cursor < entries.length ? entries[cursor] : null

    // What the field is showing right now, whichever input owns it.
    readonly property string fieldText: fieldMode === "path" ? pathInput : (fieldMode === "newfolder" ? newFolderName : query)
    readonly property string fieldPlaceholder: {
        if (fieldMode === "path")
            return "type a path";
        if (fieldMode === "newfolder")
            return "new folder name";
        return saving ? "file name" : "filter";
    }

    // Whether the field holds a name the user is COMPOSING (a save name, a
    // typed path, a new folder's name) rather than a filter over the list.
    // A composed name gets a real caret — click to place it, ← → to walk it,
    // home/end, selection — because turning "invoice-2026.pdf" into
    // "invoice-final.pdf" is an edit, and an append-only field makes that a
    // count-the-backspaces exercise. The open-mode filter stays append-only:
    // there, ← → are worth far more as folder navigation than as caret moves.
    readonly property bool fieldEditable: fieldMode !== "query" || saving

    // Write back to whichever property the field is currently showing.
    function setFieldText(value) {
        const text = String(value);
        if (fieldMode === "path")
            pathInput = text;
        else if (fieldMode === "newfolder")
            newFolderName = text;
        else
            query = text;
    }

    // Where the caret lands when the field takes focus. A save name preselects
    // its stem, so the first keystroke replaces the name and keeps the
    // extension — what every other save dialog does, and the whole reason a
    // suggested name is worth suggesting. A typed path is seeded with the
    // current directory and wants the caret at the end instead: selecting it
    // would mean the first keystroke threw the seed away.
    function placeCaret(input) {
        if (!input)
            return;
        if (fieldMode === "path" || fieldMode === "newfolder") {
            input.cursorPosition = input.length;
            return;
        }
        const text = String(input.text || "");
        const dot = text.lastIndexOf(".");
        if (dot > 0)
            input.select(0, dot);
        else
            input.selectAll();
    }

    // -------------------------------------------------------------- sidebar
    // Places and mounts come from a per-open probe (they change under us);
    // pins live in GTK's own bookmarks file so every GTK app shares them.
    property var places: []
    property var mounts: []
    property string bookmarksText: ""
    readonly property string bookmarksPath: home + "/.config/gtk-3.0/bookmarks"
    readonly property var pinned: Model.parseGtkBookmarks(bookmarksText)
    readonly property var sidebarRows: Model.sidebarRows(places, pinned, mounts)

    function runProbe() {
        if (placesProbe.running)
            return;
        placesProbe.command = ["sh", "-c", Model.probeScript()];
        placesProbe.running = true;
    }

    function jumpToPlace(slot) {
        for (let i = 0; i < sidebarRows.length; i++) {
            if (sidebarRows[i].kind === "item" && sidebarRows[i].shortcut === slot) {
                enter(sidebarRows[i].path);
                return;
            }
        }
    }

    function togglePin() {
        // One write at a time: a second toggle before the reload lands would
        // compute from the pre-write text and undo the first.
        if (pinWriter.running)
            return;
        const next = Model.toggleBookmark(bookmarksText, currentPath);
        pinWriter.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "qshell-pin", bookmarksPath, next];
        pinWriter.running = true;
    }

    readonly property Process placesProbe: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const parsed = Model.parsePlaces(String(text || ""), pickerRoot.home);
                pickerRoot.places = parsed.places;
                pickerRoot.mounts = parsed.mounts;
            }
        }
    }

    readonly property Process pinWriter: Process {
        onExited: pickerRoot.bookmarksFile.reload()
    }

    readonly property FileView bookmarksFile: FileView {
        path: pickerRoot.bookmarksPath
        watchChanges: true
        printErrors: false
        onLoaded: pickerRoot.bookmarksText = String(text() || "")
        onFileChanged: reload()
        Component.onCompleted: reload()
    }

    // ------------------------------------------------------------- geometry
    readonly property int cardMargin: theme.space(4)
    readonly property int rowHeight: theme.space(9)
    readonly property int cardWidth: panel.width > 0 ? Math.min(theme.space(290), panel.width - theme.space(16)) : theme.space(290)
    readonly property int sidebarWidth: theme.space(44)
    // The details/preview pane rides open-file dialogs only; save and folder
    // dialogs give the room back to the list.
    readonly property bool previewable: !saving && !directoryMode
    readonly property int previewWidth: theme.space(52)
    readonly property int cardHeight: panel.height > 0 ? Math.min(theme.space(160), panel.height - theme.space(16)) : theme.space(160)

    // --------------------------------------------------------------- opening
    function pick(payload) {
        let req = null;
        try {
            req = JSON.parse(String(payload || ""));
        } catch (e) {
            console.warn("filepicker: unparseable request:", e);
            return "error";
        }
        if (!req || String(req.fifo || "") === "")
            return "error";
        const next = queue.slice();
        next.push(req);
        queue = next;
        if (next.length === 1)
            startRequest();
        return "ok";
    }

    function startRequest() {
        if (!request)
            return;
        const req = request;
        const startPath = String(req.path || "");
        currentPath = startPath !== "" ? startPath : (lastDir !== "" ? lastDir : home);
        query = saving ? String(req.name || "") : "";
        fieldMode = "query";
        pathInput = "";
        newFolderName = "";
        filterIndex = Number(req.filterIndex || 0);
        selection = ({});
        selectionCount = 0;
        anchor = 0;
        anchorSelection = ({});
        overwritePending = false;
        cursorRestoreTarget = "";
        restoreAnyKind = false;
        restoreDescend = false;
        cursor = 0;
        nowMs = Date.now();
        runProbe();
        opened = true;
        rebuild();
    }

    // Answer and move on. `paths` empty means cancelled.
    function finish(paths) {
        const req = request;
        if (!req)
            return;
        const chosen = paths || [];
        if (chosen.length > 0)
            lastDir = currentPath;
        const answer = JSON.stringify(chosen.length > 0 ? {
            response: 0,
            paths: chosen
        } : {
            response: 1
        });
        // A detached writer, not a tracked Process: the FIFO's reader is the
        // portal service, and answering must not depend on the shell keeping a
        // child alive. `timeout` covers a reader that died between the request
        // and the answer, where the open() for write would block forever.
        Quickshell.execDetached(["setpriv", "--pdeathsig", "TERM", "--", "timeout", "10", "sh", "-c", 'printf "%s\\n" "$1" > "$2"', "qshell-picker", answer, String(req.fifo)]);

        const next = queue.slice(1);
        queue = next;
        if (next.length > 0)
            startRequest();
        else {
            opened = false;
            query = "";
        }
    }

    function cancel() {
        finish([]);
    }

    // The portal closed the request behind our back (the app went away).
    function cancelToken(token) {
        const id = String(token || "");
        if (id === "")
            return "error";
        const kept = [];
        let dropped = false;
        for (let i = 0; i < queue.length; i++) {
            if (String(queue[i].token || "") === id && !dropped) {
                dropped = true;
                continue;
            }
            kept.push(queue[i]);
        }
        if (!dropped)
            return "unknown";
        const wasCurrent = String(queue[0].token || "") === id;
        queue = kept;
        if (wasCurrent) {
            if (kept.length > 0)
                startRequest();
            else {
                opened = false;
                query = "";
            }
        }
        return "ok";
    }

    // ------------------------------------------------------------ listing
    FolderListModel {
        id: folder

        folder: Model.pathToUrl(pickerRoot.currentPath)
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: pickerRoot.showHidden
        showFiles: !pickerRoot.directoryMode
        sortField: FolderListModel.Name
        caseSensitive: false

        onCountChanged: pickerRoot.rebuild()
        onFolderChanged: pickerRoot.rebuild()
        // The restore target may only appear once the async listing has
        // fully arrived, and Ready is also the moment to give up on it.
        onStatusChanged: pickerRoot.tryRestoreCursor()
    }

    onQueryChanged: {
        overwritePending = false;
        rebuild();
    }
    onCurrentPathChanged: overwritePending = false
    onFilterIndexChanged: rebuild()
    onShowHiddenChanged: rebuild()
    onSortFieldChanged: rebuild()
    onSortReversedChanged: rebuild()

    // A header click: same column flips, a new column starts in its useful
    // direction — names A→Z, but newest and largest first.
    function setSort(field) {
        if (sortField === field)
            sortReversed = !sortReversed;
        else {
            sortField = field;
            sortReversed = field !== "name";
        }
        // The change handlers re-sorted `entries` synchronously above; the
        // anchor's old index now points at a different row.
        snapAnchor(cursor);
    }

    function rebuild() {
        if (!opened) {
            entries = [];
            return;
        }
        const rows = [];
        const count = folder.count;
        for (let i = 0; i < count; i++) {
            const name = String(folder.get(i, "fileName"));
            const isDir = folder.get(i, "fileIsDir") === true;
            // The name box is a file name while saving, not a filter, so it
            // must not hide the directory you are saving into.
            if (!saving && !Model.matchesQuery(name, query))
                continue;
            // Filters apply to files only — a filter that hid folders would
            // make half the filesystem unreachable.
            if (!isDir && !Model.matchesFilter(name, activeFilter))
                continue;
            rows.push({
                name: name,
                path: Model.joinPath(currentPath, name),
                isDir: isDir,
                size: isDir ? -1 : Number(folder.get(i, "fileSize")),
                modified: folder.get(i, "fileModified")
            });
        }
        entries = Model.sortEntries(rows, sortField, sortReversed);
        if (cursor >= rows.length)
            cursor = Math.max(0, rows.length - 1);
        if (cursor < 0)
            cursor = 0;
        tryRestoreCursor();
    }

    // ----------------------------------------------------------- navigation
    function enter(path) {
        // Navigation invalidates any armed cursor restore (a slow listing's
        // pending descend must not fire in a folder the user walked to) and
        // the range anchor (an index into the old folder's rows).
        cursorRestoreTarget = "";
        restoreAnyKind = false;
        restoreDescend = false;
        currentPath = String(path || home);
        cursor = 0;
        snapAnchor(0);
        if (!saving)
            query = "";
        listView.positionViewAtBeginning();
    }

    function goUp() {
        const parent = Model.parentOf(currentPath);
        const from = currentPath;
        enter(parent);
        // Land the cursor on the folder we just left, the way every file
        // manager does. The listing arrives asynchronously, so the restore
        // rides the model's own signals (rebuild/status) rather than a fixed
        // timer that a large or slow directory would outlive.
        cursorRestoreTarget = Model.baseName(from);
    }

    property string cursorRestoreTarget: ""
    // ctrl+L extras: match files too, and descend when the target is a
    // folder — a typed path has no stat, the landing tells us what it was.
    property bool restoreAnyKind: false
    property bool restoreDescend: false

    function tryRestoreCursor() {
        if (!cursorRestoreTarget)
            return;
        // Any-kind matching waits for the finished listing: mid-transition
        // rebuilds can still hold the departed folder's rows, where a file
        // may share the name. (Directory matches were always safe.)
        if (restoreAnyKind && folder.status !== FolderListModel.Ready)
            return;
        for (let i = 0; i < entries.length; i++) {
            if (entries[i].name !== cursorRestoreTarget)
                continue;
            if (!entries[i].isDir && !restoreAnyKind)
                continue;
            const entry = entries[i];
            const descend = restoreDescend && entry.isDir;
            cursorRestoreTarget = "";
            restoreAnyKind = false;
            restoreDescend = false;
            if (descend)
                enter(entry.path);
            else
                moveTo(i);
            return;
        }
        // Listing complete and the target is not in it (hidden or filtered
        // away): stop looking so a later rebuild cannot mis-match.
        if (folder.status === FolderListModel.Ready) {
            cursorRestoreTarget = "";
            restoreAnyKind = false;
            restoreDescend = false;
        }
    }

    // ------------------------------------------------------ typed location
    // ctrl+L: the field becomes a path. Enter with a trailing slash opens
    // that folder outright; otherwise land in the parent and let the restore
    // above descend into a folder or park the cursor on a file.
    function commitPath() {
        let p = Model.rebaseTyped(String(pathInput || "").trim());
        fieldMode = "query";
        pathInput = "";
        if (p === "")
            return;
        if (p === "~")
            p = home;
        else if (p.indexOf("~/") === 0)
            p = home + p.substring(1);
        if (p.indexOf("/") !== 0)
            p = Model.joinPath(currentPath, p);
        const norm = Model.normalizePath(p);
        p = norm.path;
        if (p === "/") {
            enter("/");
            return;
        }
        if (norm.trailing) {
            enter(p);
            return;
        }
        const base = Model.baseName(p);
        if (base.indexOf(".") === 0 && !showHidden)
            showHidden = true;
        const parentDir = Model.parentOf(p);
        const sameDir = parentDir === currentPath;
        enter(parentDir);
        cursorRestoreTarget = base;
        restoreAnyKind = true;
        restoreDescend = true;
        // Same folder: no model signal will fire, so restore by hand — and
        // only then, because right after a folder switch the model may still
        // hold the departed listing.
        if (sameDir)
            tryRestoreCursor();
    }

    // -------------------------------------------------------- new folder
    function commitNewFolder() {
        const name = String(newFolderName || "").trim().replace(/^\/+/, "");
        fieldMode = "query";
        newFolderName = "";
        if (name === "")
            return;
        const target = Model.joinPath(currentPath, name);
        folderMaker.pendingPath = target;
        folderMaker.command = ["mkdir", "-p", "--", target];
        folderMaker.running = true;
    }

    readonly property Process folderMaker: Process {
        property string pendingPath: ""
        onExited: exitCode => {
            if (exitCode === 0 && pendingPath !== "")
                pickerRoot.enter(pendingPath);
            pendingPath = "";
        }
    }

    // ------------------------------------------------------------- paste
    readonly property Process pasteReader: Process {
        command: ["wl-paste", "--no-newline", "--type", "text"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: pickerRoot.applyPaste(String(text || ""))
        }
    }

    function requestPaste() {
        if (!pasteReader.running)
            pasteReader.running = true;
    }

    function applyPaste(text) {
        const value = String(text || "").split("\n")[0].trim();
        if (value === "")
            return;
        // A pasted absolute path into the filter clearly wants to go there.
        if (fieldMode === "query" && !saving && (value.indexOf("/") === 0 || value.indexOf("~/") === 0)) {
            fieldMode = "path";
            pathInput = value;
            return;
        }
        if (fieldMode === "path")
            pathInput += value;
        else if (fieldMode === "newfolder")
            newFolderName += value;
        else {
            query += value;
            if (!saving)
                cursor = 0;
        }
    }

    function move(delta) {
        moveTo(cursor + delta);
    }

    function moveTo(index) {
        if (entries.length === 0)
            return;
        cursor = Math.max(0, Math.min(entries.length - 1, index));
        listView.positionViewAtIndex(cursor, ListView.Contain);
        snapAnchor(cursor);
    }

    // Hover only moves the cursor: no view jump, and no anchor — the row
    // hovered on the way to a shift+click must not become the range start.
    function hoverTo(index) {
        if (index < 0 || index >= entries.length)
            return;
        cursor = index;
    }

    function snapAnchor(index) {
        anchor = index;
        const snap = {};
        for (const key in selection)
            snap[key] = true;
        anchorSelection = snap;
    }

    // What multi-select can hold: files in file mode, folders in folder mode.
    function selectable(entry) {
        return multiple && entry && entry.isDir === directoryMode;
    }

    function setSelection(next) {
        selection = next;
        let n = 0;
        for (const k in next)
            n += 1;
        selectionCount = n;
    }

    function toggleSelection(entry) {
        if (!selectable(entry))
            return;
        const next = {};
        for (const key in selection)
            next[key] = selection[key];
        if (next[entry.path])
            delete next[entry.path];
        else
            next[entry.path] = true;
        setSelection(next);
    }

    // Ctrl+space and ctrl+click: toggle, and re-anchor on the toggled row so
    // a shift-extend that follows builds on the selection as toggled.
    function toggleAt(index) {
        if (index < 0 || index >= entries.length)
            return;
        cursor = index;
        listView.positionViewAtIndex(cursor, ListView.Contain);
        toggleSelection(entries[index]);
        snapAnchor(index);
    }

    // Shift+click / shift+arrows: anchorSelection plus everything selectable
    // between the anchor and here. Recomputing from the snapshot (not
    // accumulating) is what deselects rows a reversed range walks away from.
    function extendTo(index) {
        if (!multiple) {
            moveTo(index);
            return;
        }
        if (entries.length === 0)
            return;
        cursor = Math.max(0, Math.min(entries.length - 1, index));
        listView.positionViewAtIndex(cursor, ListView.Contain);
        const next = {};
        for (const key in anchorSelection)
            next[key] = true;
        const lo = Math.min(anchor, cursor);
        const hi = Math.max(anchor, cursor);
        for (let i = lo; i <= hi; i++) {
            if (selectable(entries[i]))
                next[entries[i].path] = true;
        }
        setSelection(next);
    }

    function selectAll() {
        if (!multiple)
            return;
        const next = {};
        for (const key in selection)
            next[key] = true;
        for (let i = 0; i < entries.length; i++) {
            if (selectable(entries[i]))
                next[entries[i].path] = true;
        }
        setSelection(next);
        snapAnchor(cursor);
    }

    function selectedPaths() {
        const paths = [];
        for (const key in selection)
            paths.push(key);
        paths.sort();
        return paths;
    }

    // Enter: descend into a folder, otherwise take what is under the cursor.
    // While saving, Enter belongs to the typed name — the cursor usually sits
    // on some folder (they sort first), and descending would break the plain
    // type-name-hit-enter flow. Navigation while saving is Right/Left, the
    // mouse, or Enter with nothing typed yet.
    function activate() {
        const entry = currentEntry;
        if (saving) {
            if (String(query || "").trim() === "" && entry && entry.isDir) {
                enter(entry.path);
                return;
            }
            acceptSave();
            return;
        }
        if (entry && entry.isDir) {
            enter(entry.path);
            return;
        }
        accept();
    }

    function accept() {
        if (saving) {
            acceptSave();
            return;
        }
        if (directoryMode) {
            const dirs = selectionCount > 0 ? selectedPaths() : [currentPath];
            finish(multiple ? dirs : [dirs[0]]);
            return;
        }
        if (multiple && selectionCount > 0) {
            finish(selectedPaths());
            return;
        }
        const entry = currentEntry;
        if (!entry || entry.isDir)
            return;
        finish([entry.path]);
    }

    // What the open folder holds under this exact name. Reads the raw model,
    // not `entries`: the active filter may hide the very file being replaced.
    // (A dotfile target with hidden files off stays invisible to this check —
    // FolderListModel is the only filesystem view the shell has.)
    function nameKindInFolder(name) {
        const count = folder.count;
        for (let i = 0; i < count; i++) {
            if (String(folder.get(i, "fileName")) === name)
                return folder.get(i, "fileIsDir") === true ? "dir" : "file";
        }
        return "";
    }

    function acceptSave() {
        const name = String(query || "").trim();
        if (name === "")
            return;
        if (name.indexOf("/") === 0) {
            finish([name]);
            return;
        }
        // A bare name is checked against the open folder: an existing folder
        // under that name is navigation (the GTK chooser's behavior), an
        // existing file arms the two-step overwrite.
        if (name.indexOf("/") === -1) {
            const kind = nameKindInFolder(name);
            if (kind === "dir") {
                query = "";
                enter(Model.joinPath(currentPath, name));
                return;
            }
            if (kind === "file" && !overwritePending) {
                overwritePending = true;
                return;
            }
        }
        finish([Model.joinPath(currentPath, name)]);
    }

    readonly property bool acceptable: {
        if (saving)
            return String(query || "").trim() !== "";
        if (directoryMode)
            return true;
        if (multiple && selectionCount > 0)
            return true;
        return currentEntry !== null && currentEntry.isDir === false;
    }

    // ---------------------------------------------------------------- window
    OverlaySurface {
        id: panel

        theme: pickerRoot.theme
        opened: pickerRoot.opened
        namespace: "qshell-filepicker"
        cardWidth: pickerRoot.cardWidth
        cardHeight: pickerRoot.cardHeight
        onDismissed: pickerRoot.cancel()

        Item {
            id: keyCatcher

            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                const alt = (event.modifiers & Qt.AltModifier) !== 0;
                const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                // Shift-held vertical navigation extends the selection from
                // the anchor; plain navigation just moves (and re-anchors).
                const go = function (index) {
                    if (shift && pickerRoot.multiple)
                        pickerRoot.extendTo(index);
                    else
                        pickerRoot.moveTo(index);
                };
                const page = Math.max(1, Math.floor(listView.height / pickerRoot.rowHeight));

                if (event.key === Qt.Key_Escape) {
                    if (pickerRoot.fieldMode !== "query") {
                        pickerRoot.fieldMode = "query";
                        pickerRoot.pathInput = "";
                        pickerRoot.newFolderName = "";
                    } else if (pickerRoot.overwritePending)
                        pickerRoot.overwritePending = false;
                    else if (!pickerRoot.saving && pickerRoot.query !== "")
                        pickerRoot.query = "";
                    else
                        pickerRoot.cancel();
                } else if (event.key === Qt.Key_Backspace) {
                    if (pickerRoot.fieldMode === "path")
                        // Ctrl erases a path segment, not a word.
                        pickerRoot.pathInput = ctrl ? pickerRoot.pathInput.replace(/\/+$/, "").replace(/[^/]*$/, "") : pickerRoot.pathInput.slice(0, -1);
                    else if (pickerRoot.fieldMode === "newfolder")
                        pickerRoot.newFolderName = FilterKeys.erased(pickerRoot.newFolderName, ctrl);
                    else if (pickerRoot.query !== "")
                        pickerRoot.query = FilterKeys.erased(pickerRoot.query, ctrl);
                    else
                        pickerRoot.goUp();
                } else if (ctrl && event.key === Qt.Key_U) {
                    if (pickerRoot.fieldMode === "path")
                        pickerRoot.pathInput = "";
                    else if (pickerRoot.fieldMode === "newfolder")
                        pickerRoot.newFolderName = "";
                    else
                        pickerRoot.query = "";
                } else if (ctrl && event.key === Qt.Key_L) {
                    pickerRoot.fieldMode = "path";
                    pickerRoot.pathInput = pickerRoot.currentPath === "/" ? "/" : pickerRoot.currentPath + "/";
                } else if (ctrl && shift && event.key === Qt.Key_N) {
                    if (pickerRoot.saving || pickerRoot.directoryMode) {
                        pickerRoot.fieldMode = "newfolder";
                        pickerRoot.newFolderName = "";
                    }
                } else if (ctrl && event.key === Qt.Key_V) {
                    pickerRoot.requestPaste();
                } else if (ctrl && event.key === Qt.Key_H) {
                    pickerRoot.showHidden = !pickerRoot.showHidden;
                } else if (ctrl && event.key === Qt.Key_A) {
                    pickerRoot.selectAll();
                } else if (ctrl && event.key === Qt.Key_D) {
                    pickerRoot.togglePin();
                } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    pickerRoot.jumpToPlace(event.key - Qt.Key_1 + 1);
                } else if (event.key === Qt.Key_Up && !alt) {
                    go(pickerRoot.cursor - 1);
                } else if (event.key === Qt.Key_Down) {
                    go(pickerRoot.cursor + 1);
                } else if (event.key === Qt.Key_PageUp) {
                    go(pickerRoot.cursor - page);
                } else if (event.key === Qt.Key_PageDown) {
                    go(pickerRoot.cursor + page);
                } else if (event.key === Qt.Key_Home) {
                    go(0);
                } else if (event.key === Qt.Key_End) {
                    go(pickerRoot.entries.length - 1);
                } else if (event.key === Qt.Key_Left || (alt && event.key === Qt.Key_Up)) {
                    // alt+← → is the same walk, and the only one available
                    // while a name is being composed — see fieldEditable.
                    pickerRoot.goUp();
                } else if (event.key === Qt.Key_Right) {
                    if (pickerRoot.currentEntry && pickerRoot.currentEntry.isDir)
                        pickerRoot.enter(pickerRoot.currentEntry.path);
                } else if (event.key === Qt.Key_Tab) {
                    if (pickerRoot.filters.length > 1)
                        pickerRoot.filterIndex = (pickerRoot.filterIndex + 1) % pickerRoot.filters.length;
                } else if (ctrl && event.key === Qt.Key_Space) {
                    pickerRoot.toggleAt(pickerRoot.cursor);
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (pickerRoot.fieldMode === "path")
                        pickerRoot.commitPath();
                    else if (pickerRoot.fieldMode === "newfolder")
                        pickerRoot.commitNewFolder();
                    else if (ctrl)
                        pickerRoot.accept();
                    else
                        pickerRoot.activate();
                } else if (FilterKeys.printable(event)) {
                    if (pickerRoot.fieldMode === "path")
                        pickerRoot.pathInput = pickerRoot.pathInput + event.text;
                    else if (pickerRoot.fieldMode === "newfolder")
                        pickerRoot.newFolderName = pickerRoot.newFolderName + event.text;
                    else {
                        pickerRoot.query = pickerRoot.query + event.text;
                        if (!pickerRoot.saving)
                            pickerRoot.cursor = 0;
                    }
                } else {
                    return;
                }
                event.accepted = true;
            }

            // Mouse side/back button walks up a directory, like a browser.
            TapHandler {
                acceptedButtons: Qt.BackButton
                onTapped: pickerRoot.goUp()
            }

            Column {
                anchors.fill: parent
                anchors.margins: pickerRoot.cardMargin
                spacing: pickerRoot.theme.space(3)

                // ------------------------------------------------ header
                Item {
                    width: parent.width
                    height: titleLabel.implicitHeight

                    StyledText {
                        id: titleLabel
                        theme: pickerRoot.theme
                        role: StyledText.Title
                        anchors.left: parent.left
                        anchors.right: modeLabel.left
                        anchors.rightMargin: pickerRoot.theme.space(3)
                        text: pickerRoot.title
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: modeLabel
                        theme: pickerRoot.theme
                        role: StyledText.Caption
                        mono: true
                        muted: true
                        anchors.right: parent.right
                        anchors.verticalCenter: titleLabel.verticalCenter
                        text: pickerRoot.queue.length > 1 ? pickerRoot.queue.length - 1 + " waiting" : (pickerRoot.multiple ? "MULTIPLE" : "")
                        visible: text !== ""
                        font.letterSpacing: 1.2
                    }
                }

                // -------------------------------------------- breadcrumb
                Flickable {
                    width: parent.width
                    height: crumbRow.implicitHeight
                    contentWidth: crumbRow.implicitWidth
                    contentHeight: height
                    interactive: contentWidth > width
                    clip: true

                    Row {
                        id: crumbRow
                        spacing: 0

                        Repeater {
                            model: pickerRoot.crumbs

                            Row {
                                required property var modelData
                                required property int index

                                spacing: 0

                                StyledText {
                                    theme: pickerRoot.theme
                                    muted: true

                                    visible: index > 0
                                    text: "  ›  "
                                }

                                StyledText {
                                    theme: pickerRoot.theme

                                    text: modelData.label
                                    color: index === pickerRoot.crumbs.length - 1 ? pickerRoot.theme.textPrimary : pickerRoot.theme.textMuted

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pickerRoot.enter(modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }

                // ------------------------------------- name/filter field
                Rectangle {
                    width: parent.width
                    height: pickerRoot.theme.space(10)
                    radius: pickerRoot.theme.radius(1)
                    color: pickerRoot.theme.surface2
                    border.width: pickerRoot.theme.borderWidth
                    border.color: pickerRoot.overwritePending ? pickerRoot.theme.warn : (pickerRoot.fieldText !== "" || pickerRoot.fieldMode !== "query" ? pickerRoot.theme.accent : pickerRoot.theme.surface3)

                    // The filter, as a label: append-only, so there is nothing
                    // to put a caret in.
                    Text {
                        visible: !pickerRoot.fieldEditable
                        anchors.left: parent.left
                        anchors.right: fieldHint.left
                        anchors.leftMargin: pickerRoot.theme.space(3)
                        anchors.rightMargin: pickerRoot.theme.space(2)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideLeft
                        text: pickerRoot.fieldText !== "" ? pickerRoot.fieldText : pickerRoot.fieldPlaceholder
                        color: pickerRoot.fieldText !== "" ? pickerRoot.theme.textPrimary : pickerRoot.theme.textMuted
                        font.family: pickerRoot.theme.fontUi
                        font.pixelSize: pickerRoot.theme.fontPx(1.0)
                    }

                    // The placeholder for the editable field, which a TextInput
                    // cannot draw itself.
                    Text {
                        visible: pickerRoot.fieldEditable && pickerRoot.fieldText === ""
                        anchors.left: parent.left
                        anchors.right: fieldHint.left
                        anchors.leftMargin: pickerRoot.theme.space(3)
                        anchors.rightMargin: pickerRoot.theme.space(2)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: pickerRoot.fieldPlaceholder
                        color: pickerRoot.theme.textMuted
                        font.family: pickerRoot.theme.fontMono
                        font.pixelSize: pickerRoot.theme.fontPx(1.0)
                    }

                    // A composed name, as a real text input.
                    TextInput {
                        id: fieldInput

                        visible: pickerRoot.fieldEditable
                        enabled: visible
                        anchors.left: parent.left
                        anchors.right: fieldHint.left
                        anchors.leftMargin: pickerRoot.theme.space(3)
                        anchors.rightMargin: pickerRoot.theme.space(2)
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true

                        text: pickerRoot.fieldText
                        // onTextEdited fires for user edits only, never for the
                        // binding above — so the two can point at each other
                        // without looping.
                        onTextEdited: pickerRoot.setFieldText(text)

                        color: pickerRoot.theme.textPrimary
                        selectionColor: pickerRoot.theme.accent
                        selectedTextColor: pickerRoot.theme.surface1
                        selectByMouse: true
                        activeFocusOnPress: true
                        font.family: pickerRoot.theme.fontMono
                        font.pixelSize: pickerRoot.theme.fontPx(1.0)

                        // Everything the picker owns has to be taken back
                        // before TextInput swallows it: the list cursor, the
                        // accept/cancel keys, and the picker's own chords.
                        // What is left through is text editing — which now
                        // includes ← → home/end, so folder walking moves onto
                        // alt+← → for as long as a name is being composed.
                        Keys.onPressed: event => {
                            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                            const alt = (event.modifiers & Qt.AltModifier) !== 0;
                            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

                            if (alt && event.key === Qt.Key_Left)
                                pickerRoot.goUp();
                            else if (alt && event.key === Qt.Key_Up)
                                pickerRoot.goUp();
                            else if (alt && event.key === Qt.Key_Right) {
                                if (pickerRoot.currentEntry && pickerRoot.currentEntry.isDir)
                                    pickerRoot.enter(pickerRoot.currentEntry.path);
                            } else if (event.key === Qt.Key_Up)
                                pickerRoot.moveTo(pickerRoot.cursor - 1);
                            else if (event.key === Qt.Key_Down)
                                pickerRoot.moveTo(pickerRoot.cursor + 1);
                            else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                                const page = Math.max(1, Math.floor(listView.height / pickerRoot.rowHeight));
                                pickerRoot.moveTo(pickerRoot.cursor + (event.key === Qt.Key_PageUp ? -page : page));
                            } else if (event.key === Qt.Key_Escape) {
                                if (pickerRoot.fieldMode !== "query") {
                                    pickerRoot.fieldMode = "query";
                                    pickerRoot.pathInput = "";
                                    pickerRoot.newFolderName = "";
                                } else if (pickerRoot.overwritePending)
                                    pickerRoot.overwritePending = false;
                                else
                                    pickerRoot.cancel();
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (pickerRoot.fieldMode === "path")
                                    pickerRoot.commitPath();
                                else if (pickerRoot.fieldMode === "newfolder")
                                    pickerRoot.commitNewFolder();
                                else
                                    pickerRoot.activate();
                            } else if (event.key === Qt.Key_Tab) {
                                if (pickerRoot.filters.length > 1)
                                    pickerRoot.filterIndex = (pickerRoot.filterIndex + 1) % pickerRoot.filters.length;
                            } else if (ctrl && event.key === Qt.Key_L) {
                                pickerRoot.fieldMode = "path";
                                pickerRoot.pathInput = pickerRoot.currentPath === "/" ? "/" : pickerRoot.currentPath + "/";
                            } else if (ctrl && shift && event.key === Qt.Key_N) {
                                pickerRoot.fieldMode = "newfolder";
                                pickerRoot.newFolderName = "";
                            } else if (ctrl && event.key === Qt.Key_H)
                                pickerRoot.showHidden = !pickerRoot.showHidden;
                            else if (ctrl && event.key === Qt.Key_D)
                                pickerRoot.togglePin();
                            else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
                                pickerRoot.jumpToPlace(event.key - Qt.Key_1 + 1);
                            else
                                return; // TextInput handles the rest.
                            event.accepted = true;
                        }

                        // The field only owns the keyboard while it is holding
                        // a name; the moment it stops, the list wants its keys
                        // back (or the surface is closing and nothing should
                        // hold focus at all).
                        function claim() {
                            fieldInput.forceActiveFocus();
                            pickerRoot.placeCaret(fieldInput);
                        }

                        Connections {
                            target: pickerRoot

                            function onOpenedChanged() {
                                if (pickerRoot.opened && pickerRoot.fieldEditable)
                                    Qt.callLater(fieldInput.claim);
                                else if (!pickerRoot.opened)
                                    keyCatcher.forceActiveFocus();
                            }

                            // Covers both directions of ctrl+L / ctrl+shift+N
                            // and the escape back out of them.
                            function onFieldEditableChanged() {
                                if (pickerRoot.fieldEditable)
                                    Qt.callLater(fieldInput.claim);
                                else
                                    keyCatcher.forceActiveFocus();
                            }

                            // Switching between two editable modes keeps the
                            // field but changes which property it edits, so the
                            // caret has to be placed again for the new one.
                            function onFieldModeChanged() {
                                if (pickerRoot.fieldEditable)
                                    Qt.callLater(fieldInput.claim);
                            }
                        }
                    }

                    StyledText {
                        id: fieldHint
                        theme: pickerRoot.theme
                        role: StyledText.Small
                        muted: true
                        anchors.right: parent.right
                        anchors.rightMargin: pickerRoot.theme.space(3)
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (pickerRoot.fieldMode === "path")
                                return "⏎ go";
                            if (pickerRoot.fieldMode === "newfolder")
                                return "⏎ create";
                            return pickerRoot.activeFilter ? String(pickerRoot.activeFilter.name || "") + (pickerRoot.filters.length > 1 ? "  ⇥" : "") : "";
                        }
                        visible: text !== ""

                        // Tab cycles filters; so does clicking the label.
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -pickerRoot.theme.space(1)
                            visible: pickerRoot.filters.length > 1 && pickerRoot.fieldMode === "query"
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pickerRoot.filterIndex = (pickerRoot.filterIndex + 1) % pickerRoot.filters.length
                        }
                    }
                }

                // -------------------------------------- sidebar + list
                Rectangle {
                    width: parent.width
                    height: parent.height - y
                    color: "transparent"

                    ListView {
                        id: sidebarList

                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: footer.height + pickerRoot.theme.space(3)
                        width: pickerRoot.sidebarWidth
                        clip: true
                        model: pickerRoot.sidebarRows
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: pickerRoot.theme.space(0.5)

                        delegate: Item {
                            id: sideRow

                            required property var modelData

                            width: sidebarList.width
                            height: pickerRoot.theme.space(8)

                            StyledText {
                                theme: pickerRoot.theme
                                role: StyledText.Micro
                                mono: true
                                muted: true

                                visible: sideRow.modelData.kind === "header"
                                anchors.left: parent.left
                                anchors.leftMargin: pickerRoot.theme.space(2)
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: pickerRoot.theme.space(1)
                                text: sideRow.modelData.label
                                font.letterSpacing: 1.2
                                font.capitalization: Font.AllUppercase
                            }

                            CursorSurface {
                                id: sideItem

                                visible: sideRow.modelData.kind === "item"
                                anchors.fill: parent
                                theme: pickerRoot.theme
                                readonly property bool active: pickerRoot.currentPath === sideRow.modelData.path
                                // The sidebar shows where you ARE, not where a
                                // keyboard cursor is — fill only, no outline.
                                bordered: false
                                current: sideItem.active
                                hasCursor: sideHover.hovered

                                HoverHandler {
                                    id: sideHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: pickerRoot.enter(sideRow.modelData.path)
                                }

                                Text {
                                    id: sideGlyph
                                    anchors.left: parent.left
                                    anchors.leftMargin: pickerRoot.theme.space(2)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: sideRow.modelData.glyph
                                    color: sideItem.active ? pickerRoot.theme.accent : pickerRoot.theme.textMuted
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: pickerRoot.theme.fontPx(1.0)
                                }

                                StyledText {
                                    id: sideDigit
                                    theme: pickerRoot.theme
                                    role: StyledText.Micro
                                    mono: true
                                    muted: true
                                    anchors.right: parent.right
                                    anchors.rightMargin: pickerRoot.theme.space(2)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: sideRow.modelData.shortcut > 0 ? String(sideRow.modelData.shortcut) : ""
                                    visible: text !== ""
                                }

                                StyledText {
                                    theme: pickerRoot.theme
                                    role: StyledText.Small

                                    anchors.left: sideGlyph.right
                                    anchors.leftMargin: pickerRoot.theme.space(2)
                                    anchors.right: sideDigit.visible ? sideDigit.left : parent.right
                                    anchors.rightMargin: pickerRoot.theme.space(2)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: sideRow.modelData.label
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: sidebarDivider

                        anchors.left: sidebarList.right
                        anchors.leftMargin: pickerRoot.theme.space(2)
                        anchors.top: parent.top
                        anchors.bottom: sidebarList.bottom
                        width: pickerRoot.theme.borderWidth
                        color: pickerRoot.theme.surface3
                    }

                    // ------------------------------------ column headers
                    Item {
                        id: listHeader

                        anchors.left: sidebarDivider.right
                        anchors.leftMargin: pickerRoot.theme.space(3)
                        anchors.right: previewPane.left
                        anchors.rightMargin: pickerRoot.theme.space(3)
                        anchors.top: parent.top
                        height: pickerRoot.theme.space(6)

                        SortHeader {
                            anchors.left: parent.left
                            anchors.leftMargin: pickerRoot.theme.space(3)
                            anchors.verticalCenter: parent.verticalCenter
                            field: "name"
                            label: "Name"
                        }

                        SortHeader {
                            id: modifiedHeader
                            anchors.right: parent.right
                            // Mirrors the rows: the checkbox column sits to
                            // the right of the time column while multi-select
                            // is on.
                            anchors.rightMargin: pickerRoot.theme.space(3) + (pickerRoot.multiple ? pickerRoot.theme.space(8) : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            width: pickerRoot.theme.space(20)
                            horizontalAlignment: Text.AlignRight
                            field: "time"
                            label: "Modified"
                        }

                        SortHeader {
                            anchors.right: modifiedHeader.left
                            anchors.rightMargin: pickerRoot.theme.space(3)
                            anchors.verticalCenter: parent.verticalCenter
                            width: pickerRoot.theme.space(16)
                            horizontalAlignment: Text.AlignRight
                            field: "size"
                            label: "Size"
                            visible: !pickerRoot.directoryMode
                        }
                    }

                    ListView {
                        id: listView

                        anchors.left: sidebarDivider.right
                        anchors.leftMargin: pickerRoot.theme.space(3)
                        anchors.right: previewPane.left
                        // The scrollbar's gutter.
                        anchors.rightMargin: pickerRoot.theme.space(3)
                        anchors.top: listHeader.bottom
                        anchors.topMargin: pickerRoot.theme.space(1)
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: footer.height + pickerRoot.theme.space(3)
                        clip: true
                        model: pickerRoot.entries
                        currentIndex: pickerRoot.cursor
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: CursorSurface {
                            id: row

                            required property var modelData
                            required property int index

                            theme: pickerRoot.theme
                            width: listView.width
                            height: pickerRoot.rowHeight
                            // Selection and cursor are the same thing here,
                            // and the fill already says so.
                            bordered: false
                            current: index === pickerRoot.cursor
                            hasCursor: rowHover.hovered

                            readonly property bool picked: pickerRoot.selection[modelData.path] === true

                            HoverHandler {
                                id: rowHover
                                cursorShape: Qt.PointingHandCursor
                                // Follow the pointer, not the scroll: rows
                                // sliding under a stationary mouse re-fire
                                // hover with the same scene position, and
                                // those must not steal the cursor.
                                onPointChanged: {
                                    if (!hovered)
                                        return;
                                    const sp = point.scenePosition;
                                    if (sp.x === pickerRoot.hoverSceneX && sp.y === pickerRoot.hoverSceneY)
                                        return;
                                    pickerRoot.hoverSceneX = sp.x;
                                    pickerRoot.hoverSceneY = sp.y;
                                    if (pickerRoot.cursor !== row.index)
                                        pickerRoot.hoverTo(row.index);
                                }
                            }

                            // The click model every picker shares: one click
                            // selects a file (or enters a folder — cheap and
                            // reversible), a double click commits. A stray
                            // click can no longer answer the dialog.
                            TapHandler {
                                acceptedModifiers: Qt.NoModifier
                                onSingleTapped: {
                                    const now = Date.now();
                                    if (now - pickerRoot.tapNavMs < 350)
                                        return;
                                    const entry = row.modelData;
                                    if (entry.isDir) {
                                        pickerRoot.tapNavMs = now;
                                        pickerRoot.enter(entry.path);
                                        return;
                                    }
                                    pickerRoot.moveTo(row.index);
                                    // Clicking an existing file while saving
                                    // adopts its name, ready to overwrite.
                                    if (pickerRoot.saving)
                                        pickerRoot.query = entry.name;
                                }
                                onDoubleTapped: {
                                    const entry = row.modelData;
                                    if (entry.isDir)
                                        return;
                                    pickerRoot.moveTo(row.index);
                                    if (pickerRoot.saving) {
                                        pickerRoot.query = entry.name;
                                        pickerRoot.acceptSave();
                                        return;
                                    }
                                    // A double-clicked file that is part of
                                    // the selection commits the selection;
                                    // outside it, just that file.
                                    if (pickerRoot.selection[entry.path] === true) {
                                        pickerRoot.accept();
                                        return;
                                    }
                                    pickerRoot.finish([entry.path]);
                                }
                            }

                            TapHandler {
                                acceptedModifiers: Qt.ControlModifier
                                onTapped: pickerRoot.toggleAt(row.index)
                            }

                            TapHandler {
                                acceptedModifiers: Qt.ShiftModifier
                                onTapped: pickerRoot.extendTo(row.index)
                            }

                            Text {
                                id: rowGlyph
                                anchors.left: parent.left
                                anchors.leftMargin: pickerRoot.theme.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                text: Model.glyphFor(row.modelData.name, row.modelData.isDir)
                                color: row.modelData.isDir ? pickerRoot.theme.accent : pickerRoot.theme.textPrimary
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: pickerRoot.theme.fontPx(1.083)
                            }

                            Text {
                                id: rowTick
                                anchors.right: parent.right
                                anchors.rightMargin: pickerRoot.theme.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pickerRoot.multiple
                                width: pickerRoot.theme.space(5)
                                horizontalAlignment: Text.AlignHCenter
                                text: row.picked ? "󰄲" : "󰄱"
                                color: row.picked ? pickerRoot.theme.accent : pickerRoot.theme.textMuted
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: pickerRoot.theme.fontPx(1.0)

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -pickerRoot.theme.space(1)
                                    onClicked: pickerRoot.toggleAt(row.index)
                                }
                            }

                            StyledText {
                                id: rowTime
                                theme: pickerRoot.theme
                                role: StyledText.Caption
                                mono: true
                                muted: true
                                anchors.right: pickerRoot.multiple ? rowTick.left : parent.right
                                anchors.rightMargin: pickerRoot.theme.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                width: pickerRoot.theme.space(20)
                                horizontalAlignment: Text.AlignRight
                                text: Model.formatTime(row.modelData.modified, pickerRoot.nowMs)
                            }

                            StyledText {
                                id: rowSize
                                theme: pickerRoot.theme
                                role: StyledText.Caption
                                mono: true
                                muted: true
                                anchors.right: rowTime.left
                                anchors.rightMargin: pickerRoot.theme.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                width: pickerRoot.theme.space(16)
                                text: row.modelData.isDir ? "" : Model.formatSize(row.modelData.size)
                            }

                            StyledText {
                                theme: pickerRoot.theme

                                anchors.left: rowGlyph.right
                                anchors.leftMargin: pickerRoot.theme.space(3)
                                anchors.right: rowSize.left
                                anchors.rightMargin: pickerRoot.theme.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.name
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ------------------------------------------ scrollbar
                    // Hand-rolled (no QtQuick.Controls in this shell): a
                    // thumb in the gutter right of the list, draggable, with
                    // track clicks jumping straight there.
                    MouseArea {
                        id: scrollTrack

                        anchors.top: listView.top
                        anchors.bottom: listView.bottom
                        anchors.left: listView.right
                        width: pickerRoot.theme.space(3)
                        visible: listView.contentHeight > listView.height
                        hoverEnabled: true
                        onPressed: mouse => jump(mouse.y)
                        onPositionChanged: mouse => {
                            if (pressed)
                                jump(mouse.y);
                        }

                        function jump(y) {
                            const frac = Math.max(0, Math.min(1, y / height));
                            listView.contentY = frac * Math.max(0, listView.contentHeight - listView.height);
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: pickerRoot.theme.space(1)
                            radius: width / 2
                            y: Math.max(0, Math.min(listView.visibleArea.yPosition * scrollTrack.height, scrollTrack.height - height))
                            height: Math.max(pickerRoot.theme.space(6), listView.visibleArea.heightRatio * scrollTrack.height)
                            color: pickerRoot.theme.alpha(pickerRoot.theme.textPrimary, scrollTrack.containsMouse || scrollTrack.pressed ? 0.4 : 0.18)
                        }
                    }

                    // -------------------------------------------- preview
                    Item {
                        id: previewPane

                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: footer.height + pickerRoot.theme.space(3)
                        width: pickerRoot.previewable ? pickerRoot.previewWidth : 0
                        visible: pickerRoot.previewable

                        readonly property var entry: pickerRoot.currentEntry
                        readonly property bool showsImage: entry !== null && !entry.isDir && Model.kindOf(entry.name) === "image"

                        Rectangle {
                            id: previewDivider

                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: pickerRoot.theme.borderWidth
                            color: pickerRoot.theme.surface3
                        }

                        Column {
                            anchors.left: previewDivider.right
                            anchors.leftMargin: pickerRoot.theme.space(3)
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: pickerRoot.theme.space(2)

                            Rectangle {
                                width: parent.width
                                height: pickerRoot.theme.space(48)
                                radius: pickerRoot.theme.radius(1)
                                color: pickerRoot.theme.surface2

                                Image {
                                    id: previewImage

                                    anchors.fill: parent
                                    anchors.margins: pickerRoot.theme.space(1)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    // Caps the decode, not the display — a
                                    // 6000px photo must not decode at full
                                    // size for a thumbnail.
                                    sourceSize.width: 512
                                    sourceSize.height: 512
                                    source: previewPane.showsImage ? Model.pathToUrl(previewPane.entry.path) : ""
                                    visible: previewPane.showsImage && status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !previewImage.visible
                                    text: previewPane.entry ? Model.glyphFor(previewPane.entry.name, previewPane.entry.isDir) : ""
                                    color: previewPane.entry && previewPane.entry.isDir ? pickerRoot.theme.accent : pickerRoot.theme.textMuted
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: pickerRoot.theme.fontPx(3)
                                }
                            }

                            StyledText {
                                theme: pickerRoot.theme

                                width: parent.width
                                text: previewPane.entry ? previewPane.entry.name : ""
                                font.weight: Font.DemiBold
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            StyledText {
                                theme: pickerRoot.theme
                                role: StyledText.Caption
                                mono: true
                                muted: true

                                width: parent.width
                                visible: text !== ""
                                text: {
                                    const e = previewPane.entry;
                                    if (!e)
                                        return "";
                                    if (e.isDir)
                                        return "Folder";
                                    const ext = Model.extensionOf(e.name);
                                    return (ext !== "" ? ext.toUpperCase() + " · " : "") + Model.formatSize(e.size);
                                }
                                elide: Text.ElideRight
                            }

                            StyledText {
                                theme: pickerRoot.theme
                                role: StyledText.Caption
                                mono: true
                                muted: true

                                width: parent.width
                                visible: text !== ""
                                text: previewPane.entry ? Model.formatTime(previewPane.entry.modified, pickerRoot.nowMs) : ""
                            }
                        }
                    }

                    StyledText {
                        theme: pickerRoot.theme
                        muted: true

                        anchors.centerIn: listView
                        visible: pickerRoot.entries.length === 0
                        text: pickerRoot.query !== "" && !pickerRoot.saving ? "Nothing matches “" + pickerRoot.query + "”" : "Empty folder"
                    }

                    // ---------------------------------------------- footer
                    Item {
                        id: footer

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: acceptButton.height

                        StyledText {
                            theme: pickerRoot.theme
                            role: StyledText.Caption

                            anchors.left: parent.left
                            anchors.right: buttons.left
                            anchors.rightMargin: pickerRoot.theme.space(3)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: {
                                if (pickerRoot.fieldMode === "path")
                                    return "type a path · ~ and relative work · esc cancels";
                                if (pickerRoot.fieldMode === "newfolder")
                                    return "type the folder name · enter creates · esc cancels";
                                if (pickerRoot.overwritePending)
                                    return "“" + pickerRoot.query.trim() + "” exists — enter again replaces it, esc keeps it";
                                if (pickerRoot.multiple && pickerRoot.selectionCount > 0)
                                    return pickerRoot.selectionCount + " selected · shift extends · ctrl+enter accepts";
                                if (pickerRoot.saving)
                                    return "edit the name · enter saves · alt+← → walks folders";
                                if (pickerRoot.multiple)
                                    return "ctrl/shift+click selects · ctrl+a all · ctrl+enter accepts";
                                return "type to filter · ctrl+l path · ctrl+d pins · ctrl+h hidden";
                            }
                            color: pickerRoot.overwritePending ? pickerRoot.theme.warn : pickerRoot.theme.textMuted
                        }

                        Row {
                            id: buttons
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: pickerRoot.theme.space(2)

                            PickerButton {
                                label: "New folder"
                                visible: pickerRoot.saving || pickerRoot.directoryMode
                                onActivated: {
                                    pickerRoot.fieldMode = "newfolder";
                                    pickerRoot.newFolderName = "";
                                }
                            }

                            PickerButton {
                                label: "Cancel"
                                onActivated: pickerRoot.cancel()
                            }

                            PickerButton {
                                id: acceptButton
                                label: pickerRoot.overwritePending ? "Overwrite" : pickerRoot.acceptLabel
                                primary: true
                                enabled: pickerRoot.acceptable
                                onActivated: pickerRoot.accept()
                            }
                        }
                    }
                }
            }
        }
    }

    component SortHeader: Text {
        id: sortHeader

        property string field: ""
        property string label: ""

        readonly property bool active: pickerRoot.sortField === field

        text: label + (active ? (pickerRoot.sortReversed ? "  ↓" : "  ↑") : "")
        color: active || sortHover.hovered ? pickerRoot.theme.textPrimary : pickerRoot.theme.textMuted
        font.family: pickerRoot.theme.fontUi
        font.pixelSize: pickerRoot.theme.fontPx(0.75)
        font.weight: active ? Font.DemiBold : Font.Normal

        HoverHandler {
            id: sortHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: pickerRoot.setSort(sortHeader.field)
        }
    }

    component PickerButton: Rectangle {
        id: button

        property string label: ""
        property bool primary: false

        signal activated

        implicitWidth: buttonLabel.implicitWidth + pickerRoot.theme.space(8)
        implicitHeight: pickerRoot.theme.space(9)
        radius: pickerRoot.theme.radius(0.75)
        opacity: button.enabled ? 1 : 0.45
        color: {
            if (button.primary)
                return buttonHover.hovered && button.enabled ? pickerRoot.theme.alpha(pickerRoot.theme.accent, 0.85) : pickerRoot.theme.accent;
            return buttonHover.hovered ? pickerRoot.theme.alpha(pickerRoot.theme.textPrimary, 0.1) : pickerRoot.theme.surface2;
        }
        border.width: pickerRoot.theme.borderWidth
        border.color: button.primary ? "transparent" : pickerRoot.theme.surface3

        StyledText {
            id: buttonLabel
            theme: pickerRoot.theme
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? pickerRoot.theme.textOnAccent : pickerRoot.theme.textPrimary
            font.weight: button.primary ? Font.DemiBold : Font.Normal
        }

        HoverHandler {
            id: buttonHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: button.activated()
        }
    }
}

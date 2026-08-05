import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "FilePickerModel.js" as Model

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
    property int cursor: 0
    property int filterIndex: 0
    property bool showHidden: false
    // path -> true, for the multi-select case.
    property var selection: ({})
    property int selectionCount: 0
    property var entries: []
    property double nowMs: Date.now()

    readonly property var crumbs: Model.crumbsFor(currentPath, home)
    readonly property var currentEntry: cursor >= 0 && cursor < entries.length ? entries[cursor] : null

    // ------------------------------------------------------------- geometry
    readonly property int cardMargin: theme.space(4)
    readonly property int rowHeight: theme.space(9)
    readonly property int cardWidth: panel.width > 0 ? Math.min(theme.space(230), panel.width - theme.space(16)) : theme.space(230)
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
        currentPath = startPath !== "" ? startPath : home;
        query = saving ? String(req.name || "") : "";
        filterIndex = Number(req.filterIndex || 0);
        selection = ({});
        selectionCount = 0;
        cursor = 0;
        nowMs = Date.now();
        opened = true;
        rebuild();
    }

    // Answer and move on. `paths` empty means cancelled.
    function finish(paths) {
        const req = request;
        if (!req)
            return;
        const chosen = paths || [];
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
    }

    onQueryChanged: rebuild()
    onFilterIndexChanged: rebuild()
    onShowHiddenChanged: rebuild()

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
        entries = rows;
        if (cursor >= rows.length)
            cursor = Math.max(0, rows.length - 1);
        if (cursor < 0)
            cursor = 0;
    }

    // ----------------------------------------------------------- navigation
    function enter(path) {
        currentPath = String(path || home);
        cursor = 0;
        if (!saving)
            query = "";
        listView.positionViewAtBeginning();
    }

    function goUp() {
        const parent = Model.parentOf(currentPath);
        const from = currentPath;
        enter(parent);
        // Land the cursor on the folder we just left, the way every file
        // manager does — rebuilt asynchronously, so after the model settles.
        cursorRestore.target = Model.baseName(from);
        cursorRestore.restart();
    }

    function move(delta) {
        if (entries.length === 0)
            return;
        cursor = Math.max(0, Math.min(entries.length - 1, cursor + delta));
        listView.positionViewAtIndex(cursor, ListView.Contain);
    }

    function moveTo(index) {
        if (entries.length === 0)
            return;
        cursor = Math.max(0, Math.min(entries.length - 1, index));
        listView.positionViewAtIndex(cursor, ListView.Contain);
    }

    function toggleSelection(entry) {
        if (!multiple || !entry || entry.isDir !== directoryMode)
            return;
        const next = {};
        for (const key in selection)
            next[key] = selection[key];
        if (next[entry.path])
            delete next[entry.path];
        else
            next[entry.path] = true;
        selection = next;
        let n = 0;
        for (const k in next)
            n += 1;
        selectionCount = n;
    }

    function selectedPaths() {
        const paths = [];
        for (const key in selection)
            paths.push(key);
        paths.sort();
        return paths;
    }

    // Enter: descend into a folder, otherwise take what is under the cursor.
    function activate() {
        const entry = currentEntry;
        if (saving) {
            acceptSave();
            return;
        }
        if (entry && entry.isDir && !directoryMode) {
            enter(entry.path);
            return;
        }
        if (entry && entry.isDir && directoryMode) {
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

    function acceptSave() {
        const name = String(query || "").trim();
        if (name === "")
            return;
        if (name.indexOf("/") === 0) {
            finish([name]);
            return;
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

    Timer {
        id: cursorRestore
        property string target: ""
        interval: 60
        onTriggered: {
            for (let i = 0; i < pickerRoot.entries.length; i++) {
                if (pickerRoot.entries[i].name === cursorRestore.target) {
                    pickerRoot.moveTo(i);
                    return;
                }
            }
        }
    }

    // ---------------------------------------------------------------- window
    PanelWindow {
        id: panel

        visible: pickerRoot.opened
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qshell-filepicker"
        WlrLayershell.keyboardFocus: pickerRoot.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.5)

            MouseArea {
                anchors.fill: parent
                onClicked: pickerRoot.cancel()
            }
        }

        Rectangle {
            id: card

            anchors.centerIn: parent
            width: pickerRoot.cardWidth
            height: pickerRoot.cardHeight
            radius: pickerRoot.theme.radius(1.5)
            color: pickerRoot.theme.surface1
            border.width: pickerRoot.theme.borderWidth
            border.color: pickerRoot.theme.surface3

            opacity: pickerRoot.opened ? 1 : 0
            scale: pickerRoot.opened ? 1 : 0.96
            Behavior on opacity {
                NumberAnimation {
                    duration: pickerRoot.theme.time(0.8)
                    easing.type: pickerRoot.theme.easing
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: pickerRoot.theme.time(0.8)
                    easing.type: pickerRoot.theme.easing
                }
            }

            MouseArea {
                // Swallow clicks so they don't fall through to the scrim.
                anchors.fill: parent
            }

            Item {
                id: keyCatcher

                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    const alt = (event.modifiers & Qt.AltModifier) !== 0;

                    if (event.key === Qt.Key_Escape) {
                        if (!pickerRoot.saving && pickerRoot.query !== "")
                            pickerRoot.query = "";
                        else
                            pickerRoot.cancel();
                    } else if (event.key === Qt.Key_Backspace) {
                        if (pickerRoot.query !== "")
                            pickerRoot.query = ctrl ? pickerRoot.query.replace(/\s+$/, "").replace(/\S+$/, "") : pickerRoot.query.slice(0, -1);
                        else
                            pickerRoot.goUp();
                    } else if (ctrl && event.key === Qt.Key_U) {
                        pickerRoot.query = "";
                    } else if (ctrl && event.key === Qt.Key_H) {
                        pickerRoot.showHidden = !pickerRoot.showHidden;
                    } else if (event.key === Qt.Key_Up) {
                        pickerRoot.move(-1);
                    } else if (event.key === Qt.Key_Down) {
                        pickerRoot.move(1);
                    } else if (event.key === Qt.Key_PageUp) {
                        pickerRoot.move(-Math.max(1, Math.floor(listView.height / pickerRoot.rowHeight)));
                    } else if (event.key === Qt.Key_PageDown) {
                        pickerRoot.move(Math.max(1, Math.floor(listView.height / pickerRoot.rowHeight)));
                    } else if (event.key === Qt.Key_Home) {
                        pickerRoot.moveTo(0);
                    } else if (event.key === Qt.Key_End) {
                        pickerRoot.moveTo(pickerRoot.entries.length - 1);
                    } else if (event.key === Qt.Key_Left || (alt && event.key === Qt.Key_Up)) {
                        pickerRoot.goUp();
                    } else if (event.key === Qt.Key_Right) {
                        if (pickerRoot.currentEntry && pickerRoot.currentEntry.isDir)
                            pickerRoot.enter(pickerRoot.currentEntry.path);
                    } else if (event.key === Qt.Key_Tab) {
                        if (pickerRoot.filters.length > 1)
                            pickerRoot.filterIndex = (pickerRoot.filterIndex + 1) % pickerRoot.filters.length;
                    } else if (ctrl && event.key === Qt.Key_Space) {
                        pickerRoot.toggleSelection(pickerRoot.currentEntry);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (ctrl)
                            pickerRoot.accept();
                        else
                            pickerRoot.activate();
                    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                        pickerRoot.query = pickerRoot.query + event.text;
                        if (!pickerRoot.saving)
                            pickerRoot.cursor = 0;
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: pickerRoot.cardMargin
                    spacing: pickerRoot.theme.space(3)

                    // ------------------------------------------------ header
                    Item {
                        width: parent.width
                        height: titleLabel.implicitHeight

                        Text {
                            id: titleLabel
                            anchors.left: parent.left
                            anchors.right: modeLabel.left
                            anchors.rightMargin: pickerRoot.theme.space(3)
                            text: pickerRoot.title
                            color: pickerRoot.theme.textPrimary
                            font.family: pickerRoot.theme.fontUi
                            font.pixelSize: pickerRoot.theme.fontPx(1.083)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            id: modeLabel
                            anchors.right: parent.right
                            anchors.verticalCenter: titleLabel.verticalCenter
                            text: pickerRoot.queue.length > 1 ? pickerRoot.queue.length - 1 + " waiting" : (pickerRoot.multiple ? "MULTIPLE" : "")
                            visible: text !== ""
                            color: pickerRoot.theme.textMuted
                            font.family: pickerRoot.theme.fontMono
                            font.pixelSize: pickerRoot.theme.fontPx(0.75)
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

                                    Text {
                                        visible: index > 0
                                        text: "  ›  "
                                        color: pickerRoot.theme.textMuted
                                        font.family: pickerRoot.theme.fontUi
                                        font.pixelSize: pickerRoot.theme.fontPx(0.917)
                                    }

                                    Text {
                                        text: modelData.label
                                        color: index === pickerRoot.crumbs.length - 1 ? pickerRoot.theme.textPrimary : pickerRoot.theme.textMuted
                                        font.family: pickerRoot.theme.fontUi
                                        font.pixelSize: pickerRoot.theme.fontPx(0.917)

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
                        border.color: pickerRoot.query !== "" ? pickerRoot.theme.accent : pickerRoot.theme.surface3

                        Text {
                            anchors.left: parent.left
                            anchors.right: fieldHint.left
                            anchors.leftMargin: pickerRoot.theme.space(3)
                            anchors.rightMargin: pickerRoot.theme.space(2)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideLeft
                            text: pickerRoot.query !== "" ? pickerRoot.query : (pickerRoot.saving ? "file name" : "filter")
                            color: pickerRoot.query !== "" ? pickerRoot.theme.textPrimary : pickerRoot.theme.textMuted
                            font.family: pickerRoot.saving ? pickerRoot.theme.fontMono : pickerRoot.theme.fontUi
                            font.pixelSize: pickerRoot.theme.fontPx(1.0)
                        }

                        Text {
                            id: fieldHint
                            anchors.right: parent.right
                            anchors.rightMargin: pickerRoot.theme.space(3)
                            anchors.verticalCenter: parent.verticalCenter
                            text: pickerRoot.activeFilter ? String(pickerRoot.activeFilter.name || "") + (pickerRoot.filters.length > 1 ? "  ⇥" : "") : ""
                            visible: text !== ""
                            color: pickerRoot.theme.textMuted
                            font.family: pickerRoot.theme.fontUi
                            font.pixelSize: pickerRoot.theme.fontPx(0.833)
                        }
                    }

                    // -------------------------------------------------- list
                    Rectangle {
                        width: parent.width
                        height: parent.height - y
                        color: "transparent"

                        ListView {
                            id: listView

                            anchors.fill: parent
                            anchors.bottomMargin: footer.height + pickerRoot.theme.space(3)
                            clip: true
                            model: pickerRoot.entries
                            currentIndex: pickerRoot.cursor
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: row

                                required property var modelData
                                required property int index

                                width: listView.width
                                height: pickerRoot.rowHeight
                                radius: pickerRoot.theme.radius(0.75)
                                color: index === pickerRoot.cursor ? pickerRoot.theme.alpha(pickerRoot.theme.accent, 0.18) : (rowHover.hovered ? pickerRoot.theme.alpha(pickerRoot.theme.textPrimary, 0.06) : "transparent")

                                readonly property bool picked: pickerRoot.selection[modelData.path] === true

                                HoverHandler {
                                    id: rowHover
                                    cursorShape: Qt.PointingHandCursor
                                    onHoveredChanged: if (hovered)
                                        pickerRoot.moveTo(row.index)
                                }

                                TapHandler {
                                    onTapped: {
                                        pickerRoot.moveTo(row.index);
                                        pickerRoot.activate();
                                    }
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
                                    text: row.picked ? "󰄲" : "󰄱"
                                    color: row.picked ? pickerRoot.theme.accent : pickerRoot.theme.textMuted
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: pickerRoot.theme.fontPx(1.0)

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -pickerRoot.theme.space(1)
                                        onClicked: {
                                            pickerRoot.moveTo(row.index);
                                            pickerRoot.toggleSelection(row.modelData);
                                        }
                                    }
                                }

                                Text {
                                    id: rowTime
                                    anchors.right: pickerRoot.multiple ? rowTick.left : parent.right
                                    anchors.rightMargin: pickerRoot.theme.space(3)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Model.formatTime(row.modelData.modified, pickerRoot.nowMs)
                                    color: pickerRoot.theme.textMuted
                                    font.family: pickerRoot.theme.fontMono
                                    font.pixelSize: pickerRoot.theme.fontPx(0.75)
                                }

                                Text {
                                    id: rowSize
                                    anchors.right: rowTime.left
                                    anchors.rightMargin: pickerRoot.theme.space(3)
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    width: pickerRoot.theme.space(16)
                                    text: row.modelData.isDir ? "" : Model.formatSize(row.modelData.size)
                                    color: pickerRoot.theme.textMuted
                                    font.family: pickerRoot.theme.fontMono
                                    font.pixelSize: pickerRoot.theme.fontPx(0.75)
                                }

                                Text {
                                    anchors.left: rowGlyph.right
                                    anchors.leftMargin: pickerRoot.theme.space(3)
                                    anchors.right: rowSize.left
                                    anchors.rightMargin: pickerRoot.theme.space(3)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.name
                                    color: pickerRoot.theme.textPrimary
                                    font.family: pickerRoot.theme.fontUi
                                    font.pixelSize: pickerRoot.theme.fontPx(0.917)
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: listView
                            visible: pickerRoot.entries.length === 0
                            text: pickerRoot.query !== "" && !pickerRoot.saving ? "Nothing matches “" + pickerRoot.query + "”" : "Empty folder"
                            color: pickerRoot.theme.textMuted
                            font.family: pickerRoot.theme.fontUi
                            font.pixelSize: pickerRoot.theme.fontPx(0.917)
                        }

                        // ---------------------------------------------- footer
                        Item {
                            id: footer

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: acceptButton.height

                            Text {
                                anchors.left: parent.left
                                anchors.right: buttons.left
                                anchors.rightMargin: pickerRoot.theme.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: {
                                    if (pickerRoot.multiple && pickerRoot.selectionCount > 0)
                                        return pickerRoot.selectionCount + " selected · ctrl+space toggles · ctrl+enter accepts";
                                    if (pickerRoot.saving)
                                        return "type the name · enter saves · ctrl+h hidden";
                                    if (pickerRoot.multiple)
                                        return "ctrl+space selects · ctrl+enter accepts · ctrl+h hidden";
                                    return "type to filter · ← → walks folders · ctrl+h hidden";
                                }
                                color: pickerRoot.theme.textMuted
                                font.family: pickerRoot.theme.fontUi
                                font.pixelSize: pickerRoot.theme.fontPx(0.75)
                            }

                            Row {
                                id: buttons
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: pickerRoot.theme.space(2)

                                PickerButton {
                                    label: "Cancel"
                                    onActivated: pickerRoot.cancel()
                                }

                                PickerButton {
                                    id: acceptButton
                                    label: pickerRoot.acceptLabel
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

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? pickerRoot.theme.textOnAccent : pickerRoot.theme.textPrimary
            font.family: pickerRoot.theme.fontUi
            font.pixelSize: pickerRoot.theme.fontPx(0.917)
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

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../components"
import "ClipboardHistory.js" as ClipboardHistory

// Clipboard history: a persistent capture watcher plus an overlay picker.
// Ported from omarchy's clipboard plugin (CREDITS.md) — their capture
// mechanism (bin/clipboard-capture), their history semantics
// (ClipboardHistory.js) and their picker layout (query line over a split of
// entry list and full preview, with the same key model). The chrome is our
// launcher/menu/emoji language: scrim, surface1 card, accent cursor fill.
//
// Two halves with different lifetimes:
//   * The watcher and the history file are EAGER — nothing is recorded if the
//     capture only starts when the picker is first summoned. This is the one
//     long-lived child process in the shell; wl-paste --watch blocks on the
//     Wayland protocol, so it costs nothing until a selection changes.
//   * The picker window is LazyLoader-gated and does not exist until first
//     summoned.
//
// Selection is upstream's: Enter copies the entry AND puts it into the focused
// window, Shift+Enter only copies, Alt+Enter opens it (bin/clipboard-open —
// URL to browser, text to editor, image to viewer). The first two go
// through `bin/clipboard-paste`, our
// merge of their omarchy-clipboard-paste-text and -paste-file, which takes the
// history index rather than the content — clipboard entries have no business
// on argv. The delivery differs from their bare `wtype -M shift -k Insert`,
// which pastes the PRIMARY selection in foot and nothing at all in GTK3 apps;
// the script documents what was measured and what it does instead.
Scope {
    id: clipboardRoot

    required property var theme

    property bool opened: false
    property bool everOpened: false
    property string filterText: ""
    property int selectedIndex: 0
    // False before anything has moved the cursor: matches upstream, where the
    // list draws no selection until a key or the mouse picks a row.
    property bool cursorActive: false
    property bool clearConfirmOpen: false
    property int clearConfirmIndex: 1
    property var history: []
    // The watcher starts eagerly and wl-paste fires once on start, so its
    // first entry can beat the async FileView load of history.json. Merging
    // that entry into the still-empty history and saving would truncate the
    // on-disk store — buffer until the load (or its failure) has settled.
    property bool historyLoaded: false
    property var pendingEntries: []
    // Set while the shell is tearing down, so the watcher's dying breath does
    // not arm the restart timer.
    property bool shuttingDown: false

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"
    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/qshell/clipboard";
    }
    // Upstream's cap: 300 entries kept on disk, 50 rows shown at a time.
    readonly property int historyLimit: 300
    readonly property int displayLimit: 50

    // ------------------------------------------------------------ geometry
    readonly property int cardMargin: theme.space(4)
    readonly property int headerHeight: theme.space(10)
    readonly property int contentSpacing: theme.space(3)
    readonly property int rowHeight: theme.space(12)

    // ---------------------------------------------------------- open/close
    function show() {
        everOpened = true;
        filterText = "";
        selectedIndex = 0;
        cursorActive = true;
        clearConfirmOpen = false;
        opened = true;
        rebuildDisplay();
    }

    function hide() {
        opened = false;
        filterText = "";
        clearConfirmOpen = false;
    }

    function toggle() {
        if (opened)
            hide();
        else
            show();
    }

    // -------------------------------------------------------------- store
    function loadHistory(raw) {
        history = ClipboardHistory.parseHistory(raw);
        if (!historyLoaded) {
            historyLoaded = true;
            const buffered = pendingEntries;
            pendingEntries = [];
            for (let i = 0; i < buffered.length; i++)
                history = ClipboardHistory.addEntry(history, buffered[i], historyLimit);
            if (buffered.length > 0)
                saveHistory();
        }
        if (opened)
            rebuildDisplay();
    }

    function saveHistory() {
        historyFile.setText(JSON.stringify(history.slice(0, historyLimit), null, 2) + "\n");
    }

    function addClipboardJson(line) {
        const entry = ClipboardHistory.parseEntryJson(line);
        if (!entry)
            return;
        if (!historyLoaded) {
            pendingEntries.push(entry);
            return;
        }
        history = ClipboardHistory.addEntry(history, entry, historyLimit);
        saveHistory();
        if (opened)
            rebuildDisplay();
    }

    function removeDisplayIndex(index) {
        if (index < 0 || index >= displayModel.count)
            return;

        history = ClipboardHistory.removeEntryAt(history, displayModel.get(index).historyIndex);
        saveHistory();

        // Keep the cursor where the eye is: on the row that slid up into the
        // deleted one, or on the new last row when the tail was deleted.
        if (displayModel.count <= 1) {
            selectedIndex = 0;
            cursorActive = false;
        } else if (selectedIndex >= displayModel.count - 1) {
            selectedIndex = displayModel.count - 2;
        }
        rebuildDisplay();
    }

    function requestClearHistory() {
        if (history.length === 0)
            return;
        clearConfirmIndex = 1;
        clearConfirmOpen = true;
    }

    function confirmClearHistory() {
        history = ClipboardHistory.clearHistory();
        saveHistory();
        selectedIndex = 0;
        cursorActive = false;
        clearConfirmOpen = false;
        rebuildDisplay();
    }

    // ------------------------------------------------------------- display
    ListModel {
        id: displayModel
    }

    function fileUrl(path) {
        return path ? "file://" + encodeURI(String(path)) : "";
    }

    function rebuildDisplay() {
        const rows = ClipboardHistory.displayRows(history, filterText, displayLimit);

        displayModel.clear();
        for (let i = 0; i < rows.length; i++)
            displayModel.append({
                entryType: rows[i].entryType,
                fullText: rows[i].fullText,
                previewText: rows[i].previewText,
                previewImage: fileUrl(rows[i].previewImage),
                path: rows[i].path,
                mime: rows[i].mime,
                historyIndex: rows[i].index
            });

        if (displayModel.count === 0)
            selectedIndex = 0;
        else if (selectedIndex >= displayModel.count)
            selectedIndex = displayModel.count - 1;
        else if (selectedIndex < 0)
            selectedIndex = 0;

        Qt.callLater(() => {
            if (pickerLoader.item && displayModel.count > 0)
                pickerLoader.item.positionAt(selectedIndex);
        });
    }

    function setFilter(next) {
        filterText = next;
        selectedIndex = 0;
        cursorActive = true;
        rebuildDisplay();
    }

    // ---------------------------------------------------------- navigation
    // Upstream's rule: the first press with no cursor parks on the first (or
    // last, moving backwards) row instead of stepping.
    function select(delta) {
        if (displayModel.count === 0)
            return;
        if (!cursorActive) {
            cursorActive = true;
            selectedIndex = delta < 0 ? displayModel.count - 1 : 0;
        } else {
            selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
        }
        if (pickerLoader.item)
            pickerLoader.item.positionAt(selectedIndex);
    }

    function selectAbsolute(index) {
        if (displayModel.count === 0)
            return;
        cursorActive = true;
        selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1));
        if (pickerLoader.item)
            pickerLoader.item.positionAt(selectedIndex);
    }

    // ------------------------------------------------------------ activate
    // Enter: copy the entry and put it into the focused window. Closing first
    // is upstream's order and it is load-bearing — the helper waits out the
    // keyboard handover, and it can only reach the application once this layer
    // surface has let go.
    function activateIndex(index) {
        if (index < 0 || index >= displayModel.count)
            return;
        const row = displayModel.get(index);
        hide();
        if (row.entryType === "image" || row.fullText)
            Quickshell.execDetached([binDir + "clipboard-paste", "--history-index", String(row.historyIndex)]);
    }

    // Alt+Enter: open the entry instead of pasting it — upstream's third
    // Enter (their omarchy-clipboard-open), URL to browser, text to a scratch
    // file in an editor, image to the viewer.
    function openIndex(index) {
        if (index < 0 || index >= displayModel.count)
            return;
        const row = displayModel.get(index);
        hide();
        if (row.entryType === "image" || row.fullText)
            Quickshell.execDetached([binDir + "clipboard-open", "--history-index", String(row.historyIndex)]);
    }

    // Shift+Enter: copy only, upstream's second Enter. The toast is ours —
    // with nothing typed, a picker that just closes looks like it did nothing.
    function copyIndex(index) {
        if (index < 0 || index >= displayModel.count)
            return;
        const row = displayModel.get(index);
        hide();
        if (row.entryType !== "image" && !row.fullText)
            return;
        Quickshell.execDetached([binDir + "clipboard-paste", "--copy-only", "--history-index", String(row.historyIndex)]);
        Quickshell.execDetached(["notify-send", "-a", "qshell", "-t", "2000", row.entryType === "image" ? "Copied image" : "Copied to clipboard", "Paste with Ctrl+V"]);
    }

    // -------------------------------------------------------------- capture
    FileView {
        id: historyFile
        path: clipboardRoot.stateDir + "/history.json"
        watchChanges: true
        // The picker is the only writer, and it writes through a temp file +
        // rename so a reader never sees a half-written history.
        atomicWrites: true
        printErrors: false
        onLoaded: clipboardRoot.loadHistory(text())
        onLoadFailed: clipboardRoot.loadHistory("[]")
        onFileChanged: reload()
        onSaveFailed: error => console.warn("Clipboard: history write failed:", error)
    }

    // The one long-lived child process in the shell. `clipboard-capture watch`
    // owns the two wl-paste watchers (text and image/png) and prints one JSON
    // entry per selection; wl-paste fires once on start too, so whatever was
    // already on the clipboard is picked up without a separate snapshot run.
    //
    // setpriv --pdeathsig is upstream's trick and it is load-bearing: quickshell
    // does NOT signal this child when the shell exits (verified — `pkill -x qs`
    // left the whole watcher tree running), so without it every restart strands
    // a watcher holding a dead stdout pipe. The kernel signals the script
    // instead, and the script's own TERM trap takes the two wl-paste children
    // down with it.
    Process {
        id: watchProc
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", clipboardRoot.binDir + "clipboard-capture", "watch"]
        stdout: SplitParser {
            onRead: data => clipboardRoot.addClipboardJson(data)
        }
        // A dead watcher takes the history with it silently — copying still
        // works, the picker still opens, the old entries are all still there,
        // and nothing new is ever recorded. Bring it back instead.
        onExited: (code, status) => {
            if (!clipboardRoot.shuttingDown)
                watchRestartTimer.restart();
        }
    }

    Component.onDestruction: clipboardRoot.shuttingDown = true

    Timer {
        id: watchRestartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!watchProc.running)
                watchProc.running = true;
        }
    }

    // --------------------------------------------------------------- picker
    // Residency: the picker tree (rows, thumbnails, the preview pane's
    // decoded screenshots) releases once it has stayed closed for the grace
    // period — dropping everOpened deactivates the LazyLoader below, and the
    // next show() re-creates it through the exact first-open path. The
    // capture watcher above is deliberately outside this: it must run for
    // the shell's whole life. One-shot, armed only by a close, cancelled by
    // a reopen.
    Timer {
        id: pickerReleaseTimer
        interval: 45000
        repeat: false
        onTriggered: {
            if (!clipboardRoot.opened)
                clipboardRoot.everOpened = false;
        }
    }

    onOpenedChanged: {
        if (opened)
            pickerReleaseTimer.stop();
        else if (everOpened)
            pickerReleaseTimer.restart();
    }

    LazyLoader {
        id: pickerLoader
        active: clipboardRoot.everOpened

        component: OverlaySurface {
            id: panel

            // Upstream clamps the card to the screen; a small display gets the
            // margin back rather than a card hanging off the edge. The panel
            // measures 0 before it is first mapped, hence the guards.
            readonly property int computedCardWidth: panel.width > 0 ? Math.min(clipboardRoot.theme.space(190), panel.width - clipboardRoot.theme.space(8) * 2) : clipboardRoot.theme.space(190)
            readonly property int computedCardHeight: panel.height > 0 ? Math.min(clipboardRoot.theme.space(130), panel.height - clipboardRoot.theme.space(8) * 2) : clipboardRoot.theme.space(130)

            function positionAt(index) {
                list.positionViewAtIndex(index, ListView.Contain);
            }

            theme: clipboardRoot.theme
            opened: clipboardRoot.opened
            namespace: "qshell-clipboard"
            cardWidth: computedCardWidth
            cardHeight: computedCardHeight
            onDismissed: clipboardRoot.hide()

            onVisibleChanged: if (visible)
                Qt.callLater(() => keyCatcher.forceActiveFocus())

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true

                // Typing owns the keyboard — every printable key is query
                // text, so navigation lives on the arrows, the page keys
                // and Delete.
                Keys.onPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

                    if (clipboardRoot.clearConfirmOpen) {
                        if (event.key === Qt.Key_Escape)
                            clipboardRoot.clearConfirmOpen = false;
                        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
                            clipboardRoot.clearConfirmIndex = clipboardRoot.clearConfirmIndex === 0 ? 1 : 0;
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (clipboardRoot.clearConfirmIndex === 1)
                                clipboardRoot.confirmClearHistory();
                            else
                                clipboardRoot.clearConfirmOpen = false;
                        } else {
                            return;
                        }
                        event.accepted = true;
                        return;
                    }

                    if (event.key === Qt.Key_Escape) {
                        if (clipboardRoot.filterText)
                            clipboardRoot.setFilter("");
                        else
                            clipboardRoot.hide();
                    } else if (event.key === Qt.Key_Backspace) {
                        // Plain backspace drops a character, Ctrl+Backspace
                        // a word, Ctrl+U the lot — upstream's editsFilter.
                        if (!clipboardRoot.filterText)
                            return;
                        clipboardRoot.setFilter(ctrl ? clipboardRoot.filterText.replace(/\s+$/, "").replace(/\S+$/, "") : clipboardRoot.filterText.slice(0, -1));
                    } else if (ctrl && event.key === Qt.Key_U) {
                        clipboardRoot.setFilter("");
                    } else if (event.key === Qt.Key_Delete) {
                        if (shift)
                            clipboardRoot.requestClearHistory();
                        else
                            clipboardRoot.removeDisplayIndex(clipboardRoot.selectedIndex);
                    } else if (event.key === Qt.Key_Up) {
                        clipboardRoot.select(-1);
                    } else if (event.key === Qt.Key_Down) {
                        clipboardRoot.select(1);
                    } else if (event.key === Qt.Key_PageUp) {
                        clipboardRoot.select(-6);
                    } else if (event.key === Qt.Key_PageDown) {
                        clipboardRoot.select(6);
                    } else if (event.key === Qt.Key_Home) {
                        clipboardRoot.selectAbsolute(0);
                    } else if (event.key === Qt.Key_End) {
                        clipboardRoot.selectAbsolute(displayModel.count - 1);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (clipboardRoot.cursorActive && (event.modifiers & Qt.AltModifier))
                            clipboardRoot.openIndex(clipboardRoot.selectedIndex);
                        else if (clipboardRoot.cursorActive && shift)
                            clipboardRoot.copyIndex(clipboardRoot.selectedIndex);
                        else if (clipboardRoot.cursorActive)
                            clipboardRoot.activateIndex(clipboardRoot.selectedIndex);
                        else if (displayModel.count > 0)
                            clipboardRoot.cursorActive = true;
                    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                        clipboardRoot.setFilter(clipboardRoot.filterText + event.text);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: clipboardRoot.cardMargin
                    spacing: clipboardRoot.contentSpacing

                    // Query line in the launcher's search-field frame. Not
                    // a TextInput: the list needs the arrow keys, so the
                    // key catcher above owns every keystroke.
                    Rectangle {
                        id: queryField
                        width: parent.width
                        height: clipboardRoot.headerHeight
                        radius: clipboardRoot.theme.radius(1)
                        color: clipboardRoot.theme.surface2
                        border.width: clipboardRoot.theme.borderWidth
                        border.color: clipboardRoot.filterText ? clipboardRoot.theme.accent : clipboardRoot.theme.surface3

                        Text {
                            anchors.left: parent.left
                            anchors.right: countLabel.left
                            anchors.leftMargin: clipboardRoot.theme.space(3)
                            anchors.rightMargin: clipboardRoot.theme.space(2)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: clipboardRoot.filterText || "search clipboard"
                            color: clipboardRoot.filterText ? clipboardRoot.theme.textPrimary : clipboardRoot.theme.textMuted
                            font.family: clipboardRoot.theme.fontUi
                            font.pixelSize: clipboardRoot.theme.fontPx(1.1)
                        }

                        Text {
                            id: countLabel
                            anchors.right: parent.right
                            anchors.rightMargin: clipboardRoot.theme.space(3)
                            anchors.verticalCenter: parent.verticalCenter
                            text: displayModel.count + (clipboardRoot.filterText ? "/" + clipboardRoot.history.length : "")
                            color: clipboardRoot.theme.textMuted
                            font.family: clipboardRoot.theme.fontUi
                            font.pixelSize: clipboardRoot.theme.fontPx(0.833)
                        }
                    }

                    Item {
                        id: body
                        width: parent.width
                        height: parent.height - y - clipboardRoot.contentSpacing - footer.height

                        // Entries on the left, the selected one in full on
                        // the right — upstream's split.
                        Row {
                            anchors.fill: parent
                            spacing: 0

                            Item {
                                width: Math.round(parent.width * 0.45)
                                height: parent.height
                                clip: true

                                ListView {
                                    id: list
                                    anchors.fill: parent
                                    anchors.rightMargin: clipboardRoot.theme.space(3)
                                    clip: true
                                    model: displayModel
                                    spacing: clipboardRoot.theme.space(1)
                                    boundsBehavior: Flickable.StopAtBounds

                                    delegate: Rectangle {
                                        id: row

                                        required property int index
                                        required property string entryType
                                        required property string previewText
                                        required property string previewImage

                                        readonly property bool hasCursor: clipboardRoot.cursorActive && row.index === clipboardRoot.selectedIndex

                                        width: list.width
                                        height: clipboardRoot.rowHeight
                                        radius: clipboardRoot.theme.radius(0.75)
                                        color: row.hasCursor ? clipboardRoot.theme.alpha(clipboardRoot.theme.accent, 0.18) : "transparent"

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: {
                                                clipboardRoot.cursorActive = true;
                                                clipboardRoot.selectedIndex = row.index;
                                            }
                                            onClicked: {
                                                clipboardRoot.cursorActive = true;
                                                clipboardRoot.selectedIndex = row.index;
                                                clipboardRoot.activateIndex(row.index);
                                            }
                                        }

                                        Image {
                                            id: thumb
                                            anchors.left: parent.left
                                            anchors.leftMargin: clipboardRoot.theme.space(2)
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: row.previewImage.length > 0
                                            width: visible ? clipboardRoot.rowHeight - clipboardRoot.theme.space(4) : 0
                                            height: width
                                            source: row.previewImage
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            smooth: true
                                            // Decode at display size: the
                                            // list must not hold full-size
                                            // pixmaps for every screenshot.
                                            sourceSize.width: 96
                                            sourceSize.height: 96
                                        }

                                        Text {
                                            anchors.left: thumb.visible ? thumb.right : parent.left
                                            anchors.leftMargin: clipboardRoot.theme.space(2)
                                            anchors.right: parent.right
                                            anchors.rightMargin: clipboardRoot.theme.space(2)
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            text: row.previewText
                                            color: clipboardRoot.theme.textPrimary
                                            // Images and file drops read as
                                            // metadata, not as content.
                                            opacity: row.entryType === "text" ? 1 : 0.72
                                            font.family: clipboardRoot.theme.fontUi
                                            font.pixelSize: clipboardRoot.theme.fontPx(1.0)
                                        }
                                    }
                                }
                            }

                            Item {
                                id: previewPane
                                width: parent.width - Math.round(parent.width * 0.45)
                                height: parent.height
                                clip: true

                                readonly property var activeRow: displayModel.count > 0 && clipboardRoot.selectedIndex >= 0 && clipboardRoot.selectedIndex < displayModel.count ? displayModel.get(clipboardRoot.selectedIndex) : null

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: clipboardRoot.theme.borderWidth
                                    color: clipboardRoot.theme.alpha(clipboardRoot.theme.textPrimary, 0.2)
                                }

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: clipboardRoot.theme.space(4)
                                    visible: previewPane.activeRow && !previewPane.activeRow.previewImage
                                    text: previewPane.activeRow ? previewPane.activeRow.fullText : ""
                                    color: clipboardRoot.theme.textPrimary
                                    font.family: clipboardRoot.theme.fontMono
                                    font.pixelSize: clipboardRoot.theme.fontPx(0.917)
                                    wrapMode: Text.WrapAnywhere
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignTop
                                }

                                Image {
                                    anchors.fill: parent
                                    anchors.leftMargin: clipboardRoot.theme.space(4)
                                    visible: previewPane.activeRow && previewPane.activeRow.previewImage
                                    source: previewPane.activeRow && previewPane.activeRow.previewImage ? previewPane.activeRow.previewImage : ""
                                    fillMode: Image.PreserveAspectFit
                                    horizontalAlignment: Image.AlignLeft
                                    verticalAlignment: Image.AlignTop
                                    asynchronous: true
                                    smooth: true
                                    sourceSize.width: width
                                    sourceSize.height: height
                                }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: clipboardRoot.theme.space(2)
                            visible: displayModel.count === 0

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: "󰅌"
                                color: clipboardRoot.theme.textMuted
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: clipboardRoot.theme.fontPx(3.0)
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: clipboardRoot.history.length === 0 ? "Clipboard is empty" : "No matches for “" + clipboardRoot.filterText + "”"
                                color: clipboardRoot.theme.textMuted
                                font.family: clipboardRoot.theme.fontUi
                                font.pixelSize: clipboardRoot.theme.fontPx(1.0)
                            }
                        }
                    }

                    // Upstream has no footer; the two Enters and
                    // Shift+Delete are all worth saying out loud.
                    Text {
                        id: footer
                        width: parent.width
                        elide: Text.ElideRight
                        text: "enter paste   ·   shift+enter copy   ·   del remove   ·   shift+del clear all"
                        color: clipboardRoot.theme.textMuted
                        font.family: clipboardRoot.theme.fontUi
                        font.pixelSize: clipboardRoot.theme.fontPx(0.75)
                    }
                }

                // Clear-all confirmation, upstream's ConfirmDialog reduced
                // to the two buttons it actually uses here.
                Rectangle {
                    anchors.fill: parent
                    visible: clipboardRoot.clearConfirmOpen
                    color: clipboardRoot.theme.alpha(clipboardRoot.theme.surface0, 0.75)
                    radius: panel.cardRadius

                    MouseArea {
                        anchors.fill: parent
                        onClicked: clipboardRoot.clearConfirmOpen = false
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - clipboardRoot.theme.space(8), clipboardRoot.theme.space(90))
                        height: confirmColumn.implicitHeight + clipboardRoot.theme.space(8)
                        radius: clipboardRoot.theme.radius(1.5)
                        color: clipboardRoot.theme.surface2
                        border.width: clipboardRoot.theme.borderWidth
                        border.color: clipboardRoot.theme.surface3

                        MouseArea {
                            anchors.fill: parent
                        }

                        Column {
                            id: confirmColumn
                            anchors.centerIn: parent
                            width: parent.width - clipboardRoot.theme.space(8)
                            spacing: clipboardRoot.theme.space(4)

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: "Delete entire clipboard history?"
                                color: clipboardRoot.theme.textPrimary
                                font.family: clipboardRoot.theme.fontUi
                                font.pixelSize: clipboardRoot.theme.fontPx(1.1)
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: clipboardRoot.theme.space(3)

                                Repeater {
                                    model: ["Cancel", "Delete"]

                                    delegate: Rectangle {
                                        id: confirmButton

                                        required property int index
                                        required property string modelData

                                        readonly property bool hasCursor: clipboardRoot.clearConfirmIndex === confirmButton.index

                                        width: clipboardRoot.theme.space(26)
                                        height: clipboardRoot.theme.space(9)
                                        radius: clipboardRoot.theme.radius(0.75)
                                        color: confirmButton.hasCursor ? clipboardRoot.theme.alpha(confirmButton.index === 1 ? clipboardRoot.theme.error : clipboardRoot.theme.accent, 0.22) : "transparent"
                                        border.width: clipboardRoot.theme.borderWidth
                                        border.color: confirmButton.hasCursor ? (confirmButton.index === 1 ? clipboardRoot.theme.error : clipboardRoot.theme.accent) : clipboardRoot.theme.surface3

                                        Text {
                                            anchors.centerIn: parent
                                            text: confirmButton.modelData
                                            color: clipboardRoot.theme.textPrimary
                                            font.family: clipboardRoot.theme.fontUi
                                            font.pixelSize: clipboardRoot.theme.fontPx(1.0)
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: clipboardRoot.clearConfirmIndex = confirmButton.index
                                            onClicked: {
                                                if (confirmButton.index === 1)
                                                    clipboardRoot.confirmClearHistory();
                                                else
                                                    clipboardRoot.clearConfirmOpen = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

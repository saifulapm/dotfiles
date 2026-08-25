import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../components"

// Shelf — a dropzone for things in transit (the omarchy ledge/shelf plugin
// family; macOS Yoink). Files dragged onto the card, added from yazi or the
// launcher (`qs ipc call shelf add <path>`), or captured off the clipboard
// park here; rows drag back out into any app with the same verified
// Wayland-DnD recipe the Notes rows use (Drag.Automatic + text/uri-list,
// dropAction deliberately not consulted — see Notes.qml).
//
// Framing mirrors Notes: a fullscreen Overlay surface whose input mask is
// only the card, so everything around it clicks — and drags — straight
// through to the apps underneath. That pass-through IS the feature: a shelf
// you cannot drag out of into a visible window would be a dead end.
// Dismissal is Esc or IPC; the card sits against the right edge, vertically
// centered, where nothing else lives (NotesEdge owns the strip below the
// bar, the card floats clear of it).
//
// Text dropped or captured from the clipboard becomes a real file under
// ~/.local/state/qshell/shelf/clips/ — a shelf item must be draggable OUT
// as a file, and a string is not.
Scope {
    id: shelfRoot

    required property var theme

    property bool opened: false

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell"
    readonly property string storePath: stateDir + "/shelf.json"
    readonly property string clipsDir: stateDir + "/shelf/clips"
    readonly property int maxItems: 30

    // [{path, name, isImage}] — newest first.
    property var items: []
    property bool loaded: false

    // Where the card sits, dragged there by its header and persisted with
    // the items. -1 = the default berth (right edge, vertically centered).
    property real cardX: -1
    property real cardY: -1

    function show() {
        opened = true;
    }
    function hide() {
        opened = false;
    }
    function toggle() {
        opened = !opened;
    }

    // ------------------------------------------------------------- storage
    function saveItems() {
        storeFile.setText(JSON.stringify({
            items: items,
            x: cardX,
            y: cardY
        }, null, 2) + "\n");
    }

    readonly property FileView storeFile: FileView {
        path: shelfRoot.storePath
        printErrors: false
        onLoaded: {
            if (shelfRoot.loaded)
                return;
            shelfRoot.loaded = true;
            try {
                const parsed = JSON.parse(text());
                // Legacy stores were a bare array; the object shape carries
                // the card position too.
                const list = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.items) ? parsed.items : []);
                shelfRoot.items = list.filter(it => it && typeof it.path === "string");
                if (parsed && !Array.isArray(parsed)) {
                    if (isFinite(Number(parsed.x)))
                        shelfRoot.cardX = Number(parsed.x);
                    if (isFinite(Number(parsed.y)))
                        shelfRoot.cardY = Number(parsed.y);
                }
            } catch (e) {}
        }
        onLoadFailed: shelfRoot.loaded = true
        Component.onCompleted: reload()
    }

    // ------------------------------------------------------------- adding
    readonly property var imageExts: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg"]

    function isImagePath(path) {
        const ext = String(path).split(".").pop().toLowerCase();
        return imageExts.indexOf(ext) !== -1;
    }

    function addPath(path) {
        const p = String(path || "").trim();
        if (!p || p[0] !== "/")
            return "not an absolute path: " + p;
        const next = items.filter(it => it.path !== p);
        next.unshift({
            path: p,
            name: p.split("/").pop(),
            isImage: isImagePath(p)
        });
        items = next.slice(0, maxItems);
        saveItems();
        show();
        // The settle check doubles as add-validation: a path that does not
        // exist is swept out within a second instead of sitting as a row
        // whose thumbnail can never load (QML cannot stat, bash can).
        settleAfterDrag([p]);
        return "ok";
    }

    function addUrl(url) {
        let s = String(url || "");
        if (s.indexOf("file://") === 0)
            s = decodeURIComponent(s.substring(7));
        return addPath(s);
    }

    function removeAt(index) {
        const next = items.slice();
        next.splice(index, 1);
        items = next;
        saveItems();
    }

    function clearAll() {
        items = [];
        saveItems();
    }

    // After a drag out, look at the FILES to learn what happened —
    // Drag.onDragFinished's dropAction is IgnoreAction for every drag on
    // this stack (ledge's finding, and Notes' before it), so a carried path
    // that no longer exists was MOVED by whoever took it and its row goes.
    // The delay lets a same-filesystem move (a rename) land first.
    property var pendingSettle: []

    function settleAfterDrag(paths) {
        if (!paths || paths.length === 0)
            return;
        const queued = pendingSettle.slice();
        for (const p of paths)
            if (queued.indexOf(p) === -1)
                queued.push(p);
        pendingSettle = queued;
        settleTimer.restart();
    }

    readonly property Timer settleTimer: Timer {
        interval: 900
        onTriggered: {
            const check = shelfRoot.pendingSettle;
            shelfRoot.pendingSettle = [];
            if (check.length === 0)
                return;
            settleProc.command = ["bash", "-c", 'for p in "$@"; do [[ -e $p ]] || printf "%s\n" "$p"; done', "qshell-shelf-settle"].concat(check);
            settleProc.running = true;
        }
    }

    readonly property Process settleProc: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const gone = String(text || "").split("\n").filter(l => l.length > 0);
                if (gone.length === 0)
                    return;
                shelfRoot.items = shelfRoot.items.filter(it => gone.indexOf(it.path) === -1);
                shelfRoot.saveItems();
            }
        }
    }

    // Clipboard capture: an image selection lands as a PNG file, text as a
    // .txt — either way the shelf holds a real, draggable file. The helper
    // prints the saved path; empty output means nothing usable was held.
    // A text drop becomes a clip file like the clipboard path does.
    function addText(text) {
        const t = String(text || "");
        if (!t)
            return;
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && f="$1/clip-$(date +%s).txt" && printf "%s" "$2" >"$f" && qs ipc call shelf add "$f"', "qshell-shelf-text", clipsDir, t]);
    }

    function addClipboard() {
        if (clipProc.running)
            return "busy";
        clipProc.running = true;
        return "ok";
    }

    readonly property Process clipProc: Process {
        command: ["bash", "-c", `
            set -uo pipefail
            dir="${shelfRoot.clipsDir}"
            mkdir -p "$dir"
            types="$(wl-paste --list-types 2>/dev/null || true)"
            if grep -q '^image/png' <<<"$types"; then
                f="$dir/clip-$(date +%s).png"
                wl-paste --type image/png >"$f" 2>/dev/null && [[ -s $f ]] && printf '%s' "$f" && exit 0
                rm -f "$f"; exit 0
            fi
            text="$(wl-paste --no-newline --type text 2>/dev/null || true)"
            [[ -n $text ]] || exit 0
            f="$dir/clip-$(date +%s).txt"
            printf '%s' "$text" >"$f" && printf '%s' "$f"
        `]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const path = String(text || "").trim();
                if (path)
                    shelfRoot.addPath(path);
                else
                    Quickshell.execDetached(["notify-send", "-a", "qshell", "Shelf", "Clipboard holds nothing shelvable"]);
            }
        }
    }

    // Ctrl-click selection, keyed by path: a drag from a selected row
    // carries the whole selection (ledge's multi-drag).
    property var selectedSet: ({})

    function toggleSelected(path) {
        const next = Object.assign({}, selectedSet);
        if (next[path])
            delete next[path];
        else
            next[path] = true;
        selectedSet = next;
    }

    function clearSelection() {
        selectedSet = {};
    }

    function carriedPaths(path) {
        if (selectedSet[path]) {
            const list = items.map(it => it.path).filter(p => selectedSet[p]);
            return list.length > 0 ? list : [path];
        }
        return [path];
    }

    function uriList(paths) {
        return paths.map(pathToUri).join("\r\n") + "\r\n";
    }

    // Click = copy as file, the always-available fallback for targets that
    // take a paste but not a drop (ledge's contract).
    function copyAsFiles(paths) {
        Quickshell.execDetached(["bash", "-c", 'printf "%s" "$2" | wl-copy --type text/uri-list', "qshell-shelf-copy", "", uriList(paths)]);
        Quickshell.execDetached(["notify-send", "-a", "qshell", "-t", "3000", "Shelf", (paths.length === 1 ? "1 file" : paths.length + " files") + " copied — paste where it should land"]);
    }

    function openItem(item) {
        if (item && item.path)
            Quickshell.execDetached(["xdg-open", item.path]);
    }

    function pathToUri(path) {
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    // -------------------------------------------------------------- window
    LazyLoader {
        active: shelfRoot.opened

        PanelWindow {
            id: panelWindow

            visible: shelfRoot.opened
            mask: cardMask
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qshell-shelf"
            // NO keyboard, ever: the shelf stays open WHILE you work, and
            // any keyboard interactivity steals focus from the window under
            // it (Exclusive stole it outright; OnDemand still grabs on map
            // under niri — both measured, focused-window went null). Close
            // is the header button, the bar icon, or IPC; there is no Esc
            // because there are no keys.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Region {
                id: cardMask
                item: card
            }

            Rectangle {
                id: card

                readonly property real cardWidth: shelfRoot.theme.space(52)

                // Free-floating: the header drags it anywhere, the berth is
                // remembered. Clamped so a saved position from a bigger
                // screen cannot strand the card off-frame.
                x: {
                    const def = parent.width - width - shelfRoot.theme.space(3);
                    const want = shelfRoot.cardX >= 0 ? shelfRoot.cardX : def;
                    return Math.max(0, Math.min(want, parent.width - width));
                }
                y: {
                    const def = (parent.height - height) / 2;
                    const want = shelfRoot.cardY >= 0 ? shelfRoot.cardY : def;
                    return Math.max(0, Math.min(want, parent.height - height));
                }
                width: cardWidth
                height: Math.min(column.implicitHeight + shelfRoot.theme.space(6), parent.height - shelfRoot.theme.space(20))
                radius: shelfRoot.theme.radius(1.5)
                color: shelfRoot.theme.glass(shelfRoot.theme.panel.background)
                border.width: dropZone.containsDrag ? Math.max(2, shelfRoot.theme.panel.borderWidth) : shelfRoot.theme.panel.borderWidth
                border.color: dropZone.containsDrag ? shelfRoot.theme.accent : shelfRoot.theme.panel.border

                MouseArea {
                    anchors.fill: parent
                }

                DropArea {
                    id: dropZone
                    anchors.fill: parent
                    onDropped: drop => {
                        if (drop.hasUrls && drop.urls.length > 0) {
                            for (let i = 0; i < drop.urls.length; i++)
                                shelfRoot.addUrl(drop.urls[i]);
                            drop.accept(Qt.CopyAction);
                        } else if (drop.hasText) {
                            // Route through the clips dir so the drop is a
                            // draggable file like everything else here.
                            Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && f="$1/clip-$(date +%s).txt" && printf "%s" "$2" >"$f" && qs ipc call shelf add "$f"', "qshell-shelf-drop", shelfRoot.clipsDir, drop.text]);
                            drop.accept(Qt.CopyAction);
                        }
                    }
                }

                Column {
                    id: column
                    x: shelfRoot.theme.space(3)
                    y: shelfRoot.theme.space(3)
                    width: parent.width - shelfRoot.theme.space(6)
                    spacing: shelfRoot.theme.space(1.5)

                    Item {
                        width: parent.width
                        height: shelfRoot.theme.space(6)

                        // The header is the card's drag grip: move the shelf
                        // wherever the current work wants it; the berth is
                        // saved with the items.
                        DragHandler {
                            target: card
                            cursorShape: Qt.SizeAllCursor
                            onActiveChanged: {
                                if (active)
                                    return;
                                shelfRoot.cardX = card.x;
                                shelfRoot.cardY = card.y;
                                shelfRoot.saveItems();
                            }
                        }

                        StyledText {
                            theme: shelfRoot.theme
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Shelf"
                            color: shelfRoot.theme.panel.text
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            theme: shelfRoot.theme
                            role: StyledText.Caption
                            muted: true
                            anchors.right: clearBtn.left
                            anchors.rightMargin: shelfRoot.theme.space(2)
                            anchors.verticalCenter: parent.verticalCenter
                            text: shelfRoot.items.length > 0 ? String(shelfRoot.items.length) : ""
                        }

                        GlyphButton {
                            id: copyAllBtn
                            theme: shelfRoot.theme
                            anchors.right: clearBtn.left
                            anchors.rightMargin: shelfRoot.theme.space(1)
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "\u{F0222}" // md-file-multiple
                            visible: shelfRoot.items.length > 0
                            hint: "Copy all as files"
                            onActivated: shelfRoot.copyAsFiles(shelfRoot.items.map(it => it.path))
                        }

                        GlyphButton {
                            id: clearBtn
                            theme: shelfRoot.theme
                            anchors.right: closeBtn.left
                            anchors.rightMargin: shelfRoot.theme.space(1)
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "󰆴" // md-trash-can
                            visible: shelfRoot.items.length > 0
                            hint: "Clear the shelf"
                            onActivated: shelfRoot.clearAll()
                        }

                        GlyphButton {
                            id: closeBtn
                            theme: shelfRoot.theme
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "󰅖" // md-close
                            hint: "Hide the shelf"
                            onActivated: shelfRoot.hide()
                        }
                    }

                    StyledText {
                        theme: shelfRoot.theme
                        role: StyledText.Small
                        muted: true
                        visible: shelfRoot.items.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Drop files here, or add from the launcher.\nRows drag back out into any app."
                    }

                    Repeater {
                        model: shelfRoot.items

                        Rectangle {
                            id: row

                            required property var modelData
                            required property int index

                            readonly property bool selected: shelfRoot.selectedSet[modelData.path] === true

                            width: column.width
                            height: shelfRoot.theme.space(11)
                            radius: shelfRoot.theme.radius(1)
                            color: rowMouse.containsMouse || selected ? shelfRoot.theme.alpha(shelfRoot.theme.accent, selected ? 0.16 : 0.1) : shelfRoot.theme.alpha(shelfRoot.theme.surface2, 0.6)
                            border.width: selected ? Math.max(1, shelfRoot.theme.borderWidth) : 0
                            border.color: shelfRoot.theme.accent

                            // The Notes drag-out recipe: Automatic platform
                            // drag, uri-list + plain path. A drag from a
                            // selected row carries the whole selection.
                            Drag.dragType: Drag.Automatic
                            Drag.supportedActions: Qt.CopyAction
                            Drag.mimeData: ({
                                    "text/uri-list": shelfRoot.uriList(shelfRoot.carriedPaths(row.modelData.path)),
                                    "text/plain": row.modelData.path
                                })
                            Drag.active: rowDrag.active
                            // What happened is settled by the files, never by
                            // dropAction (IgnoreAction for every drag here).
                            Drag.onDragFinished: {
                                const carried = shelfRoot.carriedPaths(row.modelData.path);
                                if (row.selected)
                                    shelfRoot.clearSelection();
                                shelfRoot.settleAfterDrag(carried);
                            }

                            DragHandler {
                                id: rowDrag
                                target: null
                                yAxis.enabled: false
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                // Grab the drag pixmap on HOVER — the grab is
                                // asynchronous and must be done before the
                                // press that starts the drag (ledge's note).
                                onContainsMouseChanged: if (containsMouse)
                                    row.grabToImage(result => {
                                        row.Drag.imageSource = result.url;
                                    })
                                onClicked: mouse => {
                                    if (mouse.modifiers & Qt.ControlModifier)
                                        shelfRoot.toggleSelected(row.modelData.path);
                                    else
                                        shelfRoot.copyAsFiles(shelfRoot.carriedPaths(row.modelData.path));
                                }
                                onDoubleClicked: shelfRoot.openItem(row.modelData)
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.right: removeBtn.left
                                anchors.leftMargin: shelfRoot.theme.space(1.5)
                                anchors.rightMargin: shelfRoot.theme.space(1)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: shelfRoot.theme.space(2)

                                Item {
                                    width: shelfRoot.theme.space(8)
                                    height: shelfRoot.theme.space(8)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Image {
                                        anchors.fill: parent
                                        visible: row.modelData.isImage
                                        source: row.modelData.isImage ? "file://" + row.modelData.path : ""
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    OpticalGlyph {
                                        anchors.centerIn: parent
                                        visible: !row.modelData.isImage
                                        text: String(row.modelData.path).endsWith(".txt") ? "󰈙" : "󰈔"
                                        color: shelfRoot.theme.textPrimary
                                        pixelSize: shelfRoot.theme.fontPx(1.4)
                                    }
                                }

                                StyledText {
                                    theme: shelfRoot.theme
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - shelfRoot.theme.space(11)
                                    elide: Text.ElideMiddle
                                    text: row.modelData.name
                                    color: shelfRoot.theme.panel.text
                                }
                            }

                            GlyphButton {
                                id: removeBtn
                                theme: shelfRoot.theme
                                anchors.right: parent.right
                                anchors.rightMargin: shelfRoot.theme.space(1)
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "󰅖" // md-close
                                visible: rowMouse.containsMouse
                                onActivated: shelfRoot.removeAt(row.index)
                            }
                        }
                    }

                    StyledText {
                        theme: shelfRoot.theme
                        role: StyledText.Caption
                        muted: true
                        visible: shelfRoot.items.length > 0
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "drag out · click copies as file · ctrl-click selects\ndrag the header to move the card"
                    }
                }
            }
        }
    }
}

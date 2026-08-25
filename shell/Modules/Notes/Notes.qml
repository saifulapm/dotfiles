import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../../components"
import "NotesModel.js" as NotesModel

// Quick-capture notes (Copper for macOS, rebuilt for niri): a full-height
// panel floating over the right sixth of the screen — a prompt backlog and
// scratchpad that files, text and screenshots can be dropped onto, and whose
// rows drag back out into any app as a file or as text.
//
// Lifetimes: this whole module rides an evictable SurfaceLoader in shell.qml,
// so it exists only from first summon until the grace period after a close —
// idle cost is zero. The always-on half is Modules/Notes/NotesEdge.qml, the
// 1-px hot strip that wakes this module on a right-edge hover; `notes` IPC
// (toggle/show/hide/add) is the other entry point.
//
// Keyboard is Exclusive while open (the launcher/clipboard pattern): Esc and
// the capture input work the instant the panel maps, without a click first —
// niri hands an OnDemand layer the keyboard only after a click on it
// (layer_shell_on_demand_focus, niri src). Pointer input is untouched, so
// dragging a file in from a file manager works while the panel holds keys.
Scope {
    id: notesRoot

    required property var theme

    property bool opened: false
    property string filterText: ""
    property var notes: []
    // The store loads async, and an IPC `add` (or a queued summon replay) can
    // beat it — merging into a still-empty list and saving would truncate the
    // file, so early adds buffer until the load settles (Clipboard's pattern).
    property bool notesLoaded: false
    property var pendingNotes: []
    // The attachment staged in the capture input (Copper's flow): a dropped
    // file or pasted image waits here, the user types beside it, Enter
    // commits both as one note. Clipboard pastes are files this module
    // created (attachments dir), so cancelling or losing one deletes it.
    property string pendingAttachment: ""

    // Rows the delegates can append to the ListView without churn.
    signal scrollRequested

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"
    readonly property string stateDir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/qshell/notes";
    }
    readonly property string pastePrefix: stateDir + "/attachments/paste-"

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir + "/attachments"])

    // Eviction or shutdown with a pasted image still staged: the note never
    // existed, so neither should its file.
    Component.onDestruction: {
        if (stagedPasteOrphan(pendingAttachment))
            Quickshell.execDetached(["rm", "-f", pendingAttachment]);
    }

    function isPasteFile(path) {
        return String(path || "").indexOf(pastePrefix) === 0;
    }

    // A staged paste file is disposable only while NO note references it —
    // dragging a note's own attachment back onto the panel re-stages the
    // very file the note owns, and cleanup must not delete it from under
    // the note (found by the uinput self-drop test, 2026-08-13).
    function stagedPasteOrphan(path) {
        if (!isPasteFile(path))
            return false;
        for (let i = 0; i < notes.length; i++)
            if (notes[i].path === path)
                return false;
        return true;
    }

    // ---------------------------------------------------------- open/close
    function show() {
        // Re-summons no-op: the hot strip stays reachable past the card's
        // 10 px niri gap while the panel is open, and an edge hover (or a
        // drag grazing the strip) must not yank the list to the end
        // mid-read (review 2026-08-13).
        if (opened)
            return;
        opened = true;
        scrollRequested();
    }

    function hide() {
        opened = false;
        if (searchInput.text)
            searchInput.text = "";
    }

    function toggle() {
        if (opened)
            hide();
        else
            show();
    }

    // -------------------------------------------------------------- store
    function loadNotes(raw) {
        // Our own atomic write echoes back through the watcher; rebuilding on
        // it would reset the list's scroll position for nothing.
        if (notesLoaded && String(raw || "") === NotesModel.serialize(notes))
            return;
        notes = NotesModel.parseNotes(raw);
        const firstLoad = !notesLoaded;
        notesLoaded = true;
        rebuildDisplay();
        if (firstLoad) {
            const buffered = pendingNotes;
            pendingNotes = [];
            for (let i = 0; i < buffered.length; i++)
                commitEntry(buffered[i]);
        }
    }

    function persist() {
        notesFile.setText(NotesModel.serialize(notes));
    }

    function addText(text) {
        const t = String(text || "").trim();
        if (!t)
            return;
        enqueueEntry({
            text: t,
            path: ""
        });
    }

    function addFileUrl(url) {
        const path = NotesModel.urlToPath(url);
        if (!path)
            return;
        enqueueEntry({
            text: "",
            path: path
        });
    }

    // ---------------------------------------------------- attachment stage
    function stageAttachmentPath(path) {
        if (!path)
            return;
        // Replacing a pasted-but-never-committed image orphans its file.
        if (pendingAttachment !== path && stagedPasteOrphan(pendingAttachment))
            Quickshell.execDetached(["rm", "-f", pendingAttachment]);
        pendingAttachment = path;
        captureInput.forceActiveFocus();
    }

    function stageAttachmentUrl(url) {
        stageAttachmentPath(NotesModel.urlToPath(url));
    }

    function stageText(text) {
        const t = String(text || "");
        if (!t)
            return;
        captureInput.insert(captureInput.length, (captureInput.text ? "\n" : "") + t);
        captureInput.forceActiveFocus();
    }

    function cancelStagedAttachment() {
        if (stagedPasteOrphan(pendingAttachment))
            Quickshell.execDetached(["rm", "-f", pendingAttachment]);
        pendingAttachment = "";
    }

    // Enter in the capture input: text, attachment, or both become one note.
    function commitStaged(rawText) {
        const t = String(rawText || "").trim();
        if (!t && !pendingAttachment)
            return;
        enqueueEntry({
            text: t,
            path: pendingAttachment
        });
        pendingAttachment = "";
    }

    function enqueueEntry(entry) {
        if (!notesLoaded) {
            pendingNotes.push(entry);
            return;
        }
        commitEntry(entry);
    }

    function commitEntry(entry) {
        const note = NotesModel.makeNote(entry.text, entry.path);
        notes = NotesModel.addNote(notes, note);
        persist();
        const rows = NotesModel.displayRows([note], filterText);
        if (rows.length > 0) {
            displayModel.append(rows[0]);
            scrollRequested();
        }
    }

    // Toggle and remove edit the display model in place: a rebuild would
    // reset the scroll position under the pointer that just clicked.
    function toggleDone(id) {
        notes = NotesModel.toggleDone(notes, id);
        persist();
        for (let i = 0; i < displayModel.count; i++)
            if (displayModel.get(i).noteId === id) {
                displayModel.setProperty(i, "noteDone", !displayModel.get(i).noteDone);
                break;
            }
    }

    function removeNote(id) {
        // A pasted image belongs to its note; deleting the note deletes the
        // file. Dropped external files are referenced, never owned — and a
        // shared or re-staged paste file survives its note.
        const gone = NotesModel.findNote(notes, id);
        notes = NotesModel.removeNote(notes, id);
        persist();
        if (gone && pendingAttachment !== gone.path && stagedPasteOrphan(gone.path))
            Quickshell.execDetached(["rm", "-f", gone.path]);
        for (let i = 0; i < displayModel.count; i++)
            if (displayModel.get(i).noteId === id) {
                displayModel.remove(i);
                break;
            }
    }

    function setFilter(next) {
        filterText = next;
        rebuildDisplay();
    }

    // ------------------------------------------------------------- display
    ListModel {
        id: displayModel
    }

    function rebuildDisplay() {
        const rows = NotesModel.displayRows(notes, filterText);
        displayModel.clear();
        for (let i = 0; i < rows.length; i++)
            displayModel.append(rows[i]);
    }

    // Ctrl+V in the capture input runs this beside the TextEdit's own text
    // paste (the event is never accepted): an image on the clipboard lands
    // in the attachments dir and stages itself; no image, no output, and
    // the native text paste was all that happened.
    Process {
        id: pasteProbe
        command: [notesRoot.binDir + "notes-paste-image"]
        stdout: SplitParser {
            onRead: data => {
                const path = String(data).trim();
                if (path)
                    notesRoot.stageAttachmentPath(path);
            }
        }
    }

    FileView {
        id: notesFile
        path: notesRoot.stateDir + "/notes.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: notesRoot.loadNotes(text())
        onLoadFailed: notesRoot.loadNotes("")
        onFileChanged: reload()
        onSaveFailed: error => console.warn("Notes: store write failed:", error)
    }

    // -------------------------------------------------------------- window
    PanelWindow {
        id: panelWindow

        // Fullscreen over the work area, but input lives only inside the
        // card's rectangle (the mask below): everything around the panel
        // clicks straight through to the windows underneath, so other apps
        // stay usable — and draggable-from — while the panel is open.
        // Dismissal is Esc (or IPC) only; no scrim, no outside-click
        // (user-tuned 2026-08-13). Closing is a hard unmap, no exit
        // animation (same tuning: every animated exit read as lag; instant
        // never does).
        visible: notesRoot.opened || slideAnim.running
        mask: cardMask
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        // Zone 0: reserve nothing, but let the compositor keep this surface
        // out of the bar's exclusive zone — the panel spans the same work
        // area niri hands to windows, instead of covering the bar.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qshell-notes"
        WlrLayershell.keyboardFocus: notesRoot.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // niri's `gaps 10` (config.kdl layout block): the card floats with
        // exactly the margin a tiled window gets, so it reads as a sibling
        // of the windows beside it. Pinned, not theme.space-derived — a
        // density change must not drift it away from the niri value.
        readonly property int niriGap: 10
        // The card's hidden rest: fully past the window's right edge, so
        // opening and closing are true slides, not fades.
        readonly property real slideHidden: card.width + niriGap

        // Asymmetric on purpose: slide IN, instant OUT (user-tuned
        // 2026-08-13 — every animated exit read as lag).
        //
        // The entrance is kicked a beat after the window maps (see the
        // Connections below) because slideHidden is computed from a width
        // the window only has once mapped — animating off a stale width
        // would turn the first slide into a pop. Clamping `from` covers the
        // same first-map case: the card idles at a sentinel far off-screen.
        // A fade at 75 ms reads fine, but a spatial slide across a sixth of
        // the screen needs ~1.4 beats to read as motion instead of a snap.
        function runSlide() {
            slideAnim.stop();
            slideAnim.from = Math.min(cardSlide.x, slideHidden);
            slideAnim.to = 0;
            slideAnim.duration = notesRoot.theme.time(1.4);
            slideAnim.start();
        }

        Connections {
            target: notesRoot
            function onOpenedChanged() {
                if (notesRoot.opened) {
                    Qt.callLater(() => panelWindow.runSlide());
                } else {
                    // Unmap this frame; park the card off-screen so the
                    // next entrance slides from the edge again.
                    slideAnim.stop();
                    cardSlide.x = panelWindow.slideHidden;
                }
            }
        }

        NumberAnimation {
            id: slideAnim
            target: cardSlide
            property: "x"
            easing.type: notesRoot.theme.easing
        }

        // The card's resting rectangle. Anchors, not the slide transform —
        // during the entrance the input region sits at the card's final
        // place, which is fine for the ~200 ms it is in flight.
        Region {
            id: cardMask
            x: card.x
            y: card.y
            width: card.width
            height: card.height
        }

        onVisibleChanged: if (visible)
            Qt.callLater(() => captureInput.forceActiveFocus())

        CardFrost {
            theme: notesRoot.theme
            card: card
            windowWidth: panelWindow.width
            windowHeight: panelWindow.height
            offsetX: cardSlide.x
            visible: notesRoot.theme.blurActive
        }

        Rectangle {
            id: card

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: panelWindow.niriGap
            // Fixed 450 px (user ask 2026-08-13; was a sixth of the screen).
            width: 450
            radius: notesRoot.theme.radius(1.5)
            color: notesRoot.theme.glass(notesRoot.theme.surface1)
            border.width: notesRoot.theme.borderWidth
            border.color: dropZone.containsDrag ? notesRoot.theme.accent : notesRoot.theme.surface3

            transform: Translate {
                id: cardSlide
                // Sentinel far off-screen: the real hidden x depends on the
                // window's width, which is 0 until the first map.
                x: 99999
            }

            Keys.onEscapePressed: notesRoot.hide()

            // Swallow clicks so nothing falls through to the desktop.
            MouseArea {
                anchors.fill: parent
            }

            // Drops stage into the capture input (Copper's flow) instead of
            // committing: the file waits as the pending attachment, text
            // joins the input, Enter makes the note. Extra files in a
            // multi-drop can't share the single stage slot, so they commit
            // directly. The accent border above is the whole-card drop cue.
            DropArea {
                id: dropZone
                anchors.fill: parent
                onDropped: drop => {
                    if (drop.hasUrls && drop.urls.length > 0) {
                        notesRoot.stageAttachmentUrl(drop.urls[0]);
                        for (let i = 1; i < drop.urls.length; i++)
                            notesRoot.addFileUrl(drop.urls[i]);
                        drop.accept(Qt.CopyAction);
                    } else if (drop.hasText) {
                        notesRoot.stageText(drop.text);
                        drop.accept(Qt.CopyAction);
                    }
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: notesRoot.theme.space(3)

                // Search line, the clipboard picker's field frame.
                Rectangle {
                    id: searchField

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: notesRoot.theme.space(9)
                    radius: notesRoot.theme.radius(1)
                    color: notesRoot.theme.surface2
                    border.width: notesRoot.theme.borderWidth
                    border.color: searchInput.activeFocus || searchInput.text ? notesRoot.theme.accent : notesRoot.theme.surface3

                    Text {
                        id: searchGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: notesRoot.theme.space(2.5)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        color: notesRoot.theme.textMuted
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: notesRoot.theme.fontPx(1.0)
                    }

                    TextInput {
                        id: searchInput
                        anchors.left: searchGlyph.right
                        anchors.leftMargin: notesRoot.theme.space(2)
                        anchors.right: countLabel.left
                        anchors.rightMargin: notesRoot.theme.space(2)
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        color: notesRoot.theme.textPrimary
                        font.family: notesRoot.theme.fontUi
                        font.pixelSize: notesRoot.theme.fontPx(1.0)
                        selectByMouse: true
                        onTextChanged: notesRoot.setFilter(text)
                        // Esc clears an active search; empty, it bubbles to
                        // the card and hides the panel.
                        Keys.onEscapePressed: event => {
                            if (text) {
                                text = "";
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }

                        StyledText {
                            theme: notesRoot.theme
                            role: StyledText.BodyLarge
                            muted: true

                            anchors.fill: parent
                            visible: !searchInput.text
                            text: "search"
                        }
                    }

                    StyledText {
                        id: countLabel
                        theme: notesRoot.theme
                        role: StyledText.Small
                        muted: true
                        anchors.right: parent.right
                        anchors.rightMargin: notesRoot.theme.space(2.5)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length > 0
                        text: displayModel.count + "/" + NotesModel.liveNotes(notesRoot.notes).length
                    }
                }

                Text {
                    id: footer
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    elide: Text.ElideRight
                    text: "enter add   ·   esc hide   ·   drag row out"
                    color: notesRoot.theme.textMuted
                    font.family: notesRoot.theme.fontUi
                    font.pixelSize: notesRoot.theme.fontPx(0.72)
                }

                // Capture input, Copper's bottom row: a staged attachment
                // chip above the text. Grows with its content up to a cap;
                // Enter commits text + attachment as one note, Shift+Enter
                // breaks a line, Ctrl+V stages a clipboard image.
                Rectangle {
                    id: inputField

                    anchors.bottom: footer.top
                    anchors.bottomMargin: notesRoot.theme.space(2)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Math.min(inputColumn.implicitHeight + notesRoot.theme.space(4), notesRoot.theme.space(44))
                    clip: true
                    radius: notesRoot.theme.radius(1)
                    color: notesRoot.theme.surface2
                    border.width: notesRoot.theme.borderWidth
                    border.color: captureInput.activeFocus ? notesRoot.theme.accent : notesRoot.theme.surface3

                    Column {
                        id: inputColumn
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: notesRoot.theme.space(2)
                        spacing: notesRoot.theme.space(2)

                        Rectangle {
                            id: stageChip
                            visible: notesRoot.pendingAttachment !== ""
                            width: parent.width
                            height: notesRoot.theme.space(12)
                            radius: notesRoot.theme.radius(0.75)
                            color: notesRoot.theme.alpha(notesRoot.theme.surface1, 0.9)
                            border.width: notesRoot.theme.borderWidth
                            border.color: notesRoot.theme.surface3

                            ClippingRectangle {
                                id: stageThumb
                                visible: stageChip.visible && NotesModel.isImagePath(notesRoot.pendingAttachment)
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: notesRoot.theme.space(1.5)
                                width: height
                                radius: notesRoot.theme.radius(0.5)
                                color: "transparent"

                                Image {
                                    anchors.fill: parent
                                    source: stageThumb.visible ? NotesModel.pathToUri(notesRoot.pendingAttachment) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 128
                                    sourceSize.height: 128
                                }
                            }

                            Text {
                                id: stageGlyph
                                visible: stageChip.visible && !stageThumb.visible
                                anchors.left: parent.left
                                anchors.leftMargin: notesRoot.theme.space(2)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰈔"
                                color: notesRoot.theme.textMuted
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: notesRoot.theme.fontPx(1.1)
                            }

                            StyledText {
                                theme: notesRoot.theme

                                anchors.left: stageThumb.visible ? stageThumb.right : stageGlyph.right
                                anchors.leftMargin: notesRoot.theme.space(2)
                                anchors.right: stageCancel.left
                                anchors.rightMargin: notesRoot.theme.space(1.5)
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideMiddle
                                textFormat: Text.PlainText
                                text: NotesModel.baseName(notesRoot.pendingAttachment)
                            }

                            Rectangle {
                                id: stageCancel
                                anchors.right: parent.right
                                anchors.rightMargin: notesRoot.theme.space(1.5)
                                anchors.verticalCenter: parent.verticalCenter
                                width: notesRoot.theme.space(5)
                                height: width
                                radius: notesRoot.theme.radius(0.5)
                                color: stageCancelMouse.containsMouse ? notesRoot.theme.alpha(notesRoot.theme.error, 0.22) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: stageCancelMouse.containsMouse ? notesRoot.theme.error : notesRoot.theme.textMuted
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: notesRoot.theme.fontPx(0.833)
                                }

                                MouseArea {
                                    id: stageCancelMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: notesRoot.cancelStagedAttachment()
                                }
                            }
                        }

                        TextEdit {
                            id: captureInput
                            width: parent.width
                            wrapMode: TextEdit.Wrap
                            color: notesRoot.theme.textPrimary
                            font.family: notesRoot.theme.fontUi
                            font.pixelSize: notesRoot.theme.fontPx(1.0)
                            selectByMouse: true
                            Keys.onPressed: event => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                    notesRoot.commitStaged(text);
                                    clear();
                                    event.accepted = true;
                                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                    // Not accepted: the TextEdit still pastes
                                    // any text while the probe checks for an
                                    // image — whichever the clipboard holds
                                    // is what happens.
                                    pasteProbe.running = true;
                                }
                            }

                            StyledText {
                                theme: notesRoot.theme
                                role: StyledText.BodyLarge
                                muted: true

                                anchors.fill: parent
                                visible: !captureInput.text
                                wrapMode: Text.Wrap
                                text: notesRoot.pendingAttachment ? "Add a note about the attachment…" : "Add a note, a prompt, a task…"
                            }
                        }
                    }
                }

                ListView {
                    id: list

                    anchors.top: searchField.bottom
                    anchors.topMargin: notesRoot.theme.space(2.5)
                    anchors.bottom: inputField.top
                    anchors.bottomMargin: notesRoot.theme.space(2.5)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    clip: true
                    spacing: notesRoot.theme.space(1.5)
                    model: displayModel
                    boundsBehavior: Flickable.StopAtBounds

                    Connections {
                        target: notesRoot
                        function onScrollRequested() {
                            Qt.callLater(() => list.positionViewAtEnd());
                        }
                    }

                    delegate: Rectangle {
                        id: row

                        required property int index
                        required property string noteId
                        required property string noteLabel
                        required property string noteAttach
                        required property bool noteIsImage
                        required property bool noteDone

                        width: list.width
                        height: Math.max(notesRoot.theme.space(8), rowContent.implicitHeight + notesRoot.theme.space(4))
                        radius: notesRoot.theme.radius(1)
                        color: rowMouse.containsMouse ? notesRoot.theme.alpha(notesRoot.theme.accent, 0.1) : notesRoot.theme.alpha(notesRoot.theme.surface2, 0.6)

                        // External drag: an attachment note exports its file,
                        // a text note its text. Qt's stock Wayland data
                        // device does the rest once Drag.active goes true.
                        // text/plain carries the note's TEXT (falling back
                        // to the path): a text-preferring target gets the
                        // words, a file-preferring one the file.
                        Drag.dragType: Drag.Automatic
                        Drag.supportedActions: Qt.CopyAction
                        Drag.mimeData: row.noteAttach ? {
                            "text/uri-list": NotesModel.pathToUri(row.noteAttach) + "\r\n",
                            "text/plain": row.noteLabel || row.noteAttach
                        } : {
                            "text/plain": row.noteLabel
                        }
                        Drag.active: rowDrag.active
                        // A drop hands the target ONE of the formats above —
                        // that's Wayland DnD, the receiver picks. For a note
                        // that is both file and text, most targets take the
                        // file and the words would vanish: park them on the
                        // clipboard so one Ctrl+V completes the note.
                        // dropAction is NOT consulted: a drop verified
                        // delivered (Emacs opened the dragged file) still
                        // reported IgnoreAction here — the finished action
                        // from foreign targets is unreliable on this stack,
                        // and gating on it silently dropped the text copy
                        // every time (found 2026-08-13, uinput cross-client
                        // test). Worst case of copying unconditionally is a
                        // cancelled drag parks the note's text on the
                        // clipboard — benign.
                        Drag.onDragFinished: {
                            if (row.noteAttach && row.noteLabel) {
                                Quickshell.execDetached(["wl-copy", "--", row.noteLabel]);
                                Quickshell.execDetached(["notify-send", "-a", "qshell", "-t", "3500", "Note text copied", "File dropped — paste the text with Ctrl+V (terminals: Ctrl+Shift+V)"]);
                            }
                        }

                        // Horizontal-only so vertical drags still scroll the
                        // list; once active the pointer can go anywhere.
                        DragHandler {
                            id: rowDrag
                            target: null
                            yAxis.enabled: false
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            // Pre-grab so the platform drag has its pixmap by
                            // the time the threshold trips.
                            onPressed: row.grabToImage(result => {
                                row.Drag.imageSource = result.url;
                            })
                        }

                        Rectangle {
                            id: circle
                            anchors.left: parent.left
                            anchors.leftMargin: notesRoot.theme.space(2)
                            anchors.top: parent.top
                            anchors.topMargin: notesRoot.theme.space(2)
                            width: notesRoot.theme.space(4.5)
                            height: width
                            radius: width / 2
                            color: row.noteDone ? notesRoot.theme.alpha(notesRoot.theme.accent, 0.22) : "transparent"
                            border.width: Math.max(1, notesRoot.theme.borderWidth)
                            border.color: row.noteDone ? notesRoot.theme.accent : notesRoot.theme.textMuted

                            Text {
                                anchors.centerIn: parent
                                visible: row.noteDone
                                text: "󰄬"
                                color: notesRoot.theme.accent
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: notesRoot.theme.fontPx(0.833)
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -notesRoot.theme.space(1)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notesRoot.toggleDone(row.noteId)
                            }
                        }

                        Column {
                            id: rowContent
                            anchors.left: circle.right
                            anchors.leftMargin: notesRoot.theme.space(2)
                            anchors.right: parent.right
                            anchors.rightMargin: notesRoot.theme.space(2)
                            anchors.top: parent.top
                            anchors.topMargin: notesRoot.theme.space(2)
                            spacing: notesRoot.theme.space(1.5)

                            // Image attachments render as a thumbnail card,
                            // Copper-style. Decode is capped at 400 px by
                            // sourceSize (the clipboard picker's rule) so a
                            // list of screenshots can't hold full decodes.
                            ClippingRectangle {
                                id: rowThumb
                                visible: row.noteIsImage
                                width: parent.width
                                height: visible && thumb.implicitWidth > 0 ? Math.min(width * thumb.implicitHeight / thumb.implicitWidth, notesRoot.theme.space(36)) : 0
                                radius: notesRoot.theme.radius(0.75)
                                color: "transparent"
                                opacity: row.noteDone ? 0.5 : 1

                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    source: rowThumb.visible ? NotesModel.pathToUri(row.noteAttach) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 400
                                    sourceSize.height: 400
                                }
                            }

                            Item {
                                width: parent.width
                                height: bodyText.implicitHeight
                                visible: row.noteLabel !== ""

                                Text {
                                    id: fileGlyph
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    visible: row.noteAttach !== "" && !row.noteIsImage
                                    text: "󰈔"
                                    color: notesRoot.theme.textMuted
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: notesRoot.theme.fontPx(0.917)
                                }

                                StyledText {
                                    id: bodyText
                                    theme: notesRoot.theme
                                    role: StyledText.BodyLarge
                                    anchors.left: fileGlyph.visible ? fileGlyph.right : parent.left
                                    anchors.leftMargin: fileGlyph.visible ? notesRoot.theme.space(1.5) : 0
                                    anchors.right: parent.right
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: row.noteLabel
                                    color: row.noteDone ? notesRoot.theme.textMuted : notesRoot.theme.textPrimary
                                    font.strikeout: row.noteDone
                                }
                            }
                        }

                        Rectangle {
                            id: deleteButton
                            anchors.right: parent.right
                            anchors.rightMargin: notesRoot.theme.space(1)
                            anchors.top: parent.top
                            anchors.topMargin: notesRoot.theme.space(1)
                            width: notesRoot.theme.space(5)
                            height: width
                            radius: notesRoot.theme.radius(0.75)
                            color: delMouse.containsMouse ? notesRoot.theme.alpha(notesRoot.theme.error, 0.22) : notesRoot.theme.alpha(notesRoot.theme.surface1, 0.9)
                            visible: rowMouse.containsMouse || delMouse.containsMouse

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: delMouse.containsMouse ? notesRoot.theme.error : notesRoot.theme.textMuted
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: notesRoot.theme.fontPx(0.833)
                            }

                            MouseArea {
                                id: delMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notesRoot.removeNote(row.noteId)
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: list
                    width: list.width
                    spacing: notesRoot.theme.space(2)
                    visible: displayModel.count === 0

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "󰎞"
                        color: notesRoot.theme.textMuted
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: notesRoot.theme.fontPx(3.0)
                    }

                    StyledText {
                        theme: notesRoot.theme
                        role: StyledText.BodyLarge
                        muted: true

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        text: NotesModel.liveNotes(notesRoot.notes).length === 0 ? "Type below, or drop files and text here" : "No matches for “" + notesRoot.filterText + "”"
                    }
                }
            }
        }
    }
}

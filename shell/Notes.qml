import Quickshell
import Quickshell.Io
import QtQuick
import "lib/notes.mjs" as N

// A real window, never a layer surface, so other apps keep their keyboard and clipboard; a niri rule docks it right.
FloatingWindow {
    id: win

    required property var theme
    required property var notes
    required property var niri
    property bool shown: false
    property bool pinned: false
    // composer, list, search or picker: which part has the keyboard.
    property string mode: "composer"
    property int selected: 0
    // Ids picked with v, in the order picked, so a merge keeps that order.
    property var marked: []
    // The note Enter is editing in the composer, or "".
    property string editing: ""
    // switch (Ctrl+K) or move (M): what the section picker's Enter does.
    property string picking: ""
    property int pickSelected: 0
    // Set once niri has focused this window, so losing focus can hide it.
    property bool hadFocus: false

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var store: notes.store
    readonly property string query: search.text
    readonly property var cards: query ? N.search(store, query) : N.sectionNotes(store, store.activeSection)
    readonly property var current: cards[Math.min(selected, cards.length - 1)] ?? null
    readonly property var picks: N.sectionNames(store).filter(s => s.toLowerCase().indexOf(pickInput.text.trim().toLowerCase()) >= 0)
    readonly property var niriWindow: niri.state.windows.find(w => w.title === "Notes" && w.app_id === "org.quickshell") ?? null
    readonly property bool focused: niriWindow?.is_focused ?? false

    title: "Notes"
    visible: shown
    implicitWidth: 420
    implicitHeight: 810
    color: c.surface ?? "white"

    // Mod+N: hidden → shown, shown → focused, focused → hidden with focus back where it was.
    function toggle() {
        if (!shown)
            show();
        else if (!focused && niriWindow)
            niriAction.run(["focus-window", "--id", String(niriWindow.id)], false);
        else
            niriAction.run(["focus-window-previous"], true);
    }

    function show() {
        shown = true;
        useComposer();
    }

    // Esc: focus goes back to the window you came from; an unpinned Notes hides as it loses focus.
    function back() {
        niriAction.run(["focus-window-previous"], false);
    }

    function pin() {
        pinned = !pinned;
        if (pinned && !shown)
            show();
    }

    function hide() {
        shown = false;
        hadFocus = false;
    }

    onFocusedChanged: {
        if (focused)
            hadFocus = true;
        else if (hadFocus && shown && !pinned)
            hide();
    }

    function save() {
        const now = Date.now();
        const next = editing ? N.editNote(store, editing, composer.text, now) : N.compose(store, composer.text, now, notes.newId());
        const wasEditing = editing !== "";
        composer.text = "";
        editing = "";
        notes.save(next);
        if (wasEditing)
            useList();
        else
            selected = 0;
    }

    function useList() {
        mode = "list";
        list.forceActiveFocus();
    }

    function useComposer() {
        mode = "composer";
        composer.forceActiveFocus();
    }

    // The notes a key acts on: the ones picked with v, else the selected one.
    function targets() {
        return marked.length ? marked : current ? [current.id] : [];
    }

    function mark() {
        if (!current)
            return;
        const id = current.id;
        marked = marked.indexOf(id) >= 0 ? marked.filter(m => m !== id) : marked.concat([id]);
    }

    function apply(next) {
        marked = [];
        notes.save(next);
        selected = Math.max(0, Math.min(selected, cards.length - 1));
    }

    function openPicker(kind) {
        picking = kind;
        pickInput.text = "";
        pickSelected = 0;
        mode = "picker";
        pickInput.forceActiveFocus();
    }

    // A typed name that matches no section makes a new one.
    function pick() {
        const name = picks[pickSelected] ?? pickInput.text.trim();
        if (name) {
            if (picking === "switch") {
                notes.save(N.useSection(store, name));
                selected = 0;
            } else {
                apply(N.moveNotes(store, targets(), name, Date.now()));
            }
        }
        picking = "";
        useList();
    }

    function listKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        const now = Date.now();
        if (ctrl && event.key === Qt.Key_K)
            openPicker("switch");
        else if (ctrl && event.key === Qt.Key_Y)
            notes.copyText(N.sectionList(store, store.activeSection));
        else if (ctrl && event.key === Qt.Key_V)
            notes.attachClipboard(current ? current.id : null);
        else if (ctrl)
            return false;
        else if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
            selected = Math.min(selected + 1, cards.length - 1);
        else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
            selected = Math.max(selected - 1, 0);
        else if (event.key === Qt.Key_Tab)
            useComposer();
        else if (event.key === Qt.Key_Escape && marked.length)
            marked = [];
        else if (event.key === Qt.Key_Escape && query)
            search.text = "";
        else if (event.key === Qt.Key_Escape)
            back();
        else if (event.key === Qt.Key_Slash) {
            mode = "search";
            search.forceActiveFocus();
        } else if (!current)
            return false;
        else if (event.key === Qt.Key_Space)
            notes.save(N.toggleDone(store, current.id, now));
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            editing = current.id;
            composer.text = current.text;
            useComposer();
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6)
            notes.save(N.toggleTag(store, current.id, String(event.key - Qt.Key_0), now));
        else if (event.key === Qt.Key_Y && shift && N.firstImage(current))
            notes.copyFile(N.firstImage(current));
        else if (event.key === Qt.Key_Y && !shift)
            notes.copyText(current.text);
        else if (event.key === Qt.Key_V)
            mark();
        else if (event.key === Qt.Key_M && shift)
            openPicker("move");
        else if (event.key === Qt.Key_M)
            apply(N.merge(store, marked, now));
        else if (event.key === Qt.Key_D)
            apply(N.deleteNotes(store, targets(), now));
        else
            return false;
        return true;
    }

    function state() {
        return {
            open: shown,
            focused,
            pinned,
            mode,
            section: store.activeSection,
            selected: current ? current.id : null,
            cards: cards.map(n => n.id),
            marked,
            editing,
            query,
            picking,
            picks,
            composer: composer.text,
            windowId: niriWindow ? niriWindow.id : null
        };
    }

    Process {
        id: niriAction
        property bool hideAfter: false

        function run(args, hide) {
            hideAfter = hide;
            command = ["niri", "msg", "action"].concat(args);
            running = true;
        }

        onExited: {
            if (hideAfter)
                win.hide();
        }
    }

    Item {
        anchors.fill: parent

        Text {
            id: header
            x: 18
            y: 16
            textFormat: Text.PlainText
            text: "Notes  " + win.store.activeSection + (win.pinned ? "  PINNED" : "")
            color: win.c.ink ?? "black"
            font.family: win.fonts.ui ?? ""
            font.pixelSize: 15
        }

        TextInput {
            id: search
            visible: win.mode === "search" || text !== ""
            anchors.top: header.bottom
            anchors.topMargin: 10
            x: 18
            width: parent.width - 36
            height: visible ? implicitHeight : 0
            color: win.c.ink ?? "black"
            font.family: win.fonts.ui ?? ""
            font.pixelSize: 13
            onTextChanged: win.selected = 0

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape)
                    text = "";
                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                    win.useList();
                    event.accepted = true;
                }
            }
        }

        Item {
            id: list
            anchors.top: search.bottom
            anchors.topMargin: 16
            anchors.bottom: composerBox.top
            width: parent.width
            clip: true

            Keys.onPressed: event => {
                event.accepted = win.listKey(event);
            }

            Column {
                x: 16
                width: parent.width - 32
                spacing: 12

                Repeater {
                    model: win.cards

                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: win.mode === "list" && index === win.selected
                        width: parent.width
                        height: content.implicitHeight + 24
                        color: win.marked.indexOf(modelData.id) >= 0 ? (win.c.line ?? "lightgray") : "transparent"
                        border.width: isSelected ? 2 : 1
                        border.color: isSelected ? (win.c.accent ?? "red") : (win.c.ink ?? "black")

                        // The body drags its text alone, so an input it is dropped on gets the text, whatever is attached.
                        MouseArea {
                            id: bodyDrag
                            anchors.fill: parent
                            drag.target: bodyOffer
                        }

                        Item {
                            id: bodyOffer
                            Drag.active: bodyDrag.drag.active
                            Drag.dragType: Drag.Automatic
                            Drag.supportedActions: Qt.CopyAction
                            Drag.mimeData: N.dragOffer(modelData)
                        }

                        Column {
                            id: content
                            x: 14
                            y: 12
                            width: parent.width - 28
                            spacing: 8

                            Text {
                                width: parent.width
                                visible: text !== ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                text: (modelData.todo ? (modelData.done ? "[x] " : "[ ] ") : "") + modelData.text
                                color: win.c.ink ?? "black"
                                font.family: win.fonts.ui ?? ""
                                font.pixelSize: 13
                            }

                            Repeater {
                                model: modelData.attachments

                                // Each chip drags only its own file.
                                Text {
                                    id: chip
                                    required property var modelData
                                    textFormat: Text.PlainText
                                    text: modelData.name + " · " + Math.max(1, Math.round(modelData.size / 1024)) + " KB"
                                    color: win.c.muted ?? "gray"
                                    font.family: win.fonts.mono ?? ""
                                    font.pixelSize: 10

                                    MouseArea {
                                        id: chipDrag
                                        anchors.fill: parent
                                        drag.target: chipOffer
                                    }

                                    Item {
                                        id: chipOffer
                                        Drag.active: chipDrag.drag.active
                                        Drag.dragType: Drag.Automatic
                                        Drag.supportedActions: Qt.CopyAction
                                        Drag.mimeData: N.chipOffer(chip.modelData, win.notes.attachments)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Ctrl+K and M pick a section by name; typing filters, Enter takes the selected one or the typed name.
        Rectangle {
            visible: win.mode === "picker"
            anchors.fill: list
            color: win.c.surface ?? "white"

            TextInput {
                id: pickInput
                x: 18
                width: parent.width - 36
                color: win.c.ink ?? "black"
                font.family: win.fonts.ui ?? ""
                font.pixelSize: 13
                onTextChanged: win.pickSelected = 0

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        win.picking = "";
                        win.useList();
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        win.pick();
                    else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier))
                        win.pickSelected = Math.min(win.pickSelected + 1, win.picks.length - 1);
                    else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier))
                        win.pickSelected = Math.max(win.pickSelected - 1, 0);
                    else
                        return;
                    event.accepted = true;
                }
            }

            Column {
                anchors.top: pickInput.bottom
                anchors.topMargin: 10
                x: 18

                Repeater {
                    model: win.picks

                    Text {
                        required property string modelData
                        required property int index
                        textFormat: Text.PlainText
                        text: (index === win.pickSelected ? "› " : "  ") + modelData
                        color: index === win.pickSelected ? (win.c.accent ?? "red") : (win.c.ink ?? "black")
                        font.family: win.fonts.ui ?? ""
                        font.pixelSize: 13
                    }
                }
            }
        }

        Item {
            id: composerBox
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            x: 16
            width: parent.width - 32
            height: Math.max(composer.implicitHeight, 24) + 24

            TextEdit {
                id: composer
                x: 14
                y: 12
                width: parent.width - 28
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                color: win.c.ink ?? "black"
                font.family: win.fonts.ui ?? ""
                font.pixelSize: 14

                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier))
                        win.save();
                    else if (event.key === Qt.Key_Tab)
                        win.useList();
                    else if (event.key === Qt.Key_Escape && win.editing) {
                        win.editing = "";
                        text = "";
                        win.useList();
                    } else if (event.key === Qt.Key_Escape)
                        win.back();
                    else
                        return;
                    event.accepted = true;
                }
            }
        }
    }
}

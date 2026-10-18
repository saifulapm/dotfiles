import Quickshell
import Quickshell.Io
import QtQuick
import "lib/notes.mjs" as N
import "lib/notes-look.mjs" as L

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
    readonly property var look: theme.tokens ? L.notesLook(theme.tokens) : null
    readonly property var store: notes.store
    readonly property string query: search.text
    readonly property var cards: query ? N.search(store, query) : N.sectionNotes(store, store.activeSection)
    readonly property var current: cards[Math.min(selected, cards.length - 1)] ?? null
    readonly property string typedName: pickInput.text.trim()
    // An exact name comes first, and a typed name that is no section yet is offered last, so work never lands in homework.
    readonly property var picks: {
        const names = N.sectionNames(store);
        const found = names.filter(s => s.toLowerCase().indexOf(typedName.toLowerCase()) >= 0);
        const exact = found.filter(s => s === typedName);
        const rest = exact.concat(found.filter(s => s !== typedName));
        return typedName && !exact.length ? rest.concat([typedName]) : rest;
    }
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

    // Unpinning a Notes you are not in hides it, as losing focus would have.
    function pin() {
        pinned = !pinned;
        if (pinned && !shown)
            show();
        else if (!pinned && shown && !focused)
            hide();
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

    function pick() {
        const name = picks[pickSelected];
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

    // Where the selected card's frame is drawn, in window pixels, so a check can read its outline.
    function selectedRect() {
        const item = mode === "list" ? list.itemAtIndex(selected) : null;
        if (!item)
            return null;
        const p = item.mapToItem(page, 0, 0);
        return { x: Math.round(p.x), y: Math.round(p.y), width: Math.round(item.width), height: Math.round(item.frameHeight) };
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
            windowId: niriWindow ? niriWindow.id : null,
            emptyLine: emptyLine.visible ? { text: emptyLine.text, lines: emptyLine.lineCount } : null,
            selectedRect: selectedRect()
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
        id: page
        anchors.fill: parent

        Row {
            id: header
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 10

            Text {
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: win.look ? win.look.title.text : "Notes"
                color: win.look ? win.look.title.color : "black"
                font.family: win.look ? win.look.title.font : ""
                font.pixelSize: win.look ? win.look.title.size : 17
                font.bold: win.look ? win.look.title.bold : false
                font.letterSpacing: win.look ? win.look.title.spacing : 0
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: sectionText.implicitWidth + (color.a > 0 ? 18 : 0)
                height: sectionText.implicitHeight + (color.a > 0 ? 6 : 0)
                radius: 8
                color: win.look ? win.look.section.pill : "transparent"

                Text {
                    id: sectionText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: win.look ? win.look.sectionLabel(win.store.activeSection) : win.store.activeSection
                    color: win.look ? win.look.section.color : "black"
                    font.family: win.look ? win.look.section.font : ""
                    font.pixelSize: win.look ? win.look.section.size : 12
                    font.italic: win.look ? win.look.section.italic : false
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: win.look && win.look.voice === "bracket" ? "[⌃K]" : "⌃K"
                color: win.c.muted ?? "gray"
                font.family: win.fonts.mono ?? ""
                font.pixelSize: 10
            }
        }

        Rectangle {
            visible: win.pinned
            anchors.verticalCenter: header.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 18
            width: pinnedText.implicitWidth + 14
            height: pinnedText.implicitHeight + 6
            radius: win.look && win.look.pinned.border === 0 ? 8 : 0
            color: win.look ? win.look.pinned.fill : "transparent"
            border.width: win.look ? win.look.pinned.border : 1
            border.color: win.look ? win.look.pinned.color : "red"

            Text {
                id: pinnedText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: win.look ? win.look.pinned.text : "PINNED"
                color: win.look ? win.look.pinned.color : "red"
                font.family: win.look && win.look.voice === "plain" ? win.fonts.ui : win.fonts.mono ?? ""
                font.pixelSize: win.look && win.look.voice === "plain" ? 12 : 10
                font.letterSpacing: win.look && win.look.voice === "plain" ? 0 : 1.4
            }
        }

        Rectangle {
            id: headerRule
            anchors.top: header.bottom
            anchors.topMargin: 12
            width: parent.width
            height: win.look ? win.look.rule.width : 1
            color: win.look ? win.look.rule.color : "black"
        }

        TextInput {
            id: search
            visible: win.mode === "search" || text !== ""
            anchors.top: headerRule.bottom
            anchors.topMargin: visible ? 12 : 0
            x: 18
            width: parent.width - 36
            height: visible ? implicitHeight : 0
            color: win.c.ink ?? "black"
            font.family: win.fonts.mono ?? ""
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

            Text {
                anchors.right: parent.left
                anchors.rightMargin: 4
                textFormat: Text.PlainText
                text: "/"
                color: win.c.accent ?? "red"
                font: search.font
            }
        }

        ListView {
            id: list
            anchors.top: search.bottom
            anchors.topMargin: 16
            anchors.bottom: composerBox.top
            anchors.bottomMargin: 12
            x: 16
            width: parent.width - 32
            clip: true
            spacing: 12
            model: win.cards
            currentIndex: win.selected
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            boundsBehavior: Flickable.StopAtBounds

            Keys.onPressed: event => {
                event.accepted = win.listKey(event);
            }

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool isSelected: win.mode === "list" && index === win.selected
                readonly property var style: win.look ? win.look.card(isSelected, modelData.done) : null
                readonly property var images: modelData.attachments.filter(a => a.mime.indexOf("image/") === 0)
                readonly property real frameHeight: frame.height
                width: ListView.view.width
                height: content.implicitHeight + 24 + (style && style.shadow ? style.shadow.y : 0)

                Rectangle {
                    visible: !!(card.style && card.style.shadow)
                    x: card.style && card.style.shadow ? card.style.shadow.x : 0
                    y: card.style && card.style.shadow ? card.style.shadow.y : 0
                    width: frame.width
                    height: frame.height
                    color: card.style && card.style.shadow ? card.style.shadow.color : "transparent"
                }

                // Blueprint's selected card glows and carries corner ticks, as its design draws them.
                Rectangle {
                    visible: !!(card.style && card.style.glow)
                    anchors.fill: frame
                    anchors.margins: -3
                    color: "transparent"
                    border.width: 3
                    border.color: Qt.alpha(win.c.accent ?? "cyan", 0.25)
                }

                Rectangle {
                    id: frame
                    width: parent.width
                    height: content.implicitHeight + 24
                    radius: win.look ? win.look.radius : 0
                    color: card.style ? card.style.fill : "transparent"
                    border.width: card.style ? card.style.border.width : 1
                    border.color: card.style ? card.style.border.color : "black"

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        visible: win.marked.indexOf(card.modelData.id) >= 0
                        color: Qt.alpha(win.c.accent ?? "red", 0.12)
                    }

                    Repeater {
                        model: card.style && card.style.ticks ? [[-6, -6, 1, 1], [1, -6, 0, 1], [-6, 1, 1, 0], [1, 1, 0, 0]] : []

                        Item {
                            required property var modelData
                            x: modelData[0] < 0 ? -6 : frame.width - 4
                            y: modelData[1] < 0 ? -6 : frame.height - 4
                            width: 10
                            height: 10

                            Rectangle {
                                x: modelData[2] ? 0 : 9
                                width: 1
                                height: 10
                                color: win.c.accent ?? "cyan"
                            }

                            Rectangle {
                                y: modelData[3] ? 0 : 9
                                width: 10
                                height: 1
                                color: win.c.accent ?? "cyan"
                            }
                        }
                    }
                }

                // The body drags its text alone, so an input it is dropped on gets the text, whatever is attached.
                MouseArea {
                    id: bodyDrag
                    anchors.fill: frame
                    drag.target: bodyOffer
                }

                Item {
                    id: bodyOffer
                    Drag.active: bodyDrag.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: N.dragOffer(card.modelData)
                }

                Item {
                    id: check
                    x: 14
                    y: 15
                    width: 13
                    height: 13

                    Rectangle {
                        visible: win.look && win.look.checkbox === "circle" && card.modelData.todo
                        anchors.fill: parent
                        radius: width / 2
                        color: card.modelData.done ? (win.look && win.look.voice === "plain" ? win.c.accent : win.c.ink) ?? "black" : "transparent"
                        border.width: card.modelData.done ? 0 : 1.5
                        border.color: win.c.ink ?? "black"
                    }

                    Text {
                        visible: win.look && win.look.checkbox === "brackets" && card.modelData.todo
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: card.modelData.done ? "[x]" : "[ ]"
                        color: card.modelData.done ? win.c.accent ?? "cyan" : win.c.muted ?? "gray"
                        font.family: win.fonts.mono ?? ""
                        font.pixelSize: 13
                    }
                }

                Column {
                    id: content
                    x: card.modelData.todo ? (win.look && win.look.checkbox === "brackets" ? 48 : 39) : 14
                    y: 12
                    width: frame.width - x - 14
                    spacing: 8

                    Text {
                        width: parent.width
                        visible: text !== ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        lineHeight: 1.15
                        text: card.modelData.text
                        color: card.modelData.done ? win.look?.body.done ?? "gray" : win.look?.body.color ?? "black"
                        font.family: win.look ? win.look.body.font : ""
                        font.pixelSize: win.look ? win.look.body.size : 13
                        font.strikeout: card.modelData.done
                    }

                    Repeater {
                        model: card.images

                        Image {
                            required property var modelData
                            width: Math.min(parent.width, 300)
                            height: Math.min(120, implicitHeight > 0 ? implicitHeight * width / Math.max(1, implicitWidth) : 120)
                            fillMode: Image.PreserveAspectFit
                            horizontalAlignment: Image.AlignLeft
                            asynchronous: true
                            sourceSize.width: 600
                            source: "file://" + win.notes.attachments + "/" + N.attachmentFile(modelData)
                        }
                    }

                    Repeater {
                        model: card.modelData.attachments

                        // Each chip drags only its own file.
                        Text {
                            id: chip
                            required property var modelData
                            textFormat: Text.PlainText
                            text: (win.look && win.look.voice !== "plain" ? modelData.name.toUpperCase() : modelData.name) + " · " + Math.max(1, Math.round(modelData.size / 1024)) + " KB"
                            color: win.c.muted ?? "gray"
                            font.family: win.fonts.mono ?? ""
                            font.pixelSize: win.look ? win.look.small.size : 10
                            font.letterSpacing: win.look ? win.look.small.spacing : 0

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

                    Text {
                        visible: card.isSelected && card.images.length > 0
                        textFormat: Text.PlainText
                        text: win.look ? L.keyLine(win.theme.tokens, [["y", "text"], ["⇧Y", "image"]]) : ""
                        color: win.c.accent ?? "red"
                        font.family: win.fonts.mono ?? ""
                        font.pixelSize: win.look ? win.look.small.size : 10
                        font.letterSpacing: win.look ? win.look.small.spacing : 0
                    }

                    Row {
                        visible: card.modelData.tags.length > 0
                        spacing: 4

                        Repeater {
                            model: card.modelData.tags

                            Rectangle {
                                required property string modelData
                                width: 8
                                height: 8
                                radius: win.look && win.look.radius ? 4 : 0
                                color: win.theme.tokens ? L.tagColour(win.theme.tokens, modelData) : "gray"
                            }
                        }
                    }
                }
            }
        }

        // An empty Notes shows one line of keys, nothing more.
        Text {
            id: emptyLine
            visible: win.cards.length === 0 && win.mode !== "picker"
            anchors.top: list.top
            x: 18
            width: parent.width - 36
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: win.query ? "" : win.look ? L.keyLine(win.theme.tokens, L.EMPTY_KEYS) : ""
            color: win.c.muted ?? "gray"
            font.family: win.fonts.mono ?? ""
            font.pixelSize: win.look ? win.look.small.size : 10
            font.letterSpacing: win.look ? win.look.small.spacing : 0
        }

        // Ctrl+K and M pick a section by name; typing filters, Enter takes the selected one or the typed name.
        Rectangle {
            visible: win.mode === "picker"
            anchors.fill: list
            color: win.c.surface ?? "white"

            TextInput {
                id: pickInput
                x: 2
                width: parent.width - 4
                color: win.c.ink ?? "black"
                font.family: win.fonts.mono ?? ""
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
                x: 2
                spacing: 4

                Repeater {
                    model: win.picks

                    Text {
                        required property string modelData
                        required property int index
                        textFormat: Text.PlainText
                        text: (index === win.pickSelected ? "› " : "  ") + (win.look ? win.look.sectionLabel(modelData) : modelData) + (win.store.sections.some(s => s.name === modelData) ? "" : "  +")
                        color: index === win.pickSelected ? (win.c.accent ?? "red") : (win.c.ink ?? "black")
                        font.family: win.look ? win.look.section.font : ""
                        font.pixelSize: 14
                    }
                }
            }
        }

        Rectangle {
            id: composerBox
            anchors.bottom: keyStrip.top
            anchors.bottomMargin: 12
            x: 16
            width: parent.width - 32
            height: composerColumn.implicitHeight + 24
            radius: win.look ? win.look.composer.radius : 0
            color: win.look ? win.look.composer.fill : "transparent"

            Rectangle {
                visible: win.look ? win.look.composer.radius === 0 : true
                width: parent.width
                height: win.look ? win.look.rule.width : 1
                color: win.look ? win.look.rule.color : "black"
            }

            Column {
                id: composerColumn
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 6

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        id: prompt
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: win.look ? win.look.composer.prompt : ""
                        color: win.c.accent ?? "cyan"
                        font: composer.font
                    }

                    TextEdit {
                        id: composer
                        width: parent.width - (prompt.visible ? prompt.width + 8 : 0)
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        color: win.c.ink ?? "black"
                        font.family: win.look ? win.look.composer.font : ""
                        font.pixelSize: win.look ? win.look.composer.size : 14
                        font.italic: win.look ? win.look.composer.italic && text === "" : false

                        Text {
                            visible: composer.text === ""
                            textFormat: Text.PlainText
                            text: win.editing ? "" : win.look ? win.look.composer.placeholder : ""
                            color: win.c.muted ?? "gray"
                            font: composer.font
                        }

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

                Text {
                    visible: win.cards.length > 0
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: win.look ? L.keyLine(win.theme.tokens, L.COMPOSER_KEYS) : ""
                    color: win.c.muted ?? "gray"
                    font.family: win.fonts.mono ?? ""
                    font.pixelSize: win.look ? win.look.small.size : 10
                    font.letterSpacing: win.look ? win.look.small.spacing : 0
                }
            }
        }

        Item {
            id: keyStrip
            anchors.bottom: parent.bottom
            width: parent.width
            height: win.cards.length > 0 ? keys.implicitHeight + 20 : 0
            visible: win.cards.length > 0

            Rectangle {
                width: parent.width
                height: win.look ? win.look.rule.width : 1
                color: win.look ? win.look.rule.color : "black"
            }

            Text {
                id: keys
                x: 18
                y: 10
                width: parent.width - 36
                wrapMode: Text.Wrap
                lineHeight: 1.3
                textFormat: Text.PlainText
                text: win.look ? L.keyLine(win.theme.tokens, L.KEYS) : ""
                color: win.c.muted ?? "gray"
                font.family: win.fonts.mono ?? ""
                font.pixelSize: win.look ? win.look.small.size : 10
                font.letterSpacing: win.look ? win.look.small.spacing : 0
            }
        }
    }
}

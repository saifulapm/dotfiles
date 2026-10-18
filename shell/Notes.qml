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
    // composer or list: which of the two has the keyboard.
    property string mode: "composer"
    property int selected: 0
    // Set once niri has focused this window, so losing focus can hide it.
    property bool hadFocus: false

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var store: notes.store
    readonly property var cards: N.sectionNotes(store, store.activeSection)
    readonly property var current: cards[Math.min(selected, cards.length - 1)] ?? null
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
        mode = "composer";
        shown = true;
        composer.forceActiveFocus();
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
        const next = N.compose(store, composer.text, Date.now(), notes.newId());
        composer.text = "";
        selected = 0;
        notes.save(next);
    }

    function useList() {
        mode = "list";
        list.forceActiveFocus();
    }

    function useComposer() {
        mode = "composer";
        composer.forceActiveFocus();
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

        Item {
            id: list
            anchors.top: header.bottom
            anchors.topMargin: 16
            anchors.bottom: composerBox.top
            width: parent.width
            clip: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                    win.selected = Math.min(win.selected + 1, win.cards.length - 1);
                else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                    win.selected = Math.max(win.selected - 1, 0);
                else if (event.key === Qt.Key_Tab)
                    win.useComposer();
                else if (event.key === Qt.Key_Escape)
                    win.back();
                else
                    return;
                event.accepted = true;
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
                        width: parent.width
                        height: body.implicitHeight + 24
                        color: "transparent"
                        border.width: win.mode === "list" && index === win.selected ? 2 : 1
                        border.color: win.mode === "list" && index === win.selected ? (win.c.accent ?? "red") : (win.c.ink ?? "black")

                        Text {
                            id: body
                            x: 14
                            y: 12
                            width: parent.width - 28
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            text: modelData.text
                            color: win.c.ink ?? "black"
                            font.family: win.fonts.ui ?? ""
                            font.pixelSize: 13
                        }
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
                    else if (event.key === Qt.Key_Escape)
                        win.back();
                    else
                        return;
                    event.accepted = true;
                }
            }
        }
    }
}

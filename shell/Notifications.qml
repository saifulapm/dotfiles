import Quickshell
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/notifs.mjs" as Lib

// The notification centre, drawn in the Surfaces window.
Item {
    id: centre

    required property var theme
    // The Notifs service: its history, Do Not Disturb and the remove, clear and act calls.
    required property var notifs
    property bool shown: false
    readonly property string query: input.text
    property int selected: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var groups: Lib.group(Lib.visible(notifs.history, query))
    // One row per entry in group order; the first of each group carries its header.
    readonly property var rows: groups.reduce((all, g) => all.concat(g.entries.map((e, i) => ({
                        entry: e,
                        head: i === 0 ? g.app.toUpperCase() + " · " + g.entries.length : ""
                    }))), [])

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        input.text = "";
        selected = 0;
        shown = true;
        keys.forceActiveFocus();
    }

    function close() {
        shown = false;
    }

    // Called on each of the host window's frames; the first one after open() ends the timing.
    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function move(by) {
        selected = Lib.clampSelected(selected + by, rows.length);
    }

    function act() {
        const row = rows[selected];
        if (row && notifs.act(row.entry.key))
            close();
    }

    function dismiss() {
        const row = rows[selected];
        if (row)
            notifs.remove(row.entry.key);
    }

    function state() {
        return {
            open: shown,
            query: query,
            selected: selected,
            groups: groups.map(g => ({
                        app: g.app,
                        entries: g.entries.map(e => e.summary)
                    })),
            hint: rows.length === 0,
            openMs: openMs,
            opens: opens
        };
    }

    onQueryChanged: selected = 0
    onRowsChanged: selected = Lib.clampSelected(selected, rows.length)
    onSelectedChanged: list.positionViewAtIndex(selected, ListView.Contain)
    Component.onCompleted: Root.State.loaded.push("notifs")

    visible: shown

    // Holds focus while the list is in use, where plain j/k move and d, D and / act.
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                centre.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                centre.move(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                centre.act();
            else if (event.key === Qt.Key_D && (event.modifiers & Qt.ShiftModifier))
                centre.notifs.clear();
            else if (event.key === Qt.Key_D)
                centre.dismiss();
            else if (event.key === Qt.Key_Slash)
                input.forceActiveFocus();
            else if (event.key === Qt.Key_Escape)
                centre.close();
            else
                return;
            event.accepted = true;
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(c.paper, card.style.wash)
        }

        Root.Surface {
            id: card
            x: Math.round((parent.width - width) / 2)
            y: 168
            width: 640
            height: column.implicitHeight
            tokens: centre.theme.tokens
            role: "card"
            label: "Notifications"

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 16
                    Layout.bottomMargin: 12
                    spacing: 12

                    Text {
                        textFormat: Text.PlainText
                        text: "NOTIFICATIONS"
                        color: c.ink
                        font.family: fonts.ui
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: rows.length + " · newest first"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 12
                    }
                    Rectangle {
                        implicitWidth: chip.implicitWidth + 14
                        implicitHeight: chip.implicitHeight + 6
                        color: "transparent"
                        border.color: centre.notifs.dnd ? c.accent : c.line
                        border.width: 1
                        Text {
                            id: chip
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "Do not disturb: " + (centre.notifs.dnd ? "on" : "off")
                            color: centre.notifs.dnd ? c.accent : c.muted
                            font.family: fonts.ui
                            font.pixelSize: 11
                        }
                    }
                }

                // Shown while a search is typed or has text; Tab gives the keys back to the list.
                TextInput {
                    id: input
                    visible: activeFocus || text !== ""
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.bottomMargin: 10
                    color: c.ink
                    font.family: fonts.mono
                    font.pixelSize: 13
                    clip: true
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J))
                            centre.move(1);
                        else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K))
                            centre.move(-1);
                        else if (event.key === Qt.Key_Tab)
                            keys.forceActiveFocus();
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            centre.act();
                        else if (event.key === Qt.Key_Escape)
                            centre.close();
                        else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: input.text === ""
                        text: "/ search"
                        color: c.muted
                        font: input.font
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.line
                }

                Text {
                    textFormat: Text.PlainText
                    visible: rows.length === 0
                    Layout.fillWidth: true
                    leftPadding: 20
                    topPadding: 14
                    bottomPadding: 14
                    text: (query ? "NO MATCH" : "NO NOTIFICATIONS") + " · / SEARCH · ESC CLOSE"
                    color: c.muted
                    font.family: fonts.ui
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }

                ListView {
                    id: list
                    visible: rows.length > 0
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    implicitHeight: Math.min(contentHeight, 480)
                    clip: true
                    interactive: false
                    model: rows

                    delegate: Column {
                        id: item
                        required property var modelData
                        required property int index
                        readonly property bool current: index === centre.selected
                        width: list.width

                        Text {
                            textFormat: Text.PlainText
                            visible: item.modelData.head !== ""
                            leftPadding: 20
                            topPadding: 10
                            bottomPadding: 4
                            text: item.modelData.head
                            color: c.muted
                            font.family: fonts.mono
                            font.pixelSize: 10
                            font.letterSpacing: 1.2
                        }

                        Rectangle {
                            x: 10
                            width: parent.width - 20
                            implicitHeight: entry.implicitHeight + 16
                            color: "transparent"
                            border.color: item.current ? c.accent : "transparent"
                            border.width: 1.5

                            RowLayout {
                                id: entry
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 12

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        textFormat: Text.PlainText
                                        width: parent.width
                                        text: item.modelData.entry.summary
                                        elide: Text.ElideRight
                                        color: c.ink
                                        font.family: fonts.ui
                                        font.pixelSize: 14
                                        font.weight: item.current ? Font.Medium : Font.Normal
                                    }
                                    Text {
                                        visible: text !== ""
                                        width: parent.width
                                        text: item.modelData.entry.body
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        color: c.muted
                                        font.family: fonts.ui
                                        font.pixelSize: 13
                                    }
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.alignment: Qt.AlignTop
                                    text: Qt.formatTime(new Date(item.modelData.entry.time), "HH:mm")
                                    color: c.muted
                                    font.family: fonts.mono
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.line
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    leftPadding: 20
                    rightPadding: 20
                    topPadding: 10
                    bottomPadding: 10
                    text: "j/k move  ↵ open  d dismiss  D clear all  / search  Esc"
                    color: c.muted
                    font.family: fonts.mono
                    font.pixelSize: 11
                }
            }
        }
    }
}

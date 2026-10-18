import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/cheatsheet.mjs" as Lib

// Every titled niri bind in four columns, drawn in the Surfaces window.
Item {
    id: sheet

    required property var theme
    property bool shown: false
    property var rows: []
    readonly property string query: input.text
    readonly property var columns: Lib.groupRows(Lib.filterRows(rows, query))
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        input.text = "";
        list.contentY = 0;
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

    function state() {
        return JSON.stringify({
            open: shown,
            rows: rows.length,
            groups: Lib.GROUPS,
            query: query,
            openMs: openMs,
            opens: opens
        });
    }

    Component.onCompleted: Root.State.loaded.push("cheatsheet")

    // The nested session sets DOTS_NIRI_BINDS to the repo's binds, so it never reads the live ones.
    FileView {
        path: Quickshell.env("DOTS_NIRI_BINDS") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri/binds.kdl"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: sheet.rows = Lib.parseBinds(text())
    }

    visible: shown

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Slash)
                input.forceActiveFocus();
            else if (event.key === Qt.Key_Escape)
                sheet.close();
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
            y: Math.round((parent.height - height) / 2)
            width: Math.min(1160, parent.width - 48)
            height: Math.min(column.implicitHeight, parent.height - 96)
            tokens: sheet.theme.tokens
            label: "Keys"

            ColumnLayout {
                id: column
                anchors.fill: parent
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    Layout.topMargin: 18
                    Layout.bottomMargin: 14
                    spacing: 14

                    Text {
                        textFormat: Text.PlainText
                        text: "KEYS"
                        color: c.ink
                        font.family: fonts.ui
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.letterSpacing: 1.4
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: "read from the niri binds · Mod = Super"
                        elide: Text.ElideRight
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 12
                    }
                    TextInput {
                        id: input
                        visible: activeFocus || text !== ""
                        Layout.preferredWidth: 220
                        color: c.ink
                        font.family: fonts.mono
                        font.pixelSize: 12
                        clip: true
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape)
                                sheet.close();
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                keys.forceActiveFocus();
                            else
                                return;
                            event.accepted = true;
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: "/ filter · Esc"
                        color: c.muted
                        font.family: fonts.mono
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.ink
                }

                // Scrolls when the columns are taller than the screen leaves room for.
                Flickable {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: groups.implicitHeight + 36
                    contentHeight: groups.implicitHeight + 36
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: groups
                        x: 24
                        y: 18
                        width: list.width - 48
                        spacing: 28

                        Repeater {
                            model: sheet.columns

                            Column {
                                id: group
                                required property var modelData
                                width: (groups.width - 3 * groups.spacing) / 4
                                spacing: 6

                                Text {
                                    textFormat: Text.PlainText
                                    bottomPadding: 4
                                    text: group.modelData.name
                                    color: c.muted
                                    font.family: fonts.mono
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.4
                                }

                                Repeater {
                                    model: group.modelData.rows

                                    RowLayout {
                                        required property var modelData
                                        width: group.width
                                        spacing: 6

                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.maximumWidth: group.width - keyText.implicitWidth - 24
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            color: c.ink
                                            font.family: fonts.ui
                                            font.pixelSize: 13
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: "........................................................................"
                                            clip: true
                                            color: c.line
                                            font.family: fonts.mono
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            id: keyText
                                            text: modelData.key
                                            color: c.ink
                                            font.family: fonts.mono
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.ink
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    leftPadding: 24
                    rightPadding: 24
                    topPadding: 12
                    bottomPadding: 12
                    text: "inside every surface:  j/k move   ↵ act   / search   ⇥ section   Esc close"
                    elide: Text.ElideRight
                    color: c.muted
                    font.family: fonts.mono
                    font.pixelSize: 11
                }
            }
        }
    }
}

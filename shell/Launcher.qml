import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/launcher.mjs" as Lib

// Apps mode; stays mapped once loaded, since a remap costs 20 to 30 ms before the first frame.
PanelWindow {
    id: launcher

    required property var theme
    property bool shown: false
    readonly property string query: input.text
    property int selected: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var apps: DesktopEntries.applications.values.map(e => ({
                id: e.id,
                name: e.name,
                genericName: e.genericName || e.comment,
                keywords: e.keywords,
                entry: e
            }))
    readonly property var found: Lib.rank(apps, query)
    readonly property var rows: found.slice(0, 8)

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        input.text = "";
        selected = 0;
        shown = true;
        input.forceActiveFocus();
    }

    function close() {
        shown = false;
    }

    function move(by) {
        selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }

    // niri spawns the app, so it is niri's child and outlives a shell restart.
    function launch() {
        const row = rows[selected];
        if (!row)
            return;
        Quickshell.execDetached(["niri", "msg", "action", "spawn", "--"].concat(row.entry.command));
        close();
    }

    function state() {
        return JSON.stringify({
            open: shown,
            mode: "apps",
            query: query,
            results: rows.map(r => r.name),
            selected: selected,
            openMs: openMs,
            opens: opens
        });
    }

    onQueryChanged: selected = 0
    Component.onCompleted: Root.State.loaded.push("launcher")

    Connections {
        target: launcher.contentItem.Window.window
        function onFrameSwapped() {
            if (launcher.shown && launcher.openT0 >= 0) {
                launcher.openMs = Date.now() - launcher.openT0;
                launcher.openT0 = -1;
            }
        }
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dots-launcher"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    mask: shown ? null : noInput

    Region {
        id: noInput
    }

    Item {
        anchors.fill: parent
        visible: launcher.shown

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(c.paper, 0.72)
        }

        // The hard offset shadow, square like the card.
        Rectangle {
            x: card.x + 6
            y: card.y + 6
            width: card.width
            height: card.height
            color: c.ink
        }

        Rectangle {
            id: card
            x: Math.round((parent.width - width) / 2)
            y: 168
            width: 640
            height: column.implicitHeight
            color: c.surface
            border.color: c.ink
            border.width: 1.5

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 18
                    Layout.bottomMargin: 14
                    spacing: 14

                    Rectangle {
                        implicitWidth: chip.implicitWidth + 14
                        implicitHeight: chip.implicitHeight + 6
                        color: c.ink
                        Text {
                            id: chip
                            anchors.centerIn: parent
                            text: "APPS"
                            color: c.surface
                            font.family: fonts.ui
                            font.pixelSize: 10
                            font.letterSpacing: 1.4
                        }
                    }

                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        color: c.ink
                        font.family: fonts.display
                        font.pixelSize: 34
                        clip: true
                        focus: true
                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J))
                                launcher.move(1);
                            else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K))
                                launcher.move(-1);
                            else if (event.key === Qt.Key_Tab)
                                results.forceActiveFocus();
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                launcher.launch();
                            else if (event.key === Qt.Key_Escape)
                                launcher.close();
                            else
                                return;
                            event.accepted = true;
                        }
                    }

                    Text {
                        text: found.length + " FOUND"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 10
                        font.letterSpacing: 1.4
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.ink
                }

                // Holds focus after Tab, where plain j/k move and / returns to the query.
                Item {
                    id: results
                    Layout.fillWidth: true
                    implicitHeight: list.implicitHeight + 16
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                            launcher.move(1);
                        else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                            launcher.move(-1);
                        else if (event.key === Qt.Key_Slash)
                            input.forceActiveFocus();
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            launcher.launch();
                        else if (event.key === Qt.Key_Escape)
                            launcher.close();
                        else
                            return;
                        event.accepted = true;
                    }

                    Column {
                        id: list
                        y: 8
                        width: parent.width

                        Text {
                            visible: rows.length === 0
                            leftPadding: 20
                            topPadding: 11
                            bottomPadding: 11
                            text: "NO MATCH · ↑↓ OR CTRL+J/K MOVE · TAB THEN J/K · ↵ OPEN · ESC CLOSE"
                            color: c.muted
                            font.family: fonts.ui
                            font.pixelSize: 10
                            font.letterSpacing: 1.2
                        }

                        Repeater {
                            model: rows

                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool current: index === launcher.selected
                                width: list.width
                                implicitHeight: row.implicitHeight + 22
                                color: current ? c.ink : "transparent"

                                RowLayout {
                                    id: row
                                    anchors.fill: parent
                                    anchors.leftMargin: 20
                                    anchors.rightMargin: 20
                                    spacing: 14

                                    Text {
                                        text: "▸"
                                        color: current ? c.accent : "transparent"
                                        font.family: fonts.ui
                                        font.pixelSize: 15
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        elide: Text.ElideRight
                                        color: current ? c.surface : c.ink
                                        font.family: fonts.ui
                                        font.pixelSize: 15
                                        font.weight: current ? Font.Medium : Font.Normal
                                    }
                                    Text {
                                        Layout.maximumWidth: 260
                                        text: modelData.genericName
                                        elide: Text.ElideRight
                                        color: current ? c.line : c.muted
                                        font.family: fonts.display
                                        font.italic: true
                                        font.pixelSize: 16
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
                    Layout.fillWidth: true
                    leftPadding: 20
                    rightPadding: 20
                    topPadding: 12
                    bottomPadding: 12
                    horizontalAlignment: Text.AlignRight
                    text: "J/K · ↵ · ESC"
                    color: c.muted
                    font.family: fonts.ui
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
            }
        }
    }
}

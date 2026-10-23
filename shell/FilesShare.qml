import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib/files.mjs" as F
import "lib/tailscale.mjs" as T

// Files' share list: the tailnet's devices over the window, online first; Enter sends the files to an online one and closes, and the island carries the progress.
Item {
    id: share

    // What Files hands over: the theme's colours and faces, and the voice's look.
    property var c: ({})
    property var fonts: ({})
    property var look
    property var paths: []
    property real bytes: 0

    property bool shown: false
    property bool listed: false
    property var machines: []
    property int selected: 0
    // Files takes its keys back on this.
    signal closed

    // dots-taildrop-send beside the shell's bin/, started detached so the send outlives Files' window.
    readonly property string sendBin: Quickshell.shellDir + "/../bin/dots-taildrop-send"
    readonly property string voice: look.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property var head: F.shareHead(voice, paths.length, bytes)
    readonly property var keyPairs: look.keys([["↵", "send with Taildrop"], ["j/k", "move"], ["esc", ""]])

    anchors.fill: parent
    visible: shown

    function show(files, size) {
        if (!files.length)
            return;
        paths = files;
        bytes = size;
        machines = [];
        listed = false;
        selected = 0;
        shown = true;
        reader.running = true;
        forceActiveFocus();
    }

    function close() {
        shown = false;
        closed();
    }

    function move(by) {
        selected = Math.max(0, Math.min(machines.length - 1, selected + by));
    }

    // An offline device cannot be sent to: Enter on it does nothing and the list stays.
    function send() {
        const to = machines[selected];
        if (!to || !to.online)
            return;
        const files = paths;
        close();
        Quickshell.execDetached([sendBin, to.name, to.ip].concat(files));
    }

    // The list as drawn, for checks that read the window rather than the data.
    function state() {
        const rows = [];
        for (let i = 0; i < rowRepeater.count; i++)
            rows.push(rowRepeater.itemAt(i).drawn());
        const keyTexts = [];
        for (let i = 0; i < keyRepeater.count; i++)
            keyTexts.push(keyRepeater.itemAt(i).drawn());
        return {
            open: shown,
            listed: listed,
            selected: selected,
            head: {
                label: labelText.text,
                count: countText.text,
                tag: tagText.text
            },
            rows: rows,
            keys: keyTexts
        };
    }

    Process {
        id: reader
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            id: readOut
        }
        // A tailscaled that is not running fails the read, which parses as no machines.
        onExited: {
            share.machines = T.parseStatus(readOut.text, Date.now()).machines;
            share.selected = 0;
            share.listed = true;
        }
    }

    Keys.onPressed: event => {
        const k = event.key;
        const t = event.text;
        if (k === Qt.Key_Escape)
            close();
        else if (t === "j" || k === Qt.Key_Down)
            move(1);
        else if (t === "k" || k === Qt.Key_Up)
            move(-1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter)
            send();
        // The list holds every other key too, so none reaches Files' rows behind it.
        event.accepted = true;
    }

    // The window behind, dimmed.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(share.c.surface ?? "white", 0.72)
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: 150
        width: 480
        height: cardColumn.implicitHeight + 2 * border.width
        color: share.c.surface ?? "white"
        radius: share.plain ? 14 : 0
        border.width: share.bracket ? 1 : 1.5
        border.color: share.plain || share.bracket ? share.c.accent ?? "red" : share.c.ink ?? "black"

        ColumnLayout {
            id: cardColumn
            x: card.border.width
            y: card.border.width
            width: card.width - 2 * card.border.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                spacing: 12

                Rectangle {
                    readonly property bool boxed: share.look.label.kind !== "header"
                    implicitWidth: labelText.implicitWidth + (boxed ? 14 : 0)
                    implicitHeight: labelText.implicitHeight + (boxed ? 4 : 0)
                    radius: share.look.label.kind === "pill" ? 8 : 0
                    color: boxed ? share.look.label.fill : "transparent"

                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: share.head.label
                        color: parent.boxed ? share.look.label.color : share.c.accent
                        font.family: share.look.small.font
                        font.pixelSize: 10
                        font.letterSpacing: share.plain ? 0 : 1.4
                    }
                }
                Text {
                    id: countText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: share.head.count
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: share.c.ink ?? "black"
                    font.family: share.bracket ? share.fonts.mono ?? "" : share.fonts.ui ?? ""
                    font.pixelSize: share.bracket ? 12 : 15
                }
                Text {
                    id: tagText
                    textFormat: Text.PlainText
                    text: share.head.tag
                    color: share.look.small.color
                    font.family: share.look.small.font
                    font.pixelSize: 11
                    font.letterSpacing: share.look.small.spacing
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: share.look.rule.color
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 8
                spacing: 2

                Repeater {
                    id: rowRepeater
                    model: share.machines

                    Rectangle {
                        id: rowItem
                        required property var modelData
                        required property int index
                        readonly property var say: F.shareRow(share.voice, modelData)
                        readonly property bool isCurrent: index === share.selected
                        readonly property bool online: modelData.online
                        // An offline row stays dimmed under the cursor too: Enter on it does nothing.
                        readonly property color ink: online ? (isCurrent ? share.look.cursor.text : share.c.ink ?? "black") : isCurrent ? Qt.alpha(share.look.cursor.text, 0.55) : share.c.muted ?? "gray"
                        function drawn() {
                            return {
                                name: nameText.text,
                                lines: nameText.lineCount,
                                elided: nameText.truncated,
                                detail: detailText.text,
                                status: statusText.text,
                                color: String(nameText.color),
                                current: isCurrent
                            };
                        }
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: share.look.cursor.radius
                        color: isCurrent ? share.look.cursor.fill : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 14

                            // Filled while online, hollow while offline.
                            Rectangle {
                                implicitWidth: 10
                                implicitHeight: 10
                                radius: share.plain ? 5 : 0
                                color: rowItem.online ? rowItem.ink : "transparent"
                                border.width: rowItem.online ? 0 : 1.5
                                border.color: rowItem.ink
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    id: nameText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: rowItem.say.name
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: rowItem.ink
                                    font.family: share.bracket ? share.fonts.mono ?? "" : share.fonts.ui ?? ""
                                    font.pixelSize: 14
                                    font.weight: rowItem.online ? Font.Medium : Font.Normal
                                }
                                Text {
                                    id: detailText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: rowItem.say.detail
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: rowItem.isCurrent ? share.look.cursor.detail : share.c.muted ?? "gray"
                                    font.family: share.fonts.mono ?? ""
                                    font.pixelSize: 11
                                }
                            }
                            Text {
                                id: statusText
                                textFormat: Text.PlainText
                                text: rowItem.say.status
                                color: rowItem.isCurrent ? share.look.cursor.detail : share.c.muted ?? "gray"
                                font.family: share.fonts.mono ?? ""
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: share.look.rule.color
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 11
                Layout.bottomMargin: 11
                spacing: 16

                Repeater {
                    id: keyRepeater
                    model: share.keyPairs

                    Row {
                        id: keyPair
                        required property var modelData
                        spacing: 6
                        function drawn() {
                            return keyText.text + (wordText.text ? " " + wordText.text : "");
                        }

                        Text {
                            id: keyText
                            textFormat: Text.PlainText
                            text: keyPair.modelData.key
                            color: share.bracket ? share.c.accent ?? "red" : share.c.ink ?? "black"
                            font.family: share.fonts.mono ?? ""
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Text {
                            id: wordText
                            visible: text !== ""
                            textFormat: Text.PlainText
                            text: keyPair.modelData.word
                            color: share.look.small.color
                            font.family: share.look.small.font
                            font.pixelSize: 11
                            font.letterSpacing: share.look.small.spacing
                        }
                    }
                }
            }
        }
    }
}

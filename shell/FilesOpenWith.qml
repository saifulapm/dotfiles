import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib/files.mjs" as F
import "lib/picker.mjs" as P

// Files' Open with, over the dimmed window: the apps whose desktop entries declare the targets' type, the default first. It holds the keys while open.
Item {
    id: root

    required property var look
    required property var c
    required property var fonts
    // The rows' key handler, which gets the keys back when the list closes.
    required property Item rowKeys

    property var targets: []
    property var found: null
    property int at: 0
    readonly property var apps: found ? found.apps : []
    readonly property string voice: look.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property var head: F.openWithHead(voice, targets.length, found ? found.description : null, apps.length)
    readonly property var keyPairs: look.keys([["↵", "open"], ["j/k", "move"], ["shift+↵", "make default"], ["esc", ""]])

    visible: false
    z: 10

    function show(paths) {
        if (!paths.length)
            return;
        targets = paths;
        found = null;
        at = 0;
        visible = true;
        forceActiveFocus();
        list();
    }

    function close() {
        visible = false;
        rowKeys.forceActiveFocus();
    }

    function list() {
        lister.command = ["dots-files-apps", "list"].concat(targets);
        lister.running = true;
    }

    function openIn() {
        if (!apps[at])
            return;
        // Detached, so the app outlives Files.
        Quickshell.execDetached(["dots-files-apps", "open", apps[at].id].concat(targets));
        close();
    }

    function makeDefault() {
        if (!apps[at] || setter.running)
            return;
        setter.command = ["dots-files-apps", "default", found.type, apps[at].id];
        setter.running = true;
    }

    // The list as drawn, for checks that read the window rather than the data.
    function state() {
        const rows = [];
        for (let i = 0; i < appRows.count; i++) {
            const r = appRows.itemAt(i);
            if (r)
                rows.push(r.drawn());
        }
        return {
            open: visible,
            label: label.text,
            title: title.text,
            count: count.text,
            at: at,
            rows: rows,
            keys: keyRow.drawn()
        };
    }

    Keys.onPressed: event => {
        const k = event.key;
        const t = event.text;
        if (k === Qt.Key_Escape)
            close();
        else if (t === "j" || k === Qt.Key_Down)
            at = Math.max(0, Math.min(apps.length - 1, at + 1));
        else if (t === "k" || k === Qt.Key_Up)
            at = Math.max(0, at - 1);
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier))
            makeDefault();
        else if (k === Qt.Key_Return || k === Qt.Key_Enter)
            openIn();
        event.accepted = true;
    }

    Process {
        id: lister
        stdout: StdioCollector {
            id: listOut
        }
        onExited: {
            let out = null;
            try {
                out = JSON.parse(listOut.text);
            } catch (e) {
                out = null;
            }
            root.found = out && Array.isArray(out.apps) ? out : {
                type: "",
                description: null,
                apps: []
            };
            root.at = 0;
        }
    }

    // A new default is listed again, so its badge and its place at the top follow it.
    Process {
        id: setter
        onExited: root.list()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(root.c.surface ?? "white", 0.72)
    }

    // Paper's hard ink shadow.
    Rectangle {
        visible: root.voice === "caps"
        x: card.x + 6
        y: card.y + 6
        width: card.width
        height: card.height
        color: root.c.ink ?? "black"
    }

    Rectangle {
        id: card
        x: (parent.width - width) / 2
        y: 144
        width: 560
        height: cardColumn.implicitHeight
        color: root.c.surface ?? "white"
        radius: root.plain ? 14 : 0
        border.width: root.bracket ? 1 : 1.5
        border.color: root.voice === "caps" ? root.c.ink ?? "black" : root.c.accent ?? "blue"

        ColumnLayout {
            id: cardColumn
            width: parent.width
            spacing: 0

            // The label, how many files of which type, and how many apps.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                spacing: 12

                Rectangle {
                    readonly property bool boxed: root.look.label.kind !== "header"
                    implicitWidth: label.implicitWidth + (boxed ? 14 : 0)
                    implicitHeight: label.implicitHeight + (boxed ? 4 : 0)
                    radius: root.look.label.kind === "pill" ? 8 : 0
                    color: boxed ? root.look.label.fill : "transparent"

                    Text {
                        id: label
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: root.look.heading("Open with")
                        color: parent.boxed ? root.look.label.color : root.c.accent ?? "blue"
                        font.family: root.look.small.font
                        font.pixelSize: root.plain ? 12 : 10
                        font.weight: root.voice === "caps" ? Font.Normal : root.plain ? Font.Medium : Font.Bold
                        font.letterSpacing: root.plain ? 0 : 1.4
                    }
                }
                Text {
                    visible: root.bracket
                    textFormat: Text.PlainText
                    text: "//"
                    color: root.c.muted ?? "gray"
                    font.family: root.fonts.mono ?? ""
                    font.pixelSize: 10
                }
                Text {
                    id: title
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.head.title
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: root.c.ink ?? "black"
                    font.family: root.bracket ? root.fonts.mono ?? "" : root.fonts.ui ?? ""
                    font.pixelSize: root.bracket ? 12 : root.plain ? 16 : 15
                    font.weight: root.plain ? Font.Medium : Font.Normal
                }
                Text {
                    id: count
                    textFormat: Text.PlainText
                    text: root.found ? root.head.count : ""
                    color: root.look.small.color
                    font.family: root.look.small.font
                    font.pixelSize: root.bracket ? 10 : 11
                    font.letterSpacing: root.bracket ? 1.6 : 0
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.look.rule.color
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 8
                spacing: 2

                Repeater {
                    id: appRows
                    model: root.apps

                    Rectangle {
                        id: appRow
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: index === root.at
                        readonly property var words: F.appText(root.voice, modelData)
                        function drawn() {
                            return {
                                app: modelData.id,
                                name: nameText.text,
                                lines: nameText.lineCount,
                                elided: nameText.truncated,
                                sub: subText.text,
                                badge: badgeText.text
                            };
                        }
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: root.look.cursor.radius
                        color: isCurrent ? root.look.cursor.fill : "transparent"

                        ColumnLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: badge.left
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 2

                            Text {
                                id: nameText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: appRow.words.name
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                color: appRow.isCurrent ? root.look.cursor.text : root.c.ink ?? "black"
                                font.family: root.bracket ? root.fonts.mono ?? "" : root.fonts.ui ?? ""
                                font.pixelSize: root.plain ? 15 : 14
                                font.weight: appRow.isCurrent && root.bracket ? Font.Bold : Font.Medium
                            }
                            Text {
                                id: subText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: appRow.words.sub
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                color: appRow.isCurrent ? root.look.cursor.detail : root.c.muted ?? "gray"
                                font.family: root.bracket ? root.fonts.mono ?? "" : root.fonts.ui ?? ""
                                font.pixelSize: root.bracket ? 10 : 11
                                font.letterSpacing: root.bracket ? 1.4 : 0
                            }
                        }

                        // Paper boxes the badge in the row's inverse, Artboard fills a pill in ink, Blueprint writes it bare.
                        Rectangle {
                            id: badge
                            visible: badgeText.text !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            implicitWidth: badgeText.implicitWidth + (root.bracket ? 0 : 14)
                            implicitHeight: badgeText.implicitHeight + 4
                            radius: root.plain ? 8 : 0
                            color: root.bracket ? "transparent" : root.plain ? root.c.ink ?? "black" : appRow.isCurrent ? root.look.cursor.text : root.c.ink ?? "black"

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: appRow.words.badge
                                color: root.bracket ? (appRow.isCurrent ? root.look.cursor.text : root.c.accent ?? "blue") : root.plain ? root.c.surface ?? "white" : appRow.isCurrent ? root.look.cursor.fill : root.c.surface ?? "white"
                                font.family: root.bracket ? root.fonts.mono ?? "" : root.fonts.ui ?? ""
                                font.pixelSize: root.bracket ? 10 : 11
                                font.weight: root.bracket ? Font.Bold : root.plain ? Font.Medium : Font.Normal
                                font.letterSpacing: root.bracket ? 1.2 : 0
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.look.rule.color
            }

            // The list's keys, each with its word; Esc's word is left out, as every board draws it.
            Flow {
                id: keyRow
                function drawn() {
                    const out = [];
                    for (let i = 0; i < keyRepeater.count; i++) {
                        const k = keyRepeater.itemAt(i);
                        if (k)
                            out.push(k.drawn());
                    }
                    return out;
                }
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 11
                Layout.bottomMargin: 11
                spacing: 16

                Repeater {
                    id: keyRepeater
                    model: root.keyPairs

                    Row {
                        required property var modelData
                        function drawn() {
                            return {
                                key: keyText.text,
                                word: wordText.text
                            };
                        }
                        spacing: 6

                        Text {
                            id: keyText
                            textFormat: Text.PlainText
                            text: modelData.key
                            color: root.bracket ? root.c.accent ?? "blue" : root.c.ink ?? "black"
                            font.family: root.fonts.mono ?? ""
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Text {
                            id: wordText
                            textFormat: Text.PlainText
                            text: modelData.word
                            color: root.look.small.color
                            font.family: root.look.small.font
                            font.pixelSize: root.plain ? 11 : 10
                            font.letterSpacing: root.plain ? 0 : 1.4
                        }
                    }
                }
            }
        }
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "." as Root
import "lib/voice.mjs" as L
import "lib/tailscale.mjs" as T

// The tailnet as a list: this device, the machines with their online state, or one line when Tailscale is not on; tailscale runs only while it shows.
Item {
    id: panel

    required property var theme
    property bool shown: false
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1
    property var status: ({ state: "on", self: null, machines: [], online: 0 })
    property bool listed: false
    property int selected: 0
    // "<name> is offline" after Enter or s on an offline machine, until the cursor moves.
    property string offlineNote: ""
    // A change on tailscaled's bus while a read runs asks for one more read after it.
    property bool stale: false
    readonly property bool busy: reader.running || toggler.running

    readonly property string sendBin: Quickshell.shellDir + "/bin/dots-taildrop-send"
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property var tones: L.plainTones(theme.tokens)
    readonly property var marks: T.tailscaleLook(theme.tokens ?? { color: {} })
    readonly property bool isOn: status.state === "on"
    readonly property var rows: isOn ? status.machines : []
    readonly property var current: rows[selected] ?? null
    readonly property Root.Motion motion: Root.Motion {
        shown: panel.shown
        tokens: panel.theme.tokens
    }

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        selected = 0;
        offlineNote = "";
        listed = false;
        read();
        watcher.running = true;
        shown = true;
        keyTarget.forceActiveFocus();
    }

    // The watch costs tailscaled a bus client and about 19 MiB, so it ends with the surface.
    function close() {
        shown = false;
        watcher.running = false;
        refresh.stop();
    }

    function read() {
        if (reader.running)
            stale = true;
        else
            reader.running = true;
    }

    // Called on each of the host window's frames; the first one after open() ends the timing.
    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function move(by) {
        selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }

    // A click on a row does what Enter does on it: copies its address.
    function clickRow(i) {
        selected = i;
        copy();
    }

    // The card closes on a copy, as Pass's does, and the island says what went on the clipboard.
    function copy() {
        if (!current)
            return;
        if (!current.online) {
            offlineNote = T.offlineText(current.name);
            return;
        }
        Quickshell.execDetached(["wl-copy", "--", current.ip]);
        theme.notice("Copied " + current.ip);
        close();
    }

    // dots-taildrop-send opens the chooser and outlives the card, so it starts detached after the close.
    function send() {
        if (!current)
            return;
        if (!current.online) {
            offlineNote = T.offlineText(current.name);
            return;
        }
        const target = current;
        close();
        Quickshell.execDetached([sendBin, target.name, target.ip]);
    }

    // Bare up after down brings the tailnet back with the settings it had.
    function toggle() {
        if (toggler.running || (status.state !== "on" && status.state !== "off"))
            return;
        toggler.wasOn = isOn;
        toggler.command = ["tailscale", isOn ? "down" : "up"];
        toggler.running = true;
    }

    function state() {
        const shownRows = [];
        for (let i = 0; i < rowRepeater.count; i++)
            shownRows.push(rowRepeater.itemAt(i).drawn());
        const keys = [];
        for (let i = 0; i < keyRepeater.count; i++)
            keys.push((keyRepeater.itemAt(i).keyLabel + " " + keyRepeater.itemAt(i).wordLabel).trim());
        const a = badgeBox.mapToItem(null, 0, 0);
        return JSON.stringify({
            loaded: true,
            open: shown,
            listed: listed,
            state: status.state,
            online: status.online,
            rows: shownRows,
            selected: selected,
            offlineLine: offlineLine.visible ? offlineLine.text : "",
            line: stateLine.visible ? stateLine.text : "",
            device: device.visible ? { name: deviceName.text, ip: deviceIp.text, tailnet: deviceTailnet.text } : null,
            heading: pill.text,
            badge: badgeText.text,
            badgeBox: { x: a.x, y: a.y, w: badgeBox.width * card.scale, h: badgeBox.height * card.scale },
            hint: keys.join(" · "),
            busy: busy,
            openMs: openMs,
            opens: opens,
            settled: motion.settled,
            drawing: panel.visible,
            cardBox: card.drawnBox(),
            keyboard: panel.Window.active
        });
    }

    onSelectedChanged: offlineNote = ""

    Process {
        id: reader
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            id: readOut
        }
        // A tailscaled that is not running fails the read, which parses as down.
        onExited: {
            panel.status = T.parseStatus(readOut.text, Date.now());
            panel.listed = true;
            panel.selected = Math.max(0, Math.min(panel.rows.length - 1, panel.selected));
            if (panel.stale) {
                panel.stale = false;
                refresh.restart();
            }
        }
    }

    // One line per change on tailscaled's bus; a watch that ends on its own is not restarted.
    Process {
        id: watcher
        command: ["tailscale", "debug", "watch-ipn"]
        stdout: SplitParser {
            onRead: refresh.restart()
        }
    }

    // A burst of bus lines, as a peer comes online, becomes one read.
    Root.Tick {
        id: refresh
        interval: 200
        onTriggered: panel.read()
    }

    Process {
        id: toggler
        property bool wasOn: false
        stderr: StdioCollector {
            id: toggleErr
        }
        onExited: code => {
            if (code !== 0)
                panel.theme.notice(T.toggleFailedText(wasOn, toggleErr.text));
            panel.read();
        }
    }

    Component.onCompleted: Root.State.loaded.push("tailscale")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "tailscale")

    visible: motion.drawing

    // Holds the keyboard while the card shows, the list or its one line: j and k move, Enter copies, s sends, t turns Tailscale off or on.
    Item {
        id: keyTarget
        Keys.onPressed: event => {
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                panel.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                panel.move(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                panel.copy();
            else if (event.key === Qt.Key_S)
                panel.send();
            else if (event.key === Qt.Key_T)
                panel.toggle();
            else if (event.key === Qt.Key_Escape)
                panel.close();
            else
                return;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: card.wash
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: 168
        width: 640
        height: column.implicitHeight
        tokens: panel.theme.tokens
        motion: panel.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            // The heading in the launcher's pill, and the ON or OFF badge across from it.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                spacing: 12

                Rectangle {
                    implicitWidth: pill.implicitWidth + 18
                    implicitHeight: pill.implicitHeight + 6
                    radius: 8
                    color: look.label.fill
                    Text {
                        id: pill
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: look.heading("tailscale", "")
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: badgeBox
                    readonly property var badge: marks.badge(isOn)
                    implicitWidth: badgeRow.implicitWidth + 18
                    implicitHeight: badgeRow.implicitHeight + 6
                    radius: badge.radius
                    color: badge.fill

                    Row {
                        id: badgeRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: badgeBox.badge.dot.size
                            height: width
                            radius: badgeBox.badge.dot.radius
                            color: badgeBox.badge.dot.fill
                            border.width: badgeBox.badge.dot.line !== "transparent" ? 1.5 : 0
                            border.color: badgeBox.badge.dot.line
                        }
                        Text {
                            id: badgeText
                            textFormat: Text.PlainText
                            text: badgeBox.badge.text
                            color: badgeBox.badge.color
                            font.family: fonts.ui
                            font.pixelSize: 11
                            font.letterSpacing: 0
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Rule {}

            // This device: its name, address and tailnet, kept while Tailscale is off.
            Item {
                id: device
                visible: !!status.self
                Layout.fillWidth: true
                implicitHeight: deviceColumn.implicitHeight + 16

                Rectangle {
                    x: 18
                    y: 12
                    width: parent.width - 36
                    height: deviceColumn.implicitHeight
                    radius: 12
                    color: tones.field ?? "transparent"
                }

                ColumnLayout {
                    id: deviceColumn
                    x: 32
                    y: 12
                    width: parent.width - 2 * x
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.bottomMargin: 12
                        spacing: 12

                        Tile {
                            color: tones.card
                            glyph: "laptop"
                            ink: c.muted
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                textFormat: Text.PlainText
                                text: "This device"
                                color: c.muted
                                font.family: fonts.ui
                                font.pixelSize: 11
                            }
                            Text {
                                id: deviceName
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: look.title(status.self ? status.self.name : "")
                                elide: Text.ElideRight
                                color: c.ink
                                font.family: fonts.ui
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                font.letterSpacing: 0
                            }
                        }

                        ColumnLayout {
                            spacing: 2

                            Text {
                                id: deviceIp
                                Layout.alignment: Qt.AlignRight
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: status.self ? status.self.ip : ""
                                color: c.ink
                                font.family: fonts.ui
                                font.pixelSize: 15
                                font.weight: Font.Medium
                            }
                            // The tailnet under the address.
                            Text {
                                id: deviceTailnet
                                Layout.alignment: Qt.AlignRight
                                textFormat: Text.PlainText
                                text: status.self ? status.self.tailnet : ""
                                color: c.muted
                                font.family: fonts.ui
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            // The list's head.
            RowLayout {
                visible: isOn
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: 12

                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: "Machines"
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }
            }

            Item {
                visible: isOn
                Layout.fillWidth: true
                implicitHeight: list.implicitHeight + 16

                Column {
                    id: list
                    y: 8
                    x: 8
                    width: parent.width - 2 * x

                    Repeater {
                        id: rowRepeater
                        model: rows

                        Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: index === panel.selected
                            // A click on the row does what Enter does on it.
                            Root.Click {
                                name: "tailscale-row:" + rowItem.index
                                onTapped: panel.clickRow(rowItem.index)
                            }
                            readonly property bool online: modelData.online
                            readonly property var mark: marks.status(modelData)
                            readonly property color textColor: isCurrent ? look.cursor.text : online ? c.ink : c.muted
                            // The row as drawn, for the state function: the address only where an online row draws one.
                            function drawn() {
                                const right = nameText.mapToItem(rowItem, nameText.width, 0).x;
                                return {
                                    name: nameText.text,
                                    ip: online ? detailText.text : "",
                                    status: statusText.text,
                                    lines: nameText.lineCount,
                                    elided: nameText.truncated,
                                    right: right,
                                    width: rowItem.width
                                };
                            }
                            width: list.width
                            implicitHeight: row.implicitHeight + 16
                            radius: look.cursor.radius
                            color: isCurrent ? look.cursor.fill : "transparent"

                            RowLayout {
                                id: row
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: anchors.leftMargin
                                spacing: 12

                                Tile {
                                    color: rowItem.isCurrent ? tones.card : look.tile.fill
                                    glyph: rowItem.modelData.phone ? "phone" : "box"
                                    ink: rowItem.isCurrent ? look.cursor.text : rowItem.online ? c.muted : marks.dotLine
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        id: nameText
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: look.title(rowItem.modelData.name)
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                        color: rowItem.textColor
                                        font.family: look.name.font
                                        font.pixelSize: 15
                                        font.weight: rowItem.isCurrent ? look.cursor.weight : !rowItem.online ? Font.Normal : look.name.weight
                                        font.letterSpacing: 0
                                    }
                                    Text {
                                        id: detailText
                                        textFormat: Text.PlainText
                                        text: marks.detail(rowItem.modelData)
                                        color: c.muted
                                        font.family: fonts.ui
                                        font.pixelSize: 12
                                    }
                                }

                                // The state dot and word.
                                Row {
                                    Layout.preferredWidth: implicitWidth
                                    spacing: 6

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: rowItem.mark.dot
                                        border.width: rowItem.online ? 0 : 1.5
                                        border.color: marks.dotLine
                                    }
                                    Text {
                                        id: statusText
                                        textFormat: Text.PlainText
                                        text: rowItem.mark.word
                                        color: c.muted
                                        font.family: fonts.ui
                                        font.pixelSize: 11
                                        font.letterSpacing: 0
                                    }
                                }

                                Rectangle {
                                    visible: rowItem.isCurrent
                                    implicitWidth: 22
                                    implicitHeight: 18
                                    radius: 6
                                    color: tones.card
                                    Text {
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: look.cursor.badge
                                        color: look.cursor.text
                                        font.family: fonts.ui
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        id: offlineLine
                        visible: panel.offlineNote !== ""
                        width: list.width
                        textFormat: Text.PlainText
                        leftPadding: 20
                        topPadding: 8
                        bottomPadding: 3
                        text: panel.offlineNote
                        elide: Text.ElideRight
                        color: c.danger
                        font.family: look.small.font
                        font.pixelSize: look.small.size + 1
                        font.letterSpacing: look.small.spacing
                    }
                }
            }

            // Off, logged out, starting or tailscaled away: one line where the list goes, beside a power tile.
            RowLayout {
                visible: !isOn && listed
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: 28
                Layout.bottomMargin: 28
                spacing: 12

                Tile {
                    color: look.tile.fill
                    glyph: "power"
                    ink: c.muted
                }
                Text {
                    id: stateLine
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: T.stateText(status.state)
                    color: c.muted
                    font.family: fonts.ui
                    font.pixelSize: 15
                    font.letterSpacing: 0
                }
            }

            Rule {}

            // The key strip as Pass draws it, each pair in a chip.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: 10
                Layout.bottomMargin: Layout.topMargin
                spacing: 8

                Repeater {
                    id: keyRepeater
                    model: T.tailscaleKeys(look, status.state)

                    Rectangle {
                        id: keyPair
                        required property var modelData
                        readonly property string keyLabel: keyText.text
                        readonly property string wordLabel: wordText.text
                        width: pair.implicitWidth + 14
                        height: pair.implicitHeight + 6
                        radius: 6
                        color: look.chip.fill

                        Row {
                            id: pair
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                id: keyText
                                textFormat: Text.PlainText
                                text: keyPair.modelData.key
                                color: look.chip.key
                                font.family: fonts.mono
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                                font.bold: true
                            }
                            Text {
                                id: wordText
                                visible: text !== ""
                                textFormat: Text.PlainText
                                text: keyPair.modelData.word
                                color: c.muted
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                            }
                        }
                    }
                }
            }
        }
    }

    // The 1 px slot between a card's parts; it draws no line, so the card reads as one piece.
    component Rule: Item {
        Layout.fillWidth: true
        implicitHeight: 1
    }

    // A 32 px tile with a line glyph: a laptop, a machine, a phone or the power mark.
    component Tile: Rectangle {
        id: tile
        property string glyph: "box"
        property color ink: "black"
        implicitWidth: 32
        implicitHeight: 32
        radius: 9

        Rectangle {
            visible: tile.glyph === "laptop" || tile.glyph === "box" || tile.glyph === "phone"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: tile.glyph === "laptop" ? -1.5 : 0
            width: tile.glyph === "phone" ? 7 : tile.glyph === "laptop" ? 11 : 12
            height: tile.glyph === "phone" ? 13 : tile.glyph === "laptop" ? 7.5 : 8
            radius: tile.glyph === "box" ? 2 : 1.5
            color: "transparent"
            border.width: 1.5
            border.color: tile.ink
        }
        Rectangle {
            visible: tile.glyph !== "power"
            x: tile.glyph === "laptop" ? 9 : tile.glyph === "phone" ? 15 : 13
            y: tile.glyph === "laptop" ? 20.25 : tile.glyph === "phone" ? 19.75 : 15.25
            width: tile.glyph === "laptop" ? 14 : 2
            height: 1.5
            radius: 0.75
            color: tile.ink
        }
        Shape {
            visible: tile.glyph === "power"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: tile.ink
                strokeWidth: 1.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 16
                startY: 9.8
                PathLine {
                    x: 16
                    y: 15.2
                }
                PathMove {
                    x: 12.6
                    y: 11.9
                }
                PathArc {
                    x: 19.4
                    y: 11.9
                    radiusX: 5.2
                    radiusY: 5.2
                    useLargeArc: true
                }
            }
        }
    }
}

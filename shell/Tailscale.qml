import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as IT
import "lib/tailscale.mjs" as T

// The tailnet drawn inside the island (board 8): a switch, this device as a tile, then the machines; or one line when Tailscale is not on. tailscale runs only while it shows.
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
    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, and the tones lifted to read on it.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? IT.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property bool isOn: status.state === "on"
    readonly property var rows: isOn ? status.machines : []
    readonly property var current: rows[selected] ?? null
    // The island reports this as its surface while Tailscale shows, and grows to this width for it (board 8).
    readonly property string name: "tailscale"
    readonly property int wantWidth: 640
    // True once the island has come to rest on Tailscale; the surfaces' window sets it.
    property bool settled: false
    implicitHeight: column.implicitHeight + 32

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        selected = 0;
        offlineNote = "";
        listed = false;
        shown = true;
        read();
        watcher.running = true;
        keyTarget.forceActiveFocus();
    }

    // The watch costs tailscaled a bus client and about 19 MiB, so it ends with the surface.
    function close() {
        shown = false;
        watcher.running = false;
        refresh.stop();
    }

    // A read that ends after the close, or a change that lands then, starts nothing.
    function read() {
        if (!shown)
            return;
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

    // The surface closes on a copy, as Pass's does, and the island says what went on the clipboard.
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

    // dots-taildrop-send opens the file picker, another surface, and outlives this one, so Tailscale closes first and the send starts detached.
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
        return JSON.stringify({
            loaded: true,
            open: shown,
            listed: listed,
            state: status.state,
            online: status.online,
            on: isOn,
            switchOn: tsSwitch.on,
            rows: shownRows,
            selected: selected,
            offlineLine: offlineLine.visible ? offlineLine.text : "",
            line: stateLine.visible ? stateLine.text : "",
            device: device.visible ? { name: deviceName.text, line: deviceLine.text, ip: status.self.ip } : null,
            heading: heading.text,
            ink: String(on),
            fill: String(fill),
            ok: String(tones.ok),
            muted: String(tones.muted),
            busy: busy,
            openMs: openMs,
            opens: opens,
            settled: panel.settled,
            drawing: panel.visible,
            width: panel.width,
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

    // Holds the keyboard while Tailscale shows, the list or its one line: j and k move, Enter copies, s sends, t turns Tailscale off or on.
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

    ColumnLayout {
        id: column
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 10

            Text {
                id: heading
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: "Tailscale"
                color: panel.on
                font.family: fonts.ui ?? ""
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            // A 38 x 22 switch, on while tailscaled runs the tailnet; a click does what t does.
            Rectangle {
                id: tsSwitch
                property bool on: panel.isOn
                implicitWidth: 38
                implicitHeight: 22
                radius: 11
                color: on ? panel.on : Qt.alpha(panel.on, 0.16)

                Rectangle {
                    x: tsSwitch.on ? parent.width - width - 3 : 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 8
                    color: tsSwitch.on ? panel.fill : panel.tones.muted
                }
                Root.Click {
                    name: "tailscale-switch"
                    onTapped: panel.toggle()
                }
            }
        }

        // This device, kept while Tailscale is off.
        Rectangle {
            id: device
            visible: !!status.self
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            radius: 14
            color: Qt.alpha(panel.on, 0.07)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Circle {
                    glyph: 0xF0379
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        id: deviceName
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: status.self ? status.self.name : ""
                        elide: Text.ElideRight
                        color: panel.on
                        font.family: fonts.ui ?? ""
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                    Text {
                        id: deviceLine
                        textFormat: Text.PlainText
                        text: status.self ? "this device · " + status.self.ip : ""
                        color: panel.tones.muted
                        font.family: fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                }
            }
        }

        ColumnLayout {
            visible: isOn
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                id: rowRepeater
                model: rows

                Rectangle {
                    id: rowItem
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: index === panel.selected
                    readonly property bool online: modelData.online
                    readonly property color ink: online ? panel.on : panel.tones.muted
                    // A click on the row does what Enter does on it.
                    Root.Click {
                        name: "tailscale-row:" + rowItem.index
                        onTapped: panel.clickRow(rowItem.index)
                    }
                    // The row as drawn, for the state function: the address only where an online row draws one.
                    function drawn() {
                        const right = nameText.mapToItem(rowItem, nameText.width, 0).x;
                        return {
                            name: nameText.text,
                            ip: online ? detailText.text : "",
                            line: detailText.text,
                            online: online,
                            dot: String(dot.color),
                            ink: String(nameText.color),
                            fill: String(color),
                            send: sendButton.visible ? { text: sendText.text, fill: String(sendButton.color), ink: String(sendText.color) } : null,
                            lines: nameText.lineCount,
                            elided: nameText.truncated,
                            right: right,
                            width: rowItem.width
                        };
                    }
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 12
                    color: isCurrent ? Qt.alpha(panel.on, 0.12) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 12

                        Rectangle {
                            id: dot
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: rowItem.online ? panel.tones.ok : Qt.alpha(panel.on, 0.16)
                        }
                        Text {
                            id: nameText
                            textFormat: Text.PlainText
                            text: rowItem.modelData.name
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            // A long name keeps to half the row, so its address and the Send button stay in view.
                            Layout.maximumWidth: rowItem.width / 2
                            color: rowItem.ink
                            font.family: fonts.ui ?? ""
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            id: detailText
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: T.rowLine(rowItem.modelData)
                            elide: Text.ElideRight
                            color: panel.tones.muted
                            font.family: fonts.ui ?? ""
                            font.pixelSize: 12
                        }

                        // The selected row's Send: inverted, the island's text as its fill.
                        Rectangle {
                            id: sendButton
                            visible: rowItem.isCurrent
                            implicitHeight: 32
                            implicitWidth: sendRow.implicitWidth + 24
                            radius: 10
                            color: panel.on

                            Row {
                                id: sendRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: String.fromCodePoint(0xF048A)
                                    color: panel.fill
                                    font.family: "Symbols Nerd Font Mono"
                                    font.pixelSize: 12
                                }
                                Text {
                                    id: sendText
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: "Send"
                                    color: panel.fill
                                    font.family: fonts.ui ?? ""
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }
                            Root.Click {
                                name: "tailscale-send"
                                onTapped: panel.send()
                            }
                        }
                    }
                }
            }

            Text {
                id: offlineLine
                visible: panel.offlineNote !== ""
                Layout.fillWidth: true
                textFormat: Text.PlainText
                leftPadding: 12
                text: panel.offlineNote
                elide: Text.ElideRight
                color: panel.tones.danger
                font.family: fonts.ui ?? ""
                font.pixelSize: 12
            }
        }

        // Off, logged out, starting or tailscaled away: one line where the list goes.
        Rectangle {
            visible: !isOn && listed
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            radius: 14
            color: Qt.alpha(panel.on, 0.07)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Circle {
                    glyph: 0xF0425
                }
                Text {
                    id: stateLine
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: T.stateText(status.state)
                    color: panel.tones.muted
                    font.family: fonts.ui ?? ""
                    font.pixelSize: 13
                }
            }
        }
    }

    // A 36 px circle in the 0.16 wash of the island's text, with a Nerd Font glyph in it.
    component Circle: Rectangle {
        property int glyph: 0
        implicitWidth: 36
        implicitHeight: 36
        radius: 18
        color: Qt.alpha(panel.on, 0.16)

        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: parent.glyph ? String.fromCodePoint(parent.glyph) : ""
            color: panel.on
            font.family: "Symbols Nerd Font Mono"
            font.pixelSize: 17
        }
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/dns.mjs" as D
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T

// DNS Shield drawn inside the island on its fill (board 8): the devices on the left, the cursor device's tile on the right. Space, 1-5, o, O, a and n write through dots-dns, then it reads state again.
Item {
    id: panel

    required property var theme
    property bool shown: false
    property int opens: 0
    // The last state read, kept while the surface stays loaded, so a reopen draws it at once.
    property string stateText: ""
    property real now: Date.now()
    // The countdown's clock: a timed open's chip and bar redraw from it, the rows do not.
    property real clock: Date.now()
    // The cursor's place among the device rows.
    property int selected: 0
    property bool fieldOpen: false
    // Keys pressed while a write or a read runs; each waits for the state before it, so a second space is never lost.
    property var pending: []
    // The device the cursor moves to once the next state lists it: one just added.
    property string wantKey: ""
    // The add sub-list: the router's leases, the cursor among them, and whether the name field has the keyboard.
    property bool adding: false
    property string leasesText: "[]"
    property int leaseSelected: 0
    property bool naming: false
    // The reason dots-dns gave for the last refused write, drawn in the tile until the tick clears it.
    property string writeError: ""
    readonly property bool busy: cachedReader.running || reader.running || writer.running || leasesReader.running

    readonly property string command: Quickshell.env("DOTS_DNS") || Quickshell.shellDir + "/bin/dots-dns"
    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, and the tones lifted to read on it.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property var marks: D.dnsLook(tokens)
    readonly property var view: D.dnsView(stateText, now)
    readonly property var items: D.dnsItems(view)
    readonly property var stops: items.map((it, i) => it.stop ? i : -1).filter(i => i >= 0)
    readonly property int current: stops.length ? stops[Math.min(selected, stops.length - 1)] : -1
    readonly property var device: current >= 0 ? items[current] : null
    readonly property var paneView: device ? D.paneOf(device) : null
    readonly property bool timedOpen: !!device && device.openUntil !== null
    readonly property bool paneFull: !!device && (device.kid || timedOpen)
    readonly property var leases: D.leasesView(leasesText)
    readonly property var lease: leases.length ? leases[Math.min(leaseSelected, leases.length - 1)] : null
    readonly property bool anyTimed: items.some(it => it.kind === "device" && it.openUntil !== null)
    // The island reports this as its surface while DNS Shield shows, and grows to this width for it (board 8).
    readonly property string name: "dns"
    readonly property int wantWidth: 880
    // True once the island has come to rest on DNS Shield; the surfaces' window sets it.
    property bool settled: false
    implicitHeight: card.height

    // The last full state on disk draws at once, then the full read redraws it.
    function open(t0) {
        opens += 1;
        selected = 0;
        fieldOpen = false;
        adding = false;
        clock = Date.now();
        if (!busy)
            cachedReader.running = true;
        shown = true;
        keyTarget.forceActiveFocus();
    }

    // A write that runs finishes; the keys still waiting are dropped and nothing reads again.
    function close() {
        shown = false;
        fieldOpen = false;
        adding = false;
        pending = [];
    }

    // Nothing here is timed yet; the host calls this on every frame.
    function swapped() {
    }

    function move(by) {
        selected = Math.max(0, Math.min(stops.length - 1, selected + by));
    }

    // Enter runs nothing on a device, so a click on one moves the cursor there and its tile shows; a caption takes none.
    function clickRow(i) {
        // While the allow field is open its Enter writes to the selected device, so the cursor stays where the field was opened.
        if (fieldOpen)
            return;
        const s = stops.indexOf(i);
        if (s >= 0)
            selected = s;
    }

    // State that will not parse as an object keeps the rows drawn.
    function take(text) {
        if (text.trim().charAt(0) !== "{")
            return;
        stateText = text;
        now = Date.now();
        clock = now;
        if (wantKey !== "") {
            const i = stops.findIndex(s => items[s].key === wantKey);
            if (i >= 0)
                selected = i;
            wantKey = "";
        }
    }

    function act(a) {
        if (!device)
            return;
        queue(Object.assign({ key: device.key }, a));
    }

    function queue(a) {
        pending = pending.concat([a]);
        if (!busy)
            next();
    }

    function next() {
        if (!shown || !pending.length)
            return;
        const a = pending[0];
        pending = pending.slice(1);
        run(a);
    }

    // A key is turned into its write against the state read after the one before it.
    function run(a) {
        const d = items.find(i => i.kind === "device" && i.key === a.key);
        let args = null;
        if (a.kind === "add")
            args = a.args;
        else if (d)
            args = a.kind === "kid" ? D.kidArgs(d) : a.kind === "category" ? D.categoryArgs(d, a.n) : a.kind === "open" ? D.openArgs(d, a.length) : D.allowArgs(d, a.text);
        if (!args) {
            next();
            return;
        }
        writer.command = [command].concat(args);
        writer.running = true;
    }

    function openField() {
        if (!device || !paneFull || device.dim)
            return;
        fieldInput.text = "";
        fieldOpen = true;
        fieldInput.forceActiveFocus();
    }

    function closeField(add) {
        if (add)
            act({ kind: "allow", text: fieldInput.text });
        fieldOpen = false;
        keyTarget.forceActiveFocus();
    }

    // n lists the router's leases; an unreachable router has none to give.
    function openAdd() {
        if (view.routerLine !== "" || leasesReader.running)
            return;
        leasesText = "[]";
        leaseSelected = 0;
        nameInput.text = "";
        naming = false;
        adding = true;
        leasesReader.running = true;
    }

    function closeAdd() {
        adding = false;
        naming = false;
        keyTarget.forceActiveFocus();
    }

    function moveLease(by) {
        leaseSelected = Math.max(0, Math.min(leases.length - 1, leaseSelected + by));
        nameInput.text = lease ? lease.field : "";
    }

    // Tab moves between the leases and the name field; the field takes the keyboard with its text selected, so typing replaces it.
    function toggleNaming() {
        naming = !naming;
        if (naming) {
            nameInput.forceActiveFocus();
            nameInput.selectAll();
        } else {
            keyTarget.forceActiveFocus();
        }
    }

    function addLease() {
        const args = D.addArgs(lease, nameInput.text);
        if (!args)
            return;
        wantKey = "router:" + lease.mac;
        closeAdd();
        queue({ kind: "add", args: args });
    }

    // An item's box as drawn this frame, in the window's pixels.
    function boxOf(item) {
        const a = item.mapToItem(null, 0, 0);
        return { x: a.x, y: a.y, w: item.width, h: item.height };
    }

    function state() {
        const groups = [];
        const rows = [];
        let box = null;
        for (let i = 0; i < rowRepeater.count; i++) {
            const r = rowRepeater.itemAt(i);
            if (r.it.kind === "group")
                groups.push({ text: r.groupLabel, line: r.groupLine });
            else if (r.it.kind === "device")
                rows.push(r.drawn());
            if (r.isCurrent)
                box = panel.boxOf(r);
        }
        const cats = [];
        for (let i = 0; i < catRepeater.count; i++)
            cats.push(catRepeater.itemAt(i).drawn());
        const allow = [];
        for (let i = 0; i < allowRepeater.count; i++)
            allow.push(allowRepeater.itemAt(i).text);
        const blocks = [];
        for (let i = 0; i < blockRepeater.count; i++)
            blocks.push(blockRepeater.itemAt(i).drawn());
        const leaseRows = [];
        for (let i = 0; i < leaseRepeater.count; i++)
            leaseRows.push(leaseRepeater.itemAt(i).drawn());
        const openButtons = [];
        for (let i = 0; i < openRepeater.count; i++)
            openButtons.push(openRepeater.itemAt(i).label);
        return JSON.stringify({
            // The latest notice, drawn at the tool's foot while the island holds the tool.
            note: toolNote.text,
            loaded: true,
            open: shown,
            visible: panel.visible,
            drawing: panel.visible,
            settled: panel.settled,
            keyboard: panel.Window.active,
            busy: busy,
            opens: opens,
            heading: heading.text,
            addButton: addButton.visible ? addLabel.text : "",
            cursor: device ? device.key : "",
            carried: rows.filter(r => r.key.startsWith("carried:")).length,
            router: rows.filter(r => r.key.startsWith("router:")).length,
            groups: groups,
            rows: rows,
            cursorBox: box,
            cardBox: panel.boxOf(card),
            listWidth: list.width,
            tileBox: tile.visible ? panel.boxOf(tile) : null,
            pane: {
                name: paneName.text,
                kid: kidSwitch.on,
                categories: cats,
                open: openRow.visible ? openCaption.text : "",
                openButtons: openButtons,
                left: leftText.visible ? leftText.text : "",
                allow: allow,
                blocks: blocks
            },
            field: fieldOpen ? fieldInput.text : null,
            add: adding ? {
                head: leasesHead.text,
                leases: leaseRows,
                listWidth: addList.width,
                noteLines: addNote.lineCount,
                cursor: lease ? lease.mac : "",
                name: nameInput.text,
                naming: naming,
                host: leaseHost.text,
                address: leaseAddress.text
            } : null,
            error: writeErrorText.visible ? writeErrorText.text : "",
            errorLines: writeErrorText.lineCount,
            errorTruncated: writeErrorText.truncated,
            errorColor: String(writeErrorText.color),
            footer: footerText.text
        });
    }

    Process {
        id: cachedReader
        command: [panel.command, "state", "--cached"]
        stdout: StdioCollector {
            id: cachedOut
        }
        // A surface closed while the cache was read starts no full read.
        onExited: {
            panel.take(cachedOut.text);
            if (panel.shown)
                reader.running = true;
        }
    }

    Process {
        id: reader
        command: [panel.command, "state"]
        stdout: StdioCollector {
            id: readOut
        }
        onExited: {
            panel.take(readOut.text);
            panel.next();
        }
    }

    // It reads state after every write, so a refused write leaves the rows as dots-dns has them, and shows dots-dns's reason.
    Process {
        id: writer
        stderr: StdioCollector {
            id: writerErr
        }
        onExited: code => {
            panel.writeError = code === 0 ? "" : D.writeError(writerErr.text);
            if (panel.writeError !== "")
                writeErrorTick.restart();
            if (panel.shown)
                reader.running = true;
        }
    }

    Process {
        id: leasesReader
        command: [panel.command, "leases"]
        stdout: StdioCollector {
            id: leasesOut
        }
        onExited: {
            panel.leasesText = leasesOut.text;
            nameInput.text = panel.lease ? panel.lease.field : "";
            panel.next();
        }
    }

    Root.Tick {
        id: writeErrorTick
        interval: 5000
        onTriggered: panel.writeError = ""
    }

    // A timed open counts down once a second while DNS Shield shows; at its end the collector brings Kid back, so it reads state again.
    Root.Tick {
        interval: 1000
        repeat: true
        running: panel.shown && panel.anyTimed
        onTriggered: {
            panel.clock = Date.now();
            const ended = panel.items.some(it => it.kind === "device" && it.openUntil !== null && it.openUntil * 1000 <= panel.clock);
            if (ended && !panel.busy)
                reader.running = true;
        }
    }

    Component.onCompleted: Root.State.loaded.push("dns")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "dns")

    // Holds the keyboard while DNS Shield shows, unless the allow field or the name field has it.
    Item {
        id: keyTarget
        Keys.onPressed: event => {
            if (panel.adding) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                    panel.moveLease(1);
                else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                    panel.moveLease(-1);
                else if (event.key === Qt.Key_Tab)
                    panel.toggleNaming();
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    panel.addLease();
                else if (event.key === Qt.Key_Escape)
                    panel.closeAdd();
                else
                    return;
            } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                panel.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                panel.move(-1);
            else if (event.key === Qt.Key_Space)
                panel.act({ kind: "kid" });
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5)
                panel.act({ kind: "category", n: event.key - Qt.Key_0 });
            else if (event.key === Qt.Key_O)
                panel.act({ kind: "open", length: event.text === "O" ? "2h" : "30m" });
            else if (event.key === Qt.Key_A)
                panel.openField();
            else if (event.key === Qt.Key_N)
                panel.openAdd();
            else if (event.key === Qt.Key_Escape)
                panel.close();
            else
                return;
            event.accepted = true;
        }
    }

    // A press anywhere on the tool is on its card, so the surfaces' window never takes it for a click outside.
    Item {
        objectName: "card"
        anchors.fill: parent
    }

    // The island draws the fill and plays the open; this is its content, 16 px in from its edge.
    Item {
        id: card
        width: parent.width
        height: column.implicitHeight + 32

        Column {
            id: column
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 8

            // The shield and the name, the state's age, and Add device.
            Item {
                width: column.width
                height: 36

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F0498}"
                        font.pixelSize: 17
                    }
                    Text {
                        id: heading
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: panel.marks.heading(panel.adding)
                        color: panel.on
                        font.family: panel.fonts.ui ?? ""
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Text {
                        id: footerText
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: panel.view.footer
                        color: panel.tones.muted
                        font.family: panel.fonts.ui ?? ""
                        font.pixelSize: 11
                    }
                    Rectangle {
                        id: addButton
                        visible: !panel.adding
                        anchors.verticalCenter: parent.verticalCenter
                        width: addRow.implicitWidth + 24
                        height: 32
                        radius: 10
                        color: Qt.alpha(panel.on, 0.07)
                        Row {
                            id: addRow
                            anchors.centerIn: parent
                            spacing: 6
                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{F0415}"
                                font.pixelSize: 13
                            }
                            Text {
                                id: addLabel
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: "Add device"
                                color: panel.on
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            // The two panes: about a third for the list, the rest for the tile.
            Item {
                width: column.width
                height: Math.max(panel.adding ? addList.height : list.height, panel.adding ? addTile.height : tile.visible ? tile.height : 0)

                // The devices under their two captions, the cursor row on a lighter tile.
                Column {
                    id: list
                    visible: !panel.adding
                    width: 340
                    spacing: 4

                    Repeater {
                        id: rowRepeater
                        model: panel.items

                        Item {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property var it: modelData
                            readonly property bool isCurrent: index === panel.current
                            readonly property bool hasLine: it.kind === "group" && (it.line || "") !== ""
                            readonly property string groupLabel: it.kind === "group" ? captionText.text : ""
                            readonly property string groupLine: hasLine ? groupLineText.text : ""
                            function drawn() {
                                return {
                                    key: it.key,
                                    glyph: rowGlyph.text,
                                    name: nameText.text,
                                    badge: chip.visible ? chipText.text : "",
                                    chipFill: chip.visible ? String(chip.color) : "",
                                    chipInk: chip.visible ? String(chipText.color) : "",
                                    age: ageText.text,
                                    truncated: nameText.truncated,
                                    lines: nameText.lineCount,
                                    opacity: deviceRow.opacity,
                                    nameBox: panel.boxOf(nameText)
                                };
                            }

                            width: list.width
                            height: it.kind === "group" ? (hasLine ? 40 : 24) : 44

                            // A click on the row does what Enter does on it.
                            Root.Click {
                                name: "dns-row:" + (rowItem.it.key ?? rowItem.index)
                                onTapped: panel.clickRow(rowItem.index)
                            }

                            Text {
                                id: captionText
                                visible: rowItem.it.kind === "group"
                                x: 4
                                height: 22
                                verticalAlignment: Text.AlignBottom
                                textFormat: Text.PlainText
                                text: rowItem.it.kind === "group" ? panel.marks.group(rowItem.it).text : ""
                                color: panel.tones.muted
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 10
                                font.letterSpacing: 1.2
                            }
                            // Why the router's rows are dim and since when.
                            Text {
                                id: groupLineText
                                visible: rowItem.hasLine
                                x: 4
                                y: 24
                                width: parent.width - 8
                                textFormat: Text.PlainText
                                text: rowItem.it.line || ""
                                elide: Text.ElideRight
                                color: panel.tones.danger
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 11
                            }

                            Rectangle {
                                id: deviceRow
                                visible: rowItem.it.kind === "device"
                                anchors.fill: parent
                                radius: 12
                                color: rowItem.isCurrent ? Qt.alpha(panel.on, 0.12) : "transparent"
                                opacity: rowItem.it.dim ? 0.45 : 1

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 12
                                    width: parent.width - 24
                                    spacing: 10
                                    Glyph {
                                        id: rowGlyph
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16
                                        text: rowItem.it.glyph || ""
                                    }
                                    Text {
                                        id: nameText
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - rowGlyph.width - (chip.visible ? chip.width + 10 : 0) - ageText.width - 30
                                        textFormat: Text.PlainText
                                        text: rowItem.it.name || ""
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                        color: panel.on
                                        font.family: panel.fonts.ui ?? ""
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    // Kid inverted, or a timed open's minutes left on a lighter chip.
                                    Rectangle {
                                        id: chip
                                        readonly property bool kid: rowItem.it.kid === true
                                        visible: chipText.text !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: chipText.implicitWidth + 16
                                        height: 20
                                        radius: 10
                                        color: kid ? panel.on : Qt.alpha(panel.on, 0.12)
                                        Text {
                                            id: chipText
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: rowItem.it.kind === "device" ? D.badgeText(rowItem.it, panel.clock) : ""
                                            color: chip.kid ? panel.fill : panel.on
                                            font.family: panel.fonts.ui ?? ""
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }
                                    Text {
                                        id: ageText
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 60
                                        horizontalAlignment: Text.AlignRight
                                        textFormat: Text.PlainText
                                        text: rowItem.it.age || ""
                                        color: panel.tones.muted
                                        font.family: panel.fonts.ui ?? ""
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }

                // The add list in place of the devices: the router's leases not yet listed.
                Column {
                    id: addList
                    visible: panel.adding
                    width: 340
                    spacing: 4

                    Item {
                        width: addList.width
                        height: 24
                        Text {
                            id: leasesHead
                            x: 4
                            height: 22
                            verticalAlignment: Text.AlignBottom
                            textFormat: Text.PlainText
                            text: panel.marks.leasesHead(panel.leases.length).text
                            color: panel.tones.muted
                            font.family: panel.fonts.ui ?? ""
                            font.pixelSize: 10
                            font.letterSpacing: 1.2
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            height: 22
                            verticalAlignment: Text.AlignBottom
                            textFormat: Text.PlainText
                            text: panel.marks.leasesHead(panel.leases.length).right
                            color: panel.tones.muted
                            font.family: panel.fonts.ui ?? ""
                            font.pixelSize: 10
                            font.letterSpacing: 1.2
                        }
                    }

                    Repeater {
                        id: leaseRepeater
                        model: panel.leases
                        Rectangle {
                            id: leaseRow
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: index === Math.min(panel.leaseSelected, panel.leases.length - 1)
                            function drawn() {
                                return { mac: modelData.mac, name: leaseName.text, ip: leaseIp.text, truncated: leaseName.truncated, lines: leaseName.lineCount, ipTruncated: leaseIp.truncated, ipRight: leaseIp.mapToItem(null, leaseIp.width, 0).x, ipLeft: leaseIp.mapToItem(null, 0, 0).x, left: leaseRow.mapToItem(null, 0, 0).x };
                            }
                            width: addList.width
                            height: 44
                            radius: 12
                            color: isCurrent ? Qt.alpha(panel.on, 0.12) : "transparent"
                            Text {
                                id: leaseName
                                anchors.verticalCenter: parent.verticalCenter
                                x: 12
                                width: parent.width - 24 - leaseIp.width - 10
                                textFormat: Text.PlainText
                                text: leaseRow.modelData.name
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                color: panel.on
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                id: leaseIp
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                // A router's lease is anyone's to write, so its address keeps to its column.
                                width: Math.min(implicitWidth, parent.width * 0.4)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                                text: leaseRow.modelData.ip
                                color: panel.tones.muted
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // The cursor device's tile: its Kid mode switch, the five categories, Open for a while, its allow list and its recent blocks.
                Rectangle {
                    id: tile
                    visible: !panel.adding && !!panel.device
                    x: 352
                    width: parent.width - 352
                    height: tileColumn.implicitHeight + 24
                    radius: 14
                    color: Qt.alpha(panel.on, 0.07)

                    Column {
                        id: tileColumn
                        x: 14
                        y: 12
                        width: parent.width - 28
                        spacing: 4

                        Item {
                            width: tileColumn.width
                            height: 36
                            Text {
                                id: paneName
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - kidRow.width - 10
                                textFormat: Text.PlainText
                                text: panel.paneView ? panel.paneView.name : ""
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                color: panel.on
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Row {
                                id: kidRow
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: "Kid mode"
                                    color: panel.tones.muted
                                    font.family: panel.fonts.ui ?? ""
                                    font.pixelSize: 12
                                }
                                Switch {
                                    id: kidSwitch
                                    anchors.verticalCenter: parent.verticalCenter
                                    on: !!panel.device && panel.device.kid
                                }
                            }
                        }

                        Repeater {
                            id: catRepeater
                            model: panel.paneFull && panel.paneView ? panel.paneView.categories : []
                            Column {
                                id: catRow
                                required property var modelData
                                readonly property bool hasNote: modelData.key === "youtube_kids" && !!panel.paneView && panel.paneView.shared !== ""
                                function drawn() {
                                    return { label: catLabel.text, value: catValue.text, on: catSwitch.on, note: hasNote ? catNote.text : "" };
                                }
                                width: tileColumn.width
                                Item {
                                    width: catRow.width
                                    height: 36
                                    Text {
                                        id: catLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        textFormat: Text.PlainText
                                        text: catRow.modelData.label
                                        color: panel.on
                                        font.family: panel.fonts.ui ?? ""
                                        font.pixelSize: 13
                                    }
                                    Row {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10
                                        Text {
                                            id: catValue
                                            anchors.verticalCenter: parent.verticalCenter
                                            textFormat: Text.PlainText
                                            text: catRow.modelData.value
                                            color: panel.tones.muted
                                            font.family: panel.fonts.ui ?? ""
                                            font.pixelSize: 12
                                        }
                                        Switch {
                                            id: catSwitch
                                            anchors.verticalCenter: parent.verticalCenter
                                            on: catRow.modelData.on
                                        }
                                    }
                                }
                                // On a router row YouTube Kids is one setting for every home-router device, so a change to it changes them all.
                                Text {
                                    id: catNote
                                    visible: catRow.hasNote
                                    bottomPadding: 4
                                    textFormat: Text.PlainText
                                    text: panel.paneView ? panel.paneView.shared : ""
                                    color: panel.tones.muted
                                    font.family: panel.fonts.ui ?? ""
                                    font.pixelSize: 11
                                }
                            }
                        }

                        // Open for a while, or a timed open's end and the time left over a bar of its length.
                        Item {
                            id: openRow
                            visible: panel.paneFull
                            width: tileColumn.width
                            height: 44
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                Text {
                                    id: openCaption
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: panel.timedOpen && panel.paneView ? panel.paneView.until : "Open for a while"
                                    color: panel.tones.muted
                                    font.family: panel.fonts.ui ?? ""
                                    font.pixelSize: 12
                                }
                                Text {
                                    id: leftText
                                    visible: panel.timedOpen
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: panel.timedOpen ? D.badgeText(panel.device, panel.clock) + " left" : ""
                                    color: panel.on
                                    font.family: panel.fonts.ui ?? ""
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Repeater {
                                    id: openRepeater
                                    model: ["30 min", "2 h"]
                                    Rectangle {
                                        required property string modelData
                                        readonly property string label: modelData
                                        width: openLabel.implicitWidth + 24
                                        height: 30
                                        radius: 10
                                        color: Qt.alpha(panel.on, 0.12)
                                        Text {
                                            id: openLabel
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: parent.modelData
                                            color: panel.on
                                            font.family: panel.fonts.ui ?? ""
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: panel.timedOpen
                            width: tileColumn.width
                            height: 4
                            radius: 2
                            color: Qt.alpha(panel.on, 0.16)
                            Rectangle {
                                width: parent.width * (panel.timedOpen ? D.openFraction(panel.device, panel.clock) : 0)
                                height: parent.height
                                radius: parent.radius
                                color: panel.on
                            }
                        }

                        // The allow list beside the recent blocks, so the tile stays short.
                        Row {
                            width: tileColumn.width
                            topPadding: 6
                            spacing: 12

                            Column {
                                visible: panel.paneFull
                                width: (tileColumn.width - 12) / 2
                                spacing: 2
                                Caption {
                                    text: "Allowed sites · " + (panel.paneView ? panel.paneView.allow.length : 0)
                                }
                                Repeater {
                                    id: allowRepeater
                                    model: panel.paneFull && panel.paneView ? panel.paneView.allow : []
                                    Text {
                                        required property var modelData
                                        width: parent.width
                                        height: 22
                                        verticalAlignment: Text.AlignVCenter
                                        textFormat: Text.PlainText
                                        text: modelData
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                        color: panel.on
                                        font.family: panel.fonts.ui ?? ""
                                        font.pixelSize: 12
                                    }
                                }
                                // One line for a domain to allow: Enter adds it, Esc leaves it.
                                Rectangle {
                                    visible: panel.fieldOpen
                                    width: parent.width
                                    height: 28
                                    radius: 8
                                    color: Qt.alpha(panel.on, 0.12)
                                    TextInput {
                                        id: fieldInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true
                                        color: panel.on
                                        selectionColor: Qt.alpha(panel.on, 0.3)
                                        font.family: panel.fonts.ui ?? ""
                                        font.pixelSize: 12
                                        Keys.onPressed: event => {
                                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                                panel.closeField(true);
                                            else if (event.key === Qt.Key_Escape)
                                                panel.closeField(false);
                                            else
                                                return;
                                            event.accepted = true;
                                        }
                                    }
                                }
                            }

                            Column {
                                width: (tileColumn.width - 12) / 2
                                spacing: 2
                                Caption {
                                    text: "Recent blocks"
                                }
                                Repeater {
                                    id: blockRepeater
                                    // The collector keeps 20; the tile draws the newest 6, so it stays on a laptop's screen.
                                    model: panel.paneView ? panel.paneView.blocks.slice(0, 6) : []
                                    Item {
                                        required property var modelData
                                        function drawn() {
                                            return { domain: blockDomain.text, age: blockAge.text };
                                        }
                                        width: parent.width
                                        height: 22
                                        Text {
                                            id: blockDomain
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - blockAge.width - 8
                                            textFormat: Text.PlainText
                                            text: modelData.domain
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                            color: panel.on
                                            font.family: panel.fonts.ui ?? ""
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            id: blockAge
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            textFormat: Text.PlainText
                                            text: modelData.age
                                            color: panel.tones.muted
                                            font.family: panel.fonts.ui ?? ""
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }

                        // Why the last write was refused, for 5 s.
                        Text {
                            id: writeErrorText
                            visible: panel.writeError !== ""
                            width: tileColumn.width
                            topPadding: 4
                            // The reason can quote a name anyone on the network set, so it elides in the tile's width.
                            textFormat: Text.PlainText
                            text: panel.writeError
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            color: panel.tones.danger
                            font.family: panel.fonts.ui ?? ""
                            font.pixelSize: 11
                        }
                    }
                }

                // The add tile: the name to add the lease as, what the lease says, and that it starts in Kid mode on the router.
                Rectangle {
                    id: addTile
                    visible: panel.adding
                    x: 352
                    width: parent.width - 352
                    height: addColumn.implicitHeight + 24
                    radius: 14
                    color: Qt.alpha(panel.on, 0.07)

                    Column {
                        id: addColumn
                        x: 14
                        y: 12
                        width: parent.width - 28
                        spacing: 4

                        Caption {
                            text: "Add as"
                        }
                        Rectangle {
                            width: addColumn.width
                            height: 32
                            radius: 10
                            color: Qt.alpha(panel.on, panel.naming ? 0.16 : 0.12)
                            TextInput {
                                id: nameInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: panel.on
                                selectionColor: Qt.alpha(panel.on, 0.3)
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Tab)
                                        panel.toggleNaming();
                                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                        panel.addLease();
                                    else if (event.key === Qt.Key_Escape)
                                        panel.closeAdd();
                                    else
                                        return;
                                    event.accepted = true;
                                }
                            }
                        }

                        Caption {
                            topPadding: 8
                            text: "From the lease"
                        }
                        Pair {
                            label: "Hostname"
                            Text {
                                id: leaseHost
                                // Any device names its own lease, so the hostname elides in the room the row has.
                                width: Math.min(implicitWidth, addColumn.width - 100)
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: panel.lease ? panel.lease.name : ""
                                elide: Text.ElideRight
                                color: panel.on
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 13
                            }
                        }
                        Pair {
                            label: "Address"
                            Text {
                                id: leaseAddress
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                width: Math.min(implicitWidth, parent.width * 0.6)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: panel.lease ? panel.lease.ip : ""
                                color: panel.on
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 13
                            }
                        }
                        Pair {
                            label: "Enforced by"
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: "Home router"
                                color: panel.on
                                font.family: panel.fonts.ui ?? ""
                                font.pixelSize: 13
                            }
                        }

                        Caption {
                            topPadding: 8
                            text: "Starts as Kid"
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: "YouTube · Social · Adult · Gambling"
                            color: panel.on
                            font.family: panel.fonts.ui ?? ""
                            font.pixelSize: 13
                        }
                        Text {
                            id: addNote
                            width: addColumn.width
                            topPadding: 8
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            text: "From the router's DHCP leases; listed devices are left out."
                            color: panel.tones.muted
                            font.family: panel.fonts.ui ?? ""
                            font.pixelSize: 11
                        }
                    }
                }
            }
            // A word another part of the shell sends, which the island cannot show while DNS Shield holds it.
            Root.ToolNote {
                id: toolNote
                theme: panel.theme
                width: parent.width
                color: panel.tones.muted
                font.family: panel.fonts.ui ?? ""
            }
        }
    }

    // A glyph from the symbols font in the island's ink.
    component Glyph: Text {
        textFormat: Text.PlainText
        color: panel.on
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 15
    }

    // A section's caption inside a tile, in the muted tone.
    component Caption: Text {
        height: 26 + topPadding
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        color: panel.tones.muted
        font.family: panel.fonts.ui ?? ""
        font.pixelSize: 12
    }

    // A muted label at the left of a 28 px row, its value at the right.
    component Pair: Item {
        property string label: ""
        width: addColumn.width
        height: 28
        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: parent.label
            color: panel.tones.muted
            font.family: panel.fonts.ui ?? ""
            font.pixelSize: 13
        }
    }

    // Board 8's switch: on is the island's ink with a knob of its fill at the right; off is the track with a muted knob at the left.
    component Switch: Rectangle {
        property bool on: false
        width: 38
        height: 22
        radius: 11
        color: on ? panel.on : Qt.alpha(panel.on, 0.16)
        Rectangle {
            x: parent.on ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: parent.on ? panel.fill : panel.tones.muted
        }
    }
}

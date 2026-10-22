import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/voice.mjs" as L
import "lib/dns.mjs" as D

// DNS Shield: carried and router devices with Kid mode, from dots-dns state; space, 1-4, o, a and n write through dots-dns, then the card reads state again.
Item {
    id: panel

    required property var theme
    property bool shown: false
    property int opens: 0
    // The last state read, kept while the surface stays loaded, so a reopen draws it at once.
    property string stateText: ""
    property real now: Date.now()
    // The countdown's clock: a timed open's badge and bar redraw from it, the rows do not.
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
    readonly property bool busy: cachedReader.running || reader.running || writer.running || leasesReader.running

    readonly property string command: Quickshell.env("DOTS_DNS") || "dots-dns"
    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property var marks: D.dnsLook(theme.tokens)
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
    readonly property bool caps: look.voice === "caps"
    readonly property bool plain: look.voice === "plain"
    readonly property bool bracket: look.voice === "bracket"
    readonly property Root.Motion motion: Root.Motion {
        shown: panel.shown
        tokens: panel.theme.tokens
    }

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

    // Nothing on this card is timed yet; the host calls this on every frame.
    function swapped() {
    }

    function move(by) {
        selected = Math.max(0, Math.min(stops.length - 1, selected + by));
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

    // n lists the router's leases in the card; an unreachable router has none to give.
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

    function state() {
        const groups = [];
        const rows = [];
        let box = null;
        for (let i = 0; i < rowRepeater.count; i++) {
            const r = rowRepeater.itemAt(i);
            if (r.it.kind === "group")
                groups.push({ text: r.groupLabel, right: r.groupRight, line: r.groupLine });
            else if (r.it.kind === "device")
                rows.push(r.drawn());
            if (r.isCurrent)
                box = r.drawnBox();
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
        const keys = [];
        for (let i = 0; i < keyRepeater.count; i++)
            keys.push(keyRepeater.itemAt(i).drawnKey);
        return JSON.stringify({
            loaded: true,
            open: shown,
            visible: panel.visible,
            drawing: panel.visible,
            settled: motion.settled,
            keyboard: panel.Window.active,
            busy: busy,
            opens: opens,
            heading: look.label.kind === "header" ? headerHeading.text : heading.text,
            cursor: device ? device.key : "",
            carried: rows.filter(r => r.key.startsWith("carried:")).length,
            router: rows.filter(r => r.key.startsWith("router:")).length,
            groups: groups,
            rows: rows,
            cursorBox: box,
            pane: {
                name: paneName.text,
                path: panePath.text,
                badge: paneBadge.drawnText,
                paused: pausedText.visible ? pausedText.text : "",
                categories: cats,
                until: untilRow.visible ? untilText.text : "",
                left: untilRow.visible ? leftText.text : "",
                allow: allow,
                blocks: blocks,
                hint: paneHint.visible ? paneHint.text : ""
            },
            field: fieldOpen ? fieldInput.text : null,
            add: adding ? {
                head: leasesHead.text,
                leases: leaseRows,
                cursor: lease ? lease.mac : "",
                name: nameInput.text,
                naming: naming,
                host: leaseHost.text,
                address: leaseAddress.text
            } : null,
            footer: footerText.text,
            keys: keys
        });
    }

    Process {
        id: cachedReader
        command: [panel.command, "state", "--cached"]
        stdout: StdioCollector {
            id: cachedOut
        }
        // A card closed while the cache was read starts no full read.
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

    // The card reads state after every write, so a refused write leaves the rows as dots-dns has them.
    Process {
        id: writer
        onExited: {
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

    // A timed open counts down once a second while the card shows; at its end the collector brings Kid back, so the card reads state again.
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

    visible: motion.drawing

    // Holds the keyboard while the card shows, unless the allow field or the name field has it.
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

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(c.paper, card.style.wash)
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: Math.max(24, Math.min(84, Math.round((parent.height - height) / 2)))
        width: Math.min(1040, parent.width - 48)
        height: column.implicitHeight
        tokens: panel.theme.tokens
        label: "DNS Shield"
        motion: panel.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 16
                Layout.bottomMargin: 16

                Rectangle {
                    visible: look.label.kind !== "header"
                    implicitWidth: heading.implicitWidth + 14
                    implicitHeight: heading.implicitHeight + 6
                    radius: plain ? 8 : 0
                    color: look.label.fill
                    Text {
                        id: heading
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: marks.heading(panel.adding)
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: plain ? 12 : 10
                        font.weight: plain ? Font.Medium : Font.Normal
                        font.letterSpacing: plain ? 0 : 1.4
                    }
                }
                Text {
                    id: headerHeading
                    visible: look.label.kind === "header"
                    textFormat: Text.PlainText
                    text: marks.heading(panel.adding)
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: look.small.size
                    font.letterSpacing: look.small.spacing
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            Rule {}

            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                // The device list: two groups, the cursor row inverted, and the dashed row for a device from the leases.
                Column {
                    id: list
                    visible: !panel.adding
                    Layout.preferredWidth: Math.round(card.width * 0.54)
                    Layout.alignment: Qt.AlignTop
                    Layout.margins: 8

                    Repeater {
                        id: rowRepeater
                        model: panel.items

                        Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property var it: modelData
                            readonly property bool isCurrent: index === panel.current
                            readonly property bool hasLine: it.kind === "group" && (it.line || "") !== ""
                            readonly property var group: it.kind === "group" ? marks.group(it) : null
                            readonly property string groupLabel: groupText.text
                            readonly property string groupRight: groupRightText.text
                            readonly property string groupLine: hasLine ? groupLineText.text : ""
                            readonly property color ink: isCurrent ? look.cursor.text : c.ink
                            function drawn() {
                                return { key: it.key, name: nameText.text, badge: rowBadge.drawnText, age: ageText.text, truncated: nameText.truncated, lines: nameText.lineCount, opacity: deviceRow.opacity };
                            }
                            // The row as drawn this frame, in the window's pixels.
                            function drawnBox() {
                                const a = mapToItem(null, 0, 0);
                                return { x: a.x, y: a.y, w: width * card.scale, h: height * card.scale };
                            }

                            width: list.width
                            implicitHeight: it.kind === "group" ? (hasLine ? 50 : 30) : it.kind === "add" ? 52 : 42
                            radius: look.cursor.radius
                            color: isCurrent ? look.cursor.fill : "transparent"

                            ColumnLayout {
                                visible: rowItem.it.kind === "group"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.bottomMargin: 4
                                spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        id: groupText
                                        textFormat: Text.PlainText
                                        text: rowItem.group ? rowItem.group.text : ""
                                        color: look.small.color
                                        font.family: look.small.font
                                        font.pixelSize: look.small.size
                                        font.letterSpacing: plain ? 0 : 1.6
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        id: groupRightText
                                        textFormat: Text.PlainText
                                        text: rowItem.group ? rowItem.group.right : ""
                                        color: look.small.color
                                        font.family: look.small.font
                                        font.pixelSize: look.small.size
                                        font.letterSpacing: plain ? 0 : 1.6
                                    }
                                }
                                // Why the router's rows are dim and since when, in the theme's error voice.
                                Text {
                                    id: groupLineText
                                    visible: rowItem.hasLine
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: marks.errorText(rowItem.it.line || "")
                                    elide: Text.ElideRight
                                    color: c.danger
                                    font.family: caps ? fonts.display : look.small.font
                                    font.pixelSize: caps ? 15 : 11
                                    font.italic: caps
                                    font.weight: bracket ? Font.Bold : Font.Normal
                                    font.letterSpacing: bracket ? 1.2 : 0
                                }
                            }

                            RowLayout {
                                id: deviceRow
                                visible: rowItem.it.kind === "device"
                                opacity: rowItem.it.dim ? 0.45 : 1
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 14
                                Text {
                                    id: nameText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: rowItem.it.name || ""
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: rowItem.ink
                                    font.family: look.name.font
                                    font.pixelSize: 15
                                    font.weight: rowItem.isCurrent ? Font.Medium : Font.Normal
                                    font.letterSpacing: look.name.spacing
                                }
                                Item {
                                    Layout.preferredWidth: 150
                                    implicitHeight: rowBadge.implicitHeight
                                    Badge {
                                        id: rowBadge
                                        anchors.verticalCenter: parent.verticalCenter
                                        kid: rowItem.it.kid === true
                                        timed: rowItem.it.kind === "device" && rowItem.it.openUntil !== null
                                        label: rowItem.it.kind === "device" ? D.badgeText(rowItem.it, panel.clock) : ""
                                        cursorRow: rowItem.isCurrent
                                    }
                                }
                                Text {
                                    id: ageText
                                    Layout.preferredWidth: 56
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: rowItem.it.age || ""
                                    color: rowItem.isCurrent ? look.cursor.detail : c.muted
                                    font.family: fonts.mono
                                    font.pixelSize: 12
                                }
                            }

                            Rectangle {
                                visible: rowItem.it.kind === "add"
                                anchors.fill: parent
                                anchors.topMargin: 10
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                radius: look.cursor.radius
                                color: "transparent"
                                Root.Dashed {
                                    anchors.fill: parent
                                    frame: true
                                    color: c.line
                                }
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    spacing: 12
                                    Text {
                                        textFormat: Text.PlainText
                                        text: look.keyText("n")
                                        color: c.ink
                                        font.family: fonts.mono
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "add a device from the router's leases"
                                        color: c.muted
                                        font.family: fonts.ui
                                        font.pixelSize: 13
                                    }
                                }
                            }
                        }
                    }
                }

                // The add sub-list in place of the devices: the router's leases not yet listed.
                ColumnLayout {
                    visible: panel.adding
                    Layout.preferredWidth: Math.round(card.width * 0.54)
                    Layout.alignment: Qt.AlignTop
                    Layout.margins: 8
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        Layout.topMargin: 6
                        Layout.bottomMargin: 4
                        Text {
                            id: leasesHead
                            textFormat: Text.PlainText
                            text: marks.leasesHead(panel.leases.length).text
                            color: look.small.color
                            font.family: look.small.font
                            font.pixelSize: look.small.size
                            font.letterSpacing: plain ? 0 : 1.6
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: marks.leasesHead(panel.leases.length).right
                            color: look.small.color
                            font.family: look.small.font
                            font.pixelSize: look.small.size
                            font.letterSpacing: plain ? 0 : 1.6
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
                                return { mac: modelData.mac, name: leaseName.text, ip: leaseIp.text, truncated: leaseName.truncated, lines: leaseName.lineCount };
                            }
                            Layout.fillWidth: true
                            implicitHeight: 42
                            radius: look.cursor.radius
                            color: isCurrent ? look.cursor.fill : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 14
                                Text {
                                    id: leaseName
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: leaseRow.modelData.name
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: leaseRow.isCurrent ? look.cursor.text : c.ink
                                    font.family: look.name.font
                                    font.pixelSize: 15
                                }
                                Text {
                                    id: leaseIp
                                    textFormat: Text.PlainText
                                    text: leaseRow.modelData.ip
                                    color: leaseRow.isCurrent ? look.cursor.detail : c.muted
                                    font.family: fonts.mono
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.topMargin: 10
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        text: "read from the router's DHCP leases · devices already in the list are left out"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 1
                    color: look.rule.color
                }

                // The pane for the cursor device; an OPEN one shows only its recent blocks and the way back to Kid.
                ColumnLayout {
                    visible: !panel.adding
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.leftMargin: 22
                    Layout.rightMargin: 22
                    Layout.topMargin: 18
                    Layout.bottomMargin: 18
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                id: paneName
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: panel.paneView ? panel.paneView.name : ""
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                color: c.ink
                                font.family: look.name.font
                                font.pixelSize: 17
                                font.weight: Font.Medium
                            }
                            Text {
                                id: panePath
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: panel.paneView ? panel.paneView.path : ""
                                elide: Text.ElideRight
                                color: c.muted
                                font.family: fonts.mono
                                font.pixelSize: 12
                            }
                        }
                        Badge {
                            id: paneBadge
                            Layout.alignment: Qt.AlignTop
                            kid: !!panel.device && panel.device.kid
                            timed: panel.timedOpen
                            label: panel.device ? D.badgeText(panel.device, panel.clock) : ""
                            cursorRow: false
                        }
                    }

                    ColumnLayout {
                        visible: panel.paneFull
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            Text {
                                textFormat: Text.PlainText
                                text: look.tabText("Categories")
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: plain ? 0 : 1.4
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                id: pausedText
                                visible: panel.timedOpen
                                textFormat: Text.PlainText
                                text: panel.paneView ? panel.paneView.paused : ""
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                            }
                        }
                        Repeater {
                            id: catRepeater
                            model: panel.paneView ? panel.paneView.categories : []
                            ColumnLayout {
                                id: catRow
                                required property var modelData
                                readonly property bool isOn: modelData.value === "ON"
                                readonly property bool isPaused: modelData.value === "paused"
                                readonly property bool hasNote: modelData.key === "youtube_kids" && !!panel.paneView && panel.paneView.shared !== ""
                                function drawn() {
                                    return { n: Number(catKey.text), label: catLabel.text, value: catValue.text, note: hasNote ? catNote.text : "" };
                                }
                                Layout.fillWidth: true
                                Layout.topMargin: 5
                                Layout.bottomMargin: 5
                                spacing: 2
                                RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Text {
                                    id: catKey
                                    Layout.preferredWidth: 14
                                    textFormat: Text.PlainText
                                    text: String(catRow.modelData.n)
                                    color: c.ink
                                    font.family: fonts.mono
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                Text {
                                    id: catLabel
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: catRow.modelData.label
                                    color: catRow.isPaused ? c.muted : c.ink
                                    font.family: fonts.ui
                                    font.pixelSize: 14
                                }
                                // A paused category keeps its knob at on, drawn hollow.
                                Rectangle {
                                    implicitWidth: 30
                                    implicitHeight: 16
                                    radius: 8
                                    color: catRow.isOn ? c.ink : "transparent"
                                    border.width: catRow.isOn ? 0 : 1.5
                                    border.color: c.muted
                                    Rectangle {
                                        x: catRow.isOn || catRow.isPaused ? parent.width - width - 2 : 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: catRow.isOn ? 12 : 10
                                        height: width
                                        radius: width / 2
                                        color: catRow.isOn ? c.surface : c.muted
                                    }
                                }
                                Text {
                                    id: catValue
                                    Layout.preferredWidth: 48
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: catRow.modelData.value
                                    color: catRow.isOn ? c.ink : c.muted
                                    font.family: fonts.mono
                                    font.pixelSize: 11
                                    font.weight: catRow.isOn ? Font.DemiBold : Font.Normal
                                }
                                }
                                // On a router row YouTube Kids is one setting for every home-router device, so 2 changes them all.
                                Text {
                                    id: catNote
                                    visible: catRow.hasNote
                                    Layout.leftMargin: 26
                                    textFormat: Text.PlainText
                                    text: panel.paneView ? panel.paneView.shared : ""
                                    color: c.muted
                                    font.family: fonts.ui
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    // OPEN FOR on a KID device; a timed open shows its end, what is left, a bar of its length and how to end it.
                    ColumnLayout {
                        visible: panel.paneFull
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            textFormat: Text.PlainText
                            text: look.tabText(panel.timedOpen ? "Open" : "Open for")
                            color: look.small.color
                            font.family: look.small.font
                            font.pixelSize: look.small.size
                            font.letterSpacing: plain ? 0 : 1.4
                        }
                        RowLayout {
                            id: untilRow
                            visible: panel.timedOpen
                            Layout.fillWidth: true
                            Text {
                                id: untilText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: panel.paneView ? panel.paneView.until : ""
                                color: c.ink
                                font.family: fonts.ui
                                font.pixelSize: 13
                            }
                            Text {
                                id: leftText
                                textFormat: Text.PlainText
                                text: panel.timedOpen ? D.badgeText(panel.device, panel.clock).replace("open · ", "") : ""
                                color: c.ink
                                font.family: fonts.mono
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                        }
                        Rectangle {
                            visible: panel.timedOpen
                            Layout.fillWidth: true
                            implicitHeight: 4
                            radius: plain ? 2 : 0
                            color: c.line
                            Rectangle {
                                width: parent.width * (panel.timedOpen ? D.openFraction(panel.device, panel.clock) : 0)
                                height: parent.height
                                radius: parent.radius
                                color: c.ink
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: panel.timedOpen ? [["o", "+30m"], ["O", "2h"]] : [["o", "30m"], ["O", "2h"]]
                                Rectangle {
                                    required property var modelData
                                    implicitWidth: openRow.implicitWidth + 20
                                    implicitHeight: openRow.implicitHeight + 10
                                    radius: plain ? 6 : 0
                                    color: "transparent"
                                    border.width: 1
                                    border.color: c.line
                                    Row {
                                        id: openRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text {
                                            textFormat: Text.PlainText
                                            text: modelData[0]
                                            color: c.ink
                                            font.family: fonts.mono
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: modelData[1]
                                            color: c.ink
                                            font.family: fonts.mono
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: panel.timedOpen
                                textFormat: Text.PlainText
                                text: look.keyText("space") + " " + look.tabText("ends it now")
                                color: c.muted
                                font.family: fonts.mono
                                font.pixelSize: 11
                            }
                        }
                    }

                    ColumnLayout {
                        visible: panel.paneFull
                        Layout.fillWidth: true
                        spacing: 0
                        Head {
                            text: look.tabText("Allow list") + " · " + (panel.paneView ? panel.paneView.allow.length : 0)
                            word: look.keyText("a") + " " + look.tabText("add")
                        }
                        Repeater {
                            id: allowRepeater
                            model: panel.paneView ? panel.paneView.allow : []
                            Text {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                Layout.bottomMargin: 4
                                textFormat: Text.PlainText
                                text: modelData
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                color: c.ink
                                font.family: fonts.ui
                                font.pixelSize: 14
                            }
                        }
                        // One line for a domain to allow: Enter adds it, Esc leaves it.
                        Rectangle {
                            visible: panel.fieldOpen
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            implicitHeight: fieldInput.implicitHeight + 10
                            radius: plain ? 6 : 0
                            color: "transparent"
                            border.width: 1
                            border.color: c.accent
                            TextInput {
                                id: fieldInput
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: c.ink
                                font.family: fonts.ui
                                font.pixelSize: 14
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

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Head {
                            text: look.tabText("Recent blocks")
                        }
                        Repeater {
                            id: blockRepeater
                            // The collector keeps 20; the card draws the newest 6, so it stays on a laptop's screen.
                            model: panel.paneView ? panel.paneView.blocks.slice(0, 6) : []
                            RowLayout {
                                required property var modelData
                                function drawn() {
                                    return { domain: blockDomain.text, age: blockAge.text };
                                }
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                Layout.bottomMargin: 4
                                Text {
                                    id: blockDomain
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: modelData.domain
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                    color: c.ink
                                    font.family: fonts.mono
                                    font.pixelSize: 12
                                }
                                Text {
                                    id: blockAge
                                    textFormat: Text.PlainText
                                    text: modelData.age
                                    color: c.muted
                                    font.family: fonts.mono
                                    font.pixelSize: 12
                                }
                            }
                        }
                        Text {
                            id: paneHint
                            visible: !!panel.paneView && panel.paneView.hint !== ""
                            Layout.topMargin: 8
                            textFormat: Text.PlainText
                            text: panel.paneView ? panel.paneView.hint : ""
                            color: c.muted
                            font.family: fonts.ui
                            font.pixelSize: 13
                        }
                    }
                }

                // The add pane: the name to add the lease as, what the lease says, and that it starts in Kid mode on the router.
                ColumnLayout {
                    visible: panel.adding
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.leftMargin: 22
                    Layout.rightMargin: 22
                    Layout.topMargin: 18
                    Layout.bottomMargin: 18
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Head {
                            text: look.tabText("Add as")
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: nameInput.implicitHeight + 12
                            radius: plain ? 6 : 0
                            color: "transparent"
                            border.width: panel.naming ? 2 : 1
                            border.color: panel.naming ? c.accent : c.line
                            TextInput {
                                id: nameInput
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: c.ink
                                font.family: fonts.ui
                                font.pixelSize: 15
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
                        Text {
                            textFormat: Text.PlainText
                            text: "type to rename, tab back to the leases"
                            color: c.muted
                            font.family: fonts.ui
                            font.pixelSize: 12
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Head {
                            text: look.tabText("From the lease")
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                textFormat: Text.PlainText
                                text: "Hostname"
                                color: c.muted
                                font.family: fonts.ui
                                font.pixelSize: 13
                            }
                            Text {
                                id: leaseHost
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: panel.lease ? panel.lease.name : ""
                                elide: Text.ElideRight
                                color: c.ink
                                font.family: fonts.mono
                                font.pixelSize: 13
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                textFormat: Text.PlainText
                                text: "Address"
                                color: c.muted
                                font.family: fonts.ui
                                font.pixelSize: 13
                            }
                            Text {
                                id: leaseAddress
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: panel.lease ? panel.lease.ip : ""
                                color: c.ink
                                font.family: fonts.mono
                                font.pixelSize: 13
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                textFormat: Text.PlainText
                                text: "Enforced by"
                                color: c.muted
                                font.family: fonts.ui
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: "Home router"
                                color: c.ink
                                font.family: fonts.mono
                                font.pixelSize: 13
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Head {
                            text: look.tabText("Starts as Kid")
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: "YouTube · Social · Adult · Gambling"
                            color: c.ink
                            font.family: fonts.ui
                            font.pixelSize: 14
                        }
                    }
                }
            }

            Rule {}

            Text {
                id: footerText
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                textFormat: Text.PlainText
                text: view.footer
                color: c.muted
                font.family: look.small.font
                font.pixelSize: look.small.size
                font.letterSpacing: look.small.spacing
            }

            Rule {}

            // The key strip as Accounts draws it: chips in Artboard, tracked caps in Paper, brackets in Blueprint.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                spacing: plain ? 8 : 14

                Repeater {
                    id: keyRepeater
                    model: panel.adding ? D.addKeys(look) : D.dnsKeys(look)
                    Rectangle {
                        id: keyPair
                        required property var modelData
                        readonly property string drawnKey: chipKey.text
                        width: pair.implicitWidth + (plain ? 14 : 0)
                        height: pair.implicitHeight + (plain ? 6 : 0)
                        radius: 6
                        color: look.chip.fill
                        Row {
                            id: pair
                            anchors.centerIn: parent
                            spacing: plain ? 6 : 5
                            Text {
                                id: chipKey
                                textFormat: Text.PlainText
                                text: keyPair.modelData.key
                                color: look.chip.key
                                font.family: fonts.mono
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                                font.bold: true
                            }
                            Text {
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

    // A rule across the card: solid, or dashed in Blueprint.
    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: look.rule.dashed ? "transparent" : look.rule.color

        Root.Dashed {
            visible: look.rule.dashed
            anchors.fill: parent
            color: look.rule.color
        }
    }

    // A section's head in the pane, with an optional word at the right.
    component Head: RowLayout {
        property string text: ""
        property string word: ""
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        Text {
            textFormat: Text.PlainText
            text: parent.text
            color: look.small.color
            font.family: look.small.font
            font.pixelSize: look.small.size
            font.letterSpacing: plain ? 0 : 1.4
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            visible: parent.word !== ""
            textFormat: Text.PlainText
            text: parent.word
            color: look.small.color
            font.family: look.small.font
            font.pixelSize: look.small.size
            font.letterSpacing: plain ? 0 : 1.4
        }
    }

    // KID with a filled dot, OPEN with a hollow one, a timed open with a dashed outline and a clock; on the cursor row it takes the cursor's text colour.
    component Badge: Rectangle {
        id: badgeRoot
        property bool kid: false
        property bool timed: false
        property string label: ""
        property bool cursorRow: false
        readonly property color tone: cursorRow ? look.cursor.text : kid || timed ? c.ink : c.muted
        // The badge as drawn, for the state function.
        readonly property string drawnText: badgeText.text
        implicitWidth: badgeRow.implicitWidth + 17
        implicitHeight: badgeRow.implicitHeight + 4
        radius: plain ? height / 2 : 0
        color: "transparent"
        border.width: badgeRoot.timed ? 0 : 1
        border.color: kid || cursorRow ? tone : c.line
        Root.Dashed {
            visible: badgeRoot.timed
            anchors.fill: parent
            frame: true
            color: badgeRoot.tone
        }
        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 6
            Rectangle {
                visible: !badgeRoot.timed
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: badgeRoot.kid ? badgeRoot.tone : "transparent"
                border.width: badgeRoot.kid ? 0 : 1.5
                border.color: badgeRoot.tone
            }
            // The clock of a timed open: a ring and its hand.
            Rectangle {
                visible: badgeRoot.timed
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: "transparent"
                border.width: 1.2
                border.color: badgeRoot.tone
                Rectangle {
                    x: 4.4
                    y: 2
                    width: 1.2
                    height: 3.4
                    color: badgeRoot.tone
                }
                Rectangle {
                    x: 4.4
                    y: 4.4
                    width: 2.6
                    height: 1.2
                    color: badgeRoot.tone
                }
            }
            Text {
                id: badgeText
                textFormat: Text.PlainText
                text: badgeRoot.label
                color: badgeRoot.tone
                font.family: fonts.mono
                font.pixelSize: 11
            }
        }
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/voice.mjs" as L
import "lib/dns.mjs" as D

// DNS Shield: carried and router devices with Kid mode, from dots-dns state; space, 1-4 and a write through dots-dns, then the card reads state again.
Item {
    id: panel

    required property var theme
    property bool shown: false
    property int opens: 0
    // The last state read, kept while the surface stays loaded, so a reopen draws it at once.
    property string stateText: ""
    property real now: Date.now()
    // The cursor's place among the device rows.
    property int selected: 0
    property bool fieldOpen: false
    // Keys pressed while a write or a read runs; each waits for the state before it, so a second space is never lost.
    property var pending: []
    readonly property bool busy: reader.running || writer.running

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
    readonly property bool caps: look.voice === "caps"
    readonly property bool plain: look.voice === "plain"
    readonly property bool bracket: look.voice === "bracket"
    readonly property Root.Motion motion: Root.Motion {
        shown: panel.shown
        tokens: panel.theme.tokens
    }

    function open(t0) {
        opens += 1;
        selected = 0;
        fieldOpen = false;
        if (!busy)
            reader.running = true;
        shown = true;
        keyTarget.forceActiveFocus();
    }

    // A write that runs finishes; the keys still waiting are dropped and nothing reads again.
    function close() {
        shown = false;
        fieldOpen = false;
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
        if (text.trim().charAt(0) === "{") {
            stateText = text;
            now = Date.now();
        }
    }

    function act(a) {
        if (!device)
            return;
        pending = pending.concat([Object.assign({ key: device.key }, a)]);
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
        const args = !d ? null : a.kind === "kid" ? D.kidArgs(d) : a.kind === "category" ? D.categoryArgs(d, a.n) : D.allowArgs(d, a.text);
        if (!args) {
            next();
            return;
        }
        writer.command = [command].concat(args);
        writer.running = true;
    }

    function openField() {
        if (!device || !device.kid)
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

    function state() {
        const groups = [];
        const rows = [];
        let box = null;
        for (let i = 0; i < rowRepeater.count; i++) {
            const r = rowRepeater.itemAt(i);
            if (r.it.kind === "group")
                groups.push({ text: r.groupLabel, right: r.groupRight });
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
        return JSON.stringify({
            loaded: true,
            open: shown,
            visible: panel.visible,
            drawing: panel.visible,
            settled: motion.settled,
            keyboard: panel.Window.active,
            busy: busy,
            opens: opens,
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
                categories: cats,
                allow: allow,
                blocks: blocks,
                hint: paneHint.visible ? paneHint.text : ""
            },
            field: fieldOpen ? fieldInput.text : null,
            footer: footerText.text
        });
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

    Component.onCompleted: Root.State.loaded.push("dns")
    Component.onDestruction: Root.State.loaded = Root.State.loaded.filter(n => n !== "dns")

    visible: motion.drawing

    // Holds the keyboard while the card shows, unless the allow field has it.
    Item {
        id: keyTarget
        Keys.onPressed: event => {
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                panel.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                panel.move(-1);
            else if (event.key === Qt.Key_Space)
                panel.act({ kind: "kid" });
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4)
                panel.act({ kind: "category", n: event.key - Qt.Key_0 });
            else if (event.key === Qt.Key_A)
                panel.openField();
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
                        text: look.heading("DNS Shield", "")
                        color: look.label.color
                        font.family: fonts.ui
                        font.pixelSize: plain ? 12 : 10
                        font.weight: plain ? Font.Medium : Font.Normal
                        font.letterSpacing: plain ? 0 : 1.4
                    }
                }
                Text {
                    visible: look.label.kind === "header"
                    textFormat: Text.PlainText
                    text: look.heading("DNS Shield", "devices")
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
                            readonly property var group: it.kind === "group" ? marks.group(it) : null
                            readonly property string groupLabel: groupText.text
                            readonly property string groupRight: groupRightText.text
                            readonly property color ink: isCurrent ? look.cursor.text : c.ink
                            function drawn() {
                                return { key: it.key, name: nameText.text, badge: rowBadge.drawnText, age: ageText.text, truncated: nameText.truncated, lines: nameText.lineCount };
                            }
                            // The row as drawn this frame, in the window's pixels.
                            function drawnBox() {
                                const a = mapToItem(null, 0, 0);
                                return { x: a.x, y: a.y, w: width * card.scale, h: height * card.scale };
                            }

                            width: list.width
                            implicitHeight: it.kind === "group" ? 30 : it.kind === "add" ? 52 : 42
                            radius: look.cursor.radius
                            color: isCurrent ? look.cursor.fill : "transparent"

                            RowLayout {
                                visible: rowItem.it.kind === "group"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.bottomMargin: 4
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

                            RowLayout {
                                visible: rowItem.it.kind === "device"
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
                                    Layout.preferredWidth: 132
                                    implicitHeight: rowBadge.implicitHeight
                                    Badge {
                                        id: rowBadge
                                        anchors.verticalCenter: parent.verticalCenter
                                        kid: rowItem.it.kid === true
                                        label: rowItem.it.badge || ""
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

                            // n opens the leases once adding a device is built; until then the row only says so.
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

                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 1
                    color: look.rule.color
                }

                // The pane for the cursor device; an OPEN one shows only its recent blocks and the way back to Kid.
                ColumnLayout {
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
                                textFormat: Text.PlainText
                                text: panel.paneView ? panel.paneView.path : ""
                                color: c.muted
                                font.family: fonts.mono
                                font.pixelSize: 12
                            }
                        }
                        Badge {
                            id: paneBadge
                            Layout.alignment: Qt.AlignTop
                            kid: !!panel.device && panel.device.kid
                            label: panel.paneView ? panel.paneView.badge : ""
                            cursorRow: false
                        }
                    }

                    ColumnLayout {
                        visible: !!panel.paneView && panel.paneView.categories.length > 0
                        Layout.fillWidth: true
                        spacing: 0
                        Head {
                            text: look.tabText("Categories")
                        }
                        Repeater {
                            id: catRepeater
                            model: panel.paneView ? panel.paneView.categories : []
                            RowLayout {
                                id: catRow
                                required property var modelData
                                readonly property bool isOn: modelData.value === "ON"
                                function drawn() {
                                    return { n: Number(catKey.text), label: catLabel.text, value: catValue.text };
                                }
                                Layout.fillWidth: true
                                Layout.topMargin: 5
                                Layout.bottomMargin: 5
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
                                    color: c.ink
                                    font.family: fonts.ui
                                    font.pixelSize: 14
                                }
                                Rectangle {
                                    implicitWidth: 30
                                    implicitHeight: 16
                                    radius: 8
                                    color: catRow.isOn ? c.ink : "transparent"
                                    border.width: catRow.isOn ? 0 : 1.5
                                    border.color: c.muted
                                    Rectangle {
                                        x: catRow.isOn ? parent.width - width - 2 : 2
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
                        }
                    }

                    // Opening for a time is the next piece of work; the keys are shown, and do nothing yet.
                    ColumnLayout {
                        visible: !!panel.device && panel.device.kid
                        Layout.fillWidth: true
                        spacing: 4
                        Head {
                            text: look.tabText("Open for")
                        }
                        Row {
                            spacing: 8
                            Repeater {
                                model: [["o", "30m"], ["O", "2h"]]
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
                        }
                    }

                    ColumnLayout {
                        visible: !!panel.device && panel.device.kid
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
                    model: D.dnsKeys(look)
                    Rectangle {
                        id: keyPair
                        required property var modelData
                        width: pair.implicitWidth + (plain ? 14 : 0)
                        height: pair.implicitHeight + (plain ? 6 : 0)
                        radius: 6
                        color: look.chip.fill
                        Row {
                            id: pair
                            anchors.centerIn: parent
                            spacing: plain ? 6 : 5
                            Text {
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

    // KID with a filled dot, OPEN with a hollow one; on the cursor row it takes the cursor's text colour.
    component Badge: Rectangle {
        id: badgeRoot
        property bool kid: false
        property string label: ""
        property bool cursorRow: false
        readonly property color tone: cursorRow ? look.cursor.text : kid ? c.ink : c.muted
        // The badge as drawn, for the state function.
        readonly property string drawnText: badgeText.text
        implicitWidth: badgeRow.implicitWidth + 17
        implicitHeight: badgeRow.implicitHeight + 4
        radius: plain ? height / 2 : 0
        color: "transparent"
        border.width: 1
        border.color: kid || cursorRow ? tone : c.line
        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 6
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: badgeRoot.kid ? badgeRoot.tone : "transparent"
                border.width: badgeRoot.kid ? 0 : 1.5
                border.color: badgeRoot.tone
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

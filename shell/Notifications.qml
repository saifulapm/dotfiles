import Quickshell
import QtQuick
import "." as Root
import "lib/notifs.mjs" as Lib
import "lib/notif-centre.mjs" as C
import "lib/voice.mjs" as V
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T
import "lib/dekho.mjs" as D

// The notification centre drawn inside the island on its fill (board 5): the header with the count, Do Not Disturb and Clear all, then each app's head over its notifications, newest first; Enter on a head opens that app's rules tile.
Item {
    id: centre

    required property var theme
    // The Notifs service: its history, Do Not Disturb, per-app rules and the remove, clear, act and rule calls.
    required property var notifs
    // The island reports this as its surface while the centre is shown.
    readonly property string name: "notifs"
    // The island grows to this width for the centre, as board 5 draws it.
    readonly property int wantWidth: 640
    readonly property bool busy: false
    property bool shown: false
    // True once the island has come to rest on the centre; the surfaces' window sets it.
    property bool settled: false
    // True while a file chip's drag runs, so the surfaces' window lets the pointer through outside the island to the app it drops on.
    property bool dragging: false
    // The app whose rules tile is open, or "".
    property string openRules: ""
    property bool searching: false
    readonly property string query: input.text
    property int selected: 0
    // The row the cursor is on, by what it is, so an arrival that puts rows above it does not move it to another.
    property string selectedKey: ""
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1
    // When the centre last opened; each tile's age is counted to it, so the ages need no timer.
    property real openedAt: 0

    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, and the tones lifted to read on it.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property var chipLook: V.chipLook(tokens)

    readonly property var rows: C.centreRows(notifs.history, query, notifs.rules, openRules)
    readonly property int noteCount: rows.filter(r => r.kind === "note").length
    readonly property string countText: C.countText(noteCount, notifs.history.length, query)
    // The header, and the search field while it shows, sit above the list.
    readonly property real listTop: 16 + 40 + 8 + (searchBox.visible ? 44 + 8 : 0)

    implicitHeight: listTop + (rows.length > 0 ? list.contentHeight : 120) + 16

    function open(t0) {
        openT0 = t0;
        openedAt = Date.now();
        openMs = null;
        opens += 1;
        input.text = "";
        searching = false;
        openRules = "";
        selected = C.firstNote(rows);
        shown = true;
        forceActiveFocus();
        // It opens at the top, the first app's head in view, wherever the last open left the list; queued after the rows' own re-position.
        list.positionViewAtBeginning();
        Qt.callLater(() => list.positionViewAtBeginning());
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

    // The selected note's buttons, while its app still holds it.
    function chipsOf(row) {
        return row?.kind === "note" && notifs.live[row.entry.key] ? Lib.chipsOf(row.entry.actions) : [];
    }

    // Enter on a note runs its default action, else its first button; on a head it opens or closes the app's rules; on a rule it flips it.
    function act() {
        const row = rows[selected];
        if (!row)
            return;
        if (row.kind === "head")
            toggleRules(row.app);
        else if (row.kind === "rule")
            flipRule(row);
        else if (notifs.act(row.entry.key))
            close();
        else if (chipsOf(row).length > 0)
            runChip(chipsOf(row)[0].key);
    }

    // 1 to 9 runs the selected note's button with that number.
    function runChip(key) {
        const row = rows[selected];
        const chip = chipsOf(row).find(c => c.key === key);
        if (!chip)
            return;
        notifs.runAction(row.entry.key, chip.identifier);
        close();
    }

    function toggleRules(app) {
        if (openRules === app) {
            openRules = "";
            selected = rows.findIndex(r => r.kind === "head" && r.app === app);
        } else {
            openRules = app;
            selected = rows.findIndex(r => r.kind === "rule" && r.app === app);
        }
    }

    // Mute and Show during Do Not Disturb flip; the second does nothing while muted; Stays on screen steps to its next pill.
    function flipRule(row) {
        if (row.field === "stays")
            notifs.cycleStay(row.app);
        else if (!row.greyed)
            notifs.toggleRule(row.app, row.field);
    }

    function dismiss() {
        const row = rows[selected];
        if (row?.kind === "note")
            notifs.remove(row.entry.key);
    }

    // A click outside closes the search or the rules tile first, then the centre.
    function stepBack() {
        if (openRules !== "")
            toggleRules(openRules);
        else
            close();
    }

    // An item's box in window coordinates, as a screenshot reads it.
    function box(item) {
        const p = item.mapToItem(null, 0, 0);
        return { x: p.x, y: p.y, w: item.width, h: item.height };
    }

    function drawn(i) {
        return list.itemAtIndex(i);
    }

    function state() {
        return {
            open: shown,
            query: query,
            searching: searching,
            selected: selected,
            selectedKind: rows[selected]?.kind ?? null,
            openRules: openRules,
            groups: rows.filter(r => r.kind === "head").map(h => ({
                        app: h.app,
                        entries: rows.filter(r => r.kind === "note" && r.app === h.app).map(r => r.entry.summary)
                    })),
            rows: rows.map(r => r.kind),
            heading: heading.text,
            countText: countLabel.text,
            dndOn: dndSwitch.on,
            empty: emptyBox.visible,
            emptyText: emptyBox.visible ? emptyWord.text : "",
            // Each head as drawn: its circle's letter and size, the app's name and the badge.
            heads: rows.map((r, i) => r.kind === "head" ? drawn(i) : null).filter(d => d).map(d => d.headDrawn()),
            // Each note as drawn: its summary, body and age, its fill and whether it is the selected one.
            notes: rows.map((r, i) => r.kind === "note" ? drawn(i) : null).filter(d => d).map(d => d.noteDrawn()),
            // The selected note's buttons as drawn, the first inverted.
            actions: drawn(selected)?.actionsDrawn() ?? [],
            // The open rules tile's rows as drawn.
            ruleRows: rows.map((r, i) => r.kind === "rule" ? drawn(i) : null).filter(d => d).map(d => d.ruleDrawn()),
            cursorBox: drawn(selected) ? box(drawn(selected)) : null,
            // How far the list is scrolled from its first row, the box it draws rows in, and how tall its rows are in all.
            scrollY: list.contentY - list.originY,
            listBox: box(list),
            // The right edge rows draw to, in window coordinates.
            cardRight: box(list).x + list.width,
            contentHeight: list.contentHeight,
            legend: null,
            openMs: openMs,
            opens: opens,
            settled: settled,
            drawing: shown,
            // The window has the keyboard; niri lists a layer Exclusive a moment before its keys arrive.
            keyboard: centre.Window.active
        };
    }

    onQueryChanged: selected = C.firstNote(rows)
    onRowsChanged: {
        selected = C.follow(rows, selectedKey, selected);
        // A new rows array resets the list, so the cursor's row is brought back into view once it has laid out.
        Qt.callLater(() => list.positionViewAtIndex(selected, ListView.Contain));
    }
    onSelectedChanged: {
        selectedKey = C.rowKey(rows[selected]);
        list.positionViewAtIndex(selected, ListView.Contain);
    }
    Component.onCompleted: Root.State.loaded.push("notifs")

    Keys.onPressed: event => {
        const k = event.key;
        if (event.isAutoRepeat && (k === Qt.Key_Return || k === Qt.Key_Enter)) {
            event.accepted = true;
            return;
        }
        const row = rows[selected];
        if (k === Qt.Key_J || k === Qt.Key_Down)
            move(1);
        else if (k === Qt.Key_K || k === Qt.Key_Up)
            move(-1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_Space && row?.kind === "rule"))
            act();
        else if (row?.kind === "rule" && row.field === "stays" && (k === Qt.Key_H || k === Qt.Key_Left || k === Qt.Key_L || k === Qt.Key_Right))
            notifs.stepStay(row.app, k === Qt.Key_H || k === Qt.Key_Left ? -1 : 1);
        else if (k === Qt.Key_D && (event.modifiers & Qt.ShiftModifier))
            notifs.clear();
        else if (k === Qt.Key_D)
            dismiss();
        else if (row && k === Qt.Key_M)
            notifs.toggleRule(row.app, "muted");
        else if (row && k === Qt.Key_I) {
            // Show during Do Not Disturb is greyed while the app is muted, so i leaves it as it is.
            if (!Lib.ruleOf(notifs.rules, row.app)?.muted)
                notifs.toggleRule(row.app, "dnd");
        }
        else if (row && k === Qt.Key_S)
            notifs.cycleStay(row.app);
        else if (k === Qt.Key_Slash) {
            searching = true;
            input.forceActiveFocus();
        } else if (/^[1-9]$/.test(event.text))
            runChip(event.text);
        else if (k === Qt.Key_Escape)
            stepBack();
        else
            return;
        event.accepted = true;
    }

    // Everything drawn; the click-outside check reads a press on this as one on the centre.
    Item {
        objectName: "card"
        anchors.fill: parent

        // The header: the name, the count, the moon with the Do Not Disturb switch, and Clear all.
        Item {
            x: 16
            y: 16
            width: parent.width - 32
            height: 40

            Text {
                id: heading
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Notifications"
                color: centre.on
                font.family: centre.fonts.ui ?? ""
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            Text {
                id: countLabel
                anchors.verticalCenter: parent.verticalCenter
                x: heading.width + 10
                textFormat: Text.PlainText
                text: centre.countText
                color: centre.tones.muted
                font.family: centre.fonts.ui ?? ""
                font.pixelSize: 12
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(0xF0F65)
                    color: centre.notifs.dnd ? centre.on : centre.tones.muted
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 15
                }
                Switch {
                    id: dndSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    on: centre.notifs.dnd
                    Root.Click {
                        name: "notifs-dnd"
                        onTapped: centre.notifs.setDnd(!centre.notifs.dnd)
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: clearWord.implicitWidth + 24
                    height: 30
                    radius: 10
                    color: Qt.alpha(centre.on, 0.07)
                    Text {
                        id: clearWord
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "Clear all"
                        color: centre.on
                        font.family: centre.fonts.ui ?? ""
                        font.pixelSize: 12
                    }
                    Root.Click {
                        name: "notifs-clear"
                        onTapped: centre.notifs.clear()
                    }
                }
            }
        }

        // The search field, on / and while it holds text; Tab gives the keys back to the list, Esc too once it clears the search.
        Rectangle {
            id: searchBox
            visible: centre.searching || input.text !== ""
            x: 16
            y: 16 + 40 + 8
            width: parent.width - 32
            height: 44
            radius: 12
            color: Qt.alpha(centre.on, 0.07)

            Text {
                id: searchGlyph
                anchors.verticalCenter: parent.verticalCenter
                x: 14
                textFormat: Text.PlainText
                text: String.fromCodePoint(0xF0349)
                color: centre.tones.muted
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 16
            }
            TextInput {
                id: input
                anchors.verticalCenter: parent.verticalCenter
                x: searchGlyph.x + searchGlyph.width + 10
                width: parent.width - x - 14
                color: centre.on
                cursorDelegate: Rectangle {
                    width: 1
                    color: centre.tones.accent
                    visible: input.activeFocus
                }
                font.family: centre.fonts.ui ?? ""
                font.pixelSize: 13
                clip: true
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J))
                        centre.move(1);
                    else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K))
                        centre.move(-1);
                    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Escape) {
                        // Tab keeps the search and moves to the list; Esc drops it, and a second Esc closes the centre.
                        if (event.key === Qt.Key_Escape)
                            input.text = "";
                        centre.searching = false;
                        centre.forceActiveFocus();
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        centre.act();
                    else
                        return;
                    event.accepted = true;
                }
            }
        }

        // With nothing in the list, the bell is off and nothing is new.
        Column {
            id: emptyBox
            visible: centre.rows.length === 0
            y: centre.listTop + (120 - height) / 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: String.fromCodePoint(0xF009B)
                color: centre.tones.muted
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 28
            }
            Text {
                id: emptyWord
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: centre.query ? "No match" : "Nothing new"
                color: centre.tones.muted
                font.family: centre.fonts.ui ?? ""
                font.pixelSize: 13
            }
        }

        ListView {
            id: list
            visible: centre.rows.length > 0
            x: 16
            y: centre.listTop
            width: parent.width - 32
            height: Math.max(0, centre.height - y - 16)
            clip: true
            interactive: false
            model: centre.rows

            // Under the rows in the content, the wheel moves contentY as the keys do; a row's MouseArea takes no wheel.
            MouseArea {
                anchors.fill: parent
                z: -1
                acceptedButtons: Qt.NoButton
                onWheel: event => list.contentY = list.originY + D.wheeled(list.contentY - list.originY, event.angleDelta.y, list.contentHeight, list.height)
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: index === centre.selected
                readonly property string kind: modelData.kind
                readonly property var chips: current ? centre.chipsOf(modelData) : []
                width: ListView.view.width
                height: kindLoader.height

                function headDrawn() {
                    return kindLoader.item.drawn();
                }
                function noteDrawn() {
                    return kindLoader.item.drawn();
                }
                function actionsDrawn() {
                    return kind === "note" ? kindLoader.item.actionsDrawn() : [];
                }
                function ruleDrawn() {
                    return kindLoader.item.drawn();
                }

                // Only the row's own kind is made, so a long history builds one layout per row.
                Loader {
                    id: kindLoader
                    sourceComponent: row.kind === "head" ? headKind : row.kind === "rule" ? ruleKind : noteKind
                }

                // An app's head: a 22 px circle with its letter, the name and the rule's badge; a gap above all but the first.
                Component {
                    id: headKind
                Item {
                    id: headItem
                    width: row.width
                    height: (row.modelData.first ? 0 : 8) + 28 + 6

                    function drawn() {
                        return { text: headName.text + (badge.visible ? " · " + badgeWord.text : ""), app: headName.text, letter: circleLetter.text, circle: circle.width, badge: badge.visible ? badgeWord.text : "", elided: headName.truncated, badgeRight: badge.visible ? badge.mapToItem(null, badge.width, 0).x : null, selected: row.current };
                    }

                    Rectangle {
                        y: row.modelData.first ? 0 : 8
                        width: parent.width
                        height: 28
                        radius: 10
                        color: row.current ? Qt.alpha(centre.on, 0.07) : "transparent"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 4
                            spacing: 8

                            Rectangle {
                                id: circle
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                radius: 11
                                color: Qt.alpha(centre.on, 0.12)
                                Text {
                                    id: circleLetter
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: row.modelData.letter
                                    color: centre.on
                                    font.family: centre.fonts.ui ?? ""
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }
                            Text {
                                id: headName
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, headItem.width - 4 - 22 - 8 - (badge.visible ? badge.width + 8 : 0) - 8)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: row.modelData.name
                                color: centre.on
                                font.family: centre.fonts.ui ?? ""
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            Rectangle {
                                id: badge
                                visible: badgeWord.text !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                width: badgeWord.implicitWidth + 16
                                height: 20
                                radius: 10
                                color: Qt.alpha(centre.on, 0.12)
                                Text {
                                    id: badgeWord
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: row.modelData.badge
                                    color: centre.tones.muted
                                    font.family: centre.fonts.ui ?? ""
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Root.Click {
                            name: "notifs-head:" + row.index
                            onTapped: {
                                centre.selected = row.index;
                                centre.toggleRules(row.modelData.app);
                            }
                        }
                    }
                }
                }

                // A row of the app's rules tile: a glyph, the rule's name, then its switch or Stays on screen's pills.
                Component {
                    id: ruleKind
                    RuleRow {
                        width: row.width
                        height: implicitHeight
                        rule: row.modelData
                        current: row.current
                        onPicked: centre.selected = row.index
                    }
                }

                // A notification's tile: the summary bold with its age, the body muted on one line, a file chip, and the selected one's buttons.
                Component {
                    id: noteKind
                Item {
                    id: noteItem
                    width: row.width
                    height: tile.height + 6

                    function drawn() {
                        return { summary: summary.text, body: body.text, age: age.text, fill: String(tile.color), selected: row.current, file: fileChip.visible ? Object.assign(centre.box(fileChip), { text: fileName.text }) : null, box: centre.box(tile) };
                    }
                    function actionsDrawn() {
                        return Array.from({ length: buttons.count }, (_, i) => buttons.itemAt(i).drawn());
                    }

                    Rectangle {
                        id: tile
                        width: parent.width
                        height: noteColumn.implicitHeight + 24
                        radius: 12
                        color: Qt.alpha(centre.on, row.current ? 0.12 : 0.07)

                        // As in the toast: a file notification drags from its chip, one with no file drags its body; a press released short of a drag is a click.
                        Root.DragOut {
                            id: rowArea
                            property bool onChip: false
                            readonly property var payload: Lib.dragPayload(row.modelData.entry)
                            name: "notif-row:" + row.index
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            offering: onChip || payload.mime === "text/plain"
                            mime: ({ [payload.mime]: payload.data })
                            image: payload.mime === "text/uri-list" ? rowFace.url : ""
                            // Outside the island the window takes no input while a row drags, so the drop reaches the window under it.
                            onDraggingChanged: centre.dragging = dragging
                            // An arrival mid-drag rebuilds the rows, so a row that goes while dragging hands the window its input back.
                            Component.onDestruction: if (dragging)
                                centre.dragging = false
                            onClicked: mouse => {
                                centre.selected = row.index;
                                for (let i = 0; i < buttons.count; i++) {
                                    const b = buttons.itemAt(i);
                                    if (b.contains(b.mapFromItem(rowArea, mouse.x, mouse.y)))
                                        return centre.runChip(b.modelData.key);
                                }
                                centre.act();
                            }
                            onPressed: mouse => {
                                onChip = fileChip.visible && fileChip.contains(fileChip.mapFromItem(rowArea, mouse.x, mouse.y));
                                if (onChip)
                                    rowFace.grab();
                            }
                        }

                        Column {
                            id: noteColumn
                            x: 14
                            y: 12
                            width: parent.width - 28
                            spacing: 8

                            Column {
                                width: parent.width
                                Item {
                                    width: parent.width
                                    height: 18
                                    Text {
                                        id: summary
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - age.implicitWidth - 10
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        text: V.line(row.modelData.entry.summary)
                                        color: centre.on
                                        font.family: centre.fonts.ui ?? ""
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        id: age
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: parent.right
                                        textFormat: Text.PlainText
                                        text: C.ageText(centre.openedAt - row.modelData.entry.time)
                                        color: centre.tones.muted
                                        font.family: centre.fonts.ui ?? ""
                                        font.pixelSize: 11
                                    }
                                }
                                Text {
                                    id: body
                                    visible: text !== ""
                                    width: parent.width
                                    height: 18
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: V.line(row.modelData.entry.body)
                                    color: centre.tones.muted
                                    font.family: centre.fonts.ui ?? ""
                                    font.pixelSize: 13
                                }
                            }

                            // A file shows as a chip that drags out of the island.
                            Rectangle {
                                id: fileChip
                                readonly property var files: row.modelData.entry.files ?? []
                                visible: files.length > 0
                                width: Math.min(fileRow.implicitWidth + 22, parent.width)
                                height: 30
                                radius: 10
                                color: Qt.alpha(centre.on, 0.12)
                                Row {
                                    id: fileRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 10
                                    spacing: 8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        textFormat: Text.PlainText
                                        text: String.fromCodePoint(0xF0219)
                                        color: centre.on
                                        font.family: "Symbols Nerd Font Mono"
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        id: fileName
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, noteColumn.width - 22 - 22)
                                        elide: Text.ElideMiddle
                                        textFormat: Text.PlainText
                                        text: fileChip.files.length > 0 ? centre.chipLook.name(fileChip.files) : ""
                                        color: centre.on
                                        font.family: centre.fonts.ui ?? ""
                                        font.pixelSize: 12
                                    }
                                }
                            }

                            // Only the selected note shows its buttons, the first inverted.
                            Row {
                                visible: row.chips.length > 0
                                spacing: 8
                                Repeater {
                                    id: buttons
                                    model: row.chips
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        readonly property bool inverted: index === 0
                                        function drawn() {
                                            return Object.assign(centre.box(this), { text: word.text, key: modelData.key, inverted, fill: String(color), ink: String(word.color) });
                                        }
                                        objectName: "click:notif-chip:" + modelData.key
                                        // A sender's long label elides, so the buttons share the tile's width at most.
                                        width: Math.min(word.implicitWidth + 24, (noteColumn.width - 8 * (row.chips.length - 1)) / row.chips.length)
                                        height: 30
                                        radius: 10
                                        color: inverted ? centre.on : Qt.alpha(centre.on, 0.12)
                                        Text {
                                            id: word
                                            anchors.centerIn: parent
                                            width: Math.min(implicitWidth, parent.width - 24)
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                            text: V.line(modelData.text)
                                            color: parent.inverted ? centre.fill : centre.on
                                            font.family: centre.fonts.ui ?? ""
                                            font.pixelSize: 12
                                            font.weight: parent.inverted ? Font.Bold : Font.Normal
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            width: 0
                            height: 0
                            clip: true

                            Root.Island.DragFace {
                                id: rowFace
                                look: centre.chipLook
                                files: fileChip.files
                            }
                        }
                    }
                }
                }
            }
        }
    }

    // A row of an app's rules tile: a glyph, the rule's name, then its switch or Stays on screen's pills; the tile's corners round on its first and last rows, and Show during Do Not Disturb greys while the app is muted.
    component RuleRow: Item {
        id: ruleRow
        property var rule: null
        property bool current: false
        signal picked
        readonly property var set: rule ? Lib.ruleOf(centre.notifs.rules, rule.app) : undefined
        readonly property bool first: rule?.field === "muted"
        readonly property bool last: rule?.field === "stays"
        readonly property bool on: rule?.field === "muted" ? !!set?.muted : rule?.field === "dnd" ? !!set?.dnd : false
        readonly property var pills: [["Default", -1], ["3 s", 3000], ["10 s", 10000], ["Until dismissed", 0]]
        readonly property int stays: set?.stays >= 0 ? set.stays : -1
        implicitHeight: 44 + (first ? 4 : 0) + (last ? 4 + 6 : 0)

        function drawn() {
            return Object.assign(centre.box(line), { field: rule?.field ?? "", label: label.text, on, greyed: !!rule?.greyed, selected: current, pills: last ? Array.from({ length: pillRepeater.count }, (_, i) => pillRepeater.itemAt(i).drawn()) : [] });
        }

        Rectangle {
            width: parent.width
            height: 44 + (ruleRow.first ? 4 : 0) + (ruleRow.last ? 4 : 0)
            color: Qt.alpha(centre.on, 0.07)
            topLeftRadius: ruleRow.first ? 12 : 0
            topRightRadius: topLeftRadius
            bottomLeftRadius: ruleRow.last ? 12 : 0
            bottomRightRadius: bottomLeftRadius
        }
        Rectangle {
            id: line
            y: ruleRow.first ? 4 : 0
            x: 4
            width: parent.width - 8
            height: 44
            radius: 8
            color: ruleRow.current ? Qt.alpha(centre.on, 0.07) : "transparent"

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                spacing: 12
                opacity: ruleRow.rule?.greyed ? 0.4 : 1

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(({ muted: 0xF009B, dnd: 0xF0F65, stays: 0xF051B })[ruleRow.rule?.field] ?? 0xF009B)
                    color: ruleRow.on ? centre.on : centre.tones.muted
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 15
                }
                Text {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    width: line.width - 10 - 18 - 12 - 12 - 10 - (ruleRow.last ? pillRow.width : 38)
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: ({ muted: "Mute", dnd: "Show during Do Not Disturb", stays: "Stays on screen" })[ruleRow.rule?.field] ?? ""
                    color: centre.on
                    font.family: centre.fonts.ui ?? ""
                    font.pixelSize: 13
                }
                Switch {
                    visible: !ruleRow.last
                    anchors.verticalCenter: parent.verticalCenter
                    on: ruleRow.on
                }
                Row {
                    id: pillRow
                    visible: ruleRow.last
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Repeater {
                        id: pillRepeater
                        model: ruleRow.pills
                        Rectangle {
                            required property var modelData
                            readonly property bool lit: ruleRow.stays === modelData[1]
                            function drawn() {
                                return Object.assign(centre.box(this), { text: pillWord.text, on: lit, fill: String(color) });
                            }
                            width: pillWord.implicitWidth + 20
                            height: 26
                            radius: 8
                            color: lit ? centre.on : "transparent"
                            Text {
                                id: pillWord
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: parent.modelData[0]
                                color: parent.lit ? centre.fill : centre.tones.muted
                                font.family: centre.fonts.ui ?? ""
                                font.pixelSize: 12
                                font.weight: parent.lit ? Font.Bold : Font.Normal
                            }
                            Root.Click {
                                name: "notifs-stay:" + parent.modelData[0]
                                onTapped: {
                                    ruleRow.picked();
                                    centre.notifs.setStays(ruleRow.rule.app, parent.modelData[1]);
                                }
                            }
                        }
                    }
                }
            }
            // A click on a switch row flips it, as Enter does; the pills take their own clicks above this.
            Root.Click {
                z: -1
                name: "notifs-rule:" + (ruleRow.rule?.field ?? "")
                onTapped: {
                    ruleRow.picked();
                    if (!ruleRow.last)
                        centre.flipRule(ruleRow.rule);
                }
            }
        }
    }

    // A 38 x 22 switch: the knob at the right and filled while on.
    component Switch: Rectangle {
        property bool on: false
        width: 38
        height: 22
        radius: 11
        color: on ? centre.on : Qt.alpha(centre.on, 0.14)

        Rectangle {
            x: parent.on ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: parent.on ? centre.fill : centre.tones.muted
        }
    }
}

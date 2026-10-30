import Quickshell
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/notifs.mjs" as Lib
import "lib/voice.mjs" as V

// The notification centre, drawn in the Surfaces window.
Item {
    id: centre

    required property var theme
    // The Notifs service: its history, Do Not Disturb, per-app rules and the remove, clear, act and rule calls.
    required property var notifs
    property bool shown: false
    // True while a row's drag runs, so the surfaces' window lets the pointer through to the app it drops on.
    property bool dragging: false
    readonly property string query: input.text
    property int selected: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1
    // When the centre last opened; each row's age is counted to it, so the ages need no timer.
    property real openedAt: 0

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: V.listLook(theme.tokens)
    readonly property var chipLook: V.chipLook(theme.tokens)
    readonly property Root.Motion motion: Root.Motion {
        shown: centre.shown
        tokens: centre.theme.tokens
    }
    // The caps voices write d and D alike, so clear all reads ⇧D.
    readonly property var legendKeys: look.keys([["j/k", "move"], ["↵", "open"], ["d", "dismiss"], ["⇧D", "clear all"], ["m", "mute"], ["i", "DND"], ["s", "stay"], ["/", "search"], ["esc", "close"]])
    readonly property var hintKeys: look.keys([["/", "search"], ["esc", "close"]])
    readonly property var groups: Lib.group(Lib.visible(notifs.history, query))
    // One row per entry in group order; the first of each group carries its header.
    readonly property var rows: groups.reduce((all, g) => all.concat(g.entries.map((e, i) => ({
                        entry: e,
                        head: i === 0 ? look.groupHead(g.app, g.entries.length) : "",
                        rule: i === 0 ? Lib.ruleText(notifs.rules[g.app]) : ""
                    }))), [])

    function open(t0) {
        openT0 = t0;
        openedAt = Date.now();
        openMs = null;
        opens += 1;
        input.text = "";
        selected = 0;
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

    function move(by) {
        selected = Lib.clampSelected(selected + by, rows.length);
    }

    function act() {
        const row = rows[selected];
        if (row && notifs.act(row.entry.key))
            close();
    }

    // m, i and s set a rule for the selected row's app.
    function toggleRule(field) {
        const row = rows[selected];
        if (row)
            notifs.toggleRule(row.entry.app, field);
    }

    function cycleStay() {
        const row = rows[selected];
        if (row)
            notifs.cycleStay(row.entry.app);
    }

    function dismiss() {
        const row = rows[selected];
        if (row)
            notifs.remove(row.entry.key);
    }

    // An item's box in window coordinates, as a screenshot reads it.
    function box(item) {
        const p = item.mapToItem(null, 0, 0);
        return {
            x: p.x,
            y: p.y,
            w: item.width,
            h: item.height
        };
    }

    function state() {
        const d = rows.length > 0 ? list.itemAtIndex(selected) : null;
        const cur = d ? d.box : null;
        const heading = look.label.kind === "header" ? header : look.label.kind === "pill" ? pill : chip;
        return {
            open: shown,
            query: query,
            selected: selected,
            groups: groups.map(g => ({
                        app: g.app,
                        entries: g.entries.map(e => e.summary)
                    })),
            hint: rows.length === 0,
            hintKeys: hintKeys.map(k => k.key),
            ages: rows.map((r, i) => {
                const d = list.itemAtIndex(i);
                return d ? d.age : null;
            }),
            // Each row's file chip as drawn, null on a row about no file.
            chips: rows.map((r, i) => {
                const f = list.itemAtIndex(i)?.fileChip;
                return f ? { text: f.text, box: box(f) } : null;
            }),
            // Each group's head as drawn: its text, whether it elides, and how many lines it takes.
            heads: rows.map((r, i) => list.itemAtIndex(i)).filter(d => d && d.headItem.visible).map(d => ({
                        text: d.headItem.text,
                        elided: d.headItem.truncated,
                        lines: d.headItem.lineCount,
                        right: d.headItem.mapToItem(null, d.headItem.width, 0).x,
                        rule: d.headItem.rule.text,
                        ruleRight: d.headItem.rule.mapToItem(null, d.headItem.rule.width - d.headItem.rule.rightPadding, 0).x
                    })),
            cardRight: box(card).x + card.width,
            openMs: openMs,
            opens: opens,
            motion: motion.curves?.kind ?? null,
            settleMs: motion.settleMs,
            settled: motion.settled,
            drawing: centre.visible,
            cardBox: card.drawnBox(),
            frameLabel: card.frameLabel(),
            headingKind: look.label.kind,
            heading: heading.text,
            headingBox: box(heading),
            ruleBox: box(headRule),
            cursorFill: cur ? String(cur.color) : null,
            cursorBox: cur ? box(cur) : null,
            legend: legendKeys.map(k => k.key + " " + k.word).join("  "),
            legendKeys: legendKeys.map(k => k.key),
            legendSpacing: look.small.spacing,
            // The window has the keyboard; niri lists a layer Exclusive a moment before its keys arrive.
            keyboard: centre.Window.active
        };
    }

    onQueryChanged: selected = 0
    onRowsChanged: selected = Lib.clampSelected(selected, rows.length)
    onSelectedChanged: list.positionViewAtIndex(selected, ListView.Contain)
    Component.onCompleted: Root.State.loaded.push("notifs")

    visible: motion.drawing

    // Holds focus while the list is in use, where plain j/k move and d, D, m, i, s and / act.
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                centre.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                centre.move(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                centre.act();
            else if (event.key === Qt.Key_D && (event.modifiers & Qt.ShiftModifier))
                centre.notifs.clear();
            else if (event.key === Qt.Key_D)
                centre.dismiss();
            else if (event.key === Qt.Key_M)
                centre.toggleRule("muted");
            else if (event.key === Qt.Key_I)
                centre.toggleRule("dnd");
            else if (event.key === Qt.Key_S)
                centre.cycleStay();
            else if (event.key === Qt.Key_Slash)
                input.forceActiveFocus();
            else if (event.key === Qt.Key_Escape)
                centre.close();
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
            y: 168
            width: 640
            height: column.implicitHeight
            tokens: centre.theme.tokens
            role: "card"
            label: "Notifications"
            motion: centre.motion

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 0

                // The launcher's mode label names the centre: Paper's ink chip, Artboard's tint pill, Blueprint's header line.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 16
                    Layout.bottomMargin: 12
                    spacing: 12

                    Rectangle {
                        visible: look.label.kind === "chip"
                        implicitWidth: chip.implicitWidth + 14
                        implicitHeight: chip.implicitHeight + 6
                        color: look.label.fill
                        Text {
                            id: chip
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: look.heading("notifications", "")
                            color: look.label.color
                            font.family: fonts.ui
                            font.pixelSize: 10
                            font.letterSpacing: 1.4
                        }
                    }
                    Rectangle {
                        visible: look.label.kind === "pill"
                        implicitWidth: pill.implicitWidth + 18
                        implicitHeight: pill.implicitHeight + 6
                        radius: 8
                        color: look.label.fill
                        Text {
                            id: pill
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: look.heading("notifications", "")
                            color: look.label.color
                            font.family: fonts.ui
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }
                    Text {
                        id: header
                        visible: look.label.kind === "header"
                        textFormat: Text.PlainText
                        text: look.heading("notifications", "")
                        color: look.small.color
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: look.tabText(rows.length + " · newest first")
                        color: look.small.color
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }
                    Rectangle {
                        implicitWidth: dnd.implicitWidth + 14
                        implicitHeight: dnd.implicitHeight + 6
                        color: "transparent"
                        border.color: centre.notifs.dnd ? c.accent : c.line
                        border.width: 1
                        Text {
                            id: dnd
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: look.tabText("Do not disturb: " + (centre.notifs.dnd ? "on" : "off"))
                            color: centre.notifs.dnd ? c.accent : c.muted
                            font.family: look.small.font
                            font.pixelSize: look.small.size
                            font.letterSpacing: look.small.spacing
                        }
                    }
                }

                // Shown while a search is typed or has text; Tab gives the keys back to the list.
                TextInput {
                    id: input
                    visible: activeFocus || text !== ""
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.bottomMargin: 10
                    color: c.ink
                    font.family: fonts.mono
                    font.pixelSize: 13
                    clip: true
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J))
                            centre.move(1);
                        else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K))
                            centre.move(-1);
                        else if (event.key === Qt.Key_Tab)
                            keys.forceActiveFocus();
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            centre.act();
                        else if (event.key === Qt.Key_Escape)
                            centre.close();
                        else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: input.text === ""
                        text: "/ search"
                        color: c.muted
                        font: input.font
                    }
                }

                Rule {
                    id: headRule
                }

                // An empty list says so, then names its keys as the legend draws them.
                Flow {
                    visible: rows.length === 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 14
                    Layout.bottomMargin: 14
                    spacing: look.legend("").chips ? 8 : 14

                    Text {
                        textFormat: Text.PlainText
                        text: look.tabText(query ? "No match" : "No notifications")
                        color: look.small.color
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
                    }
                    Repeater {
                        model: centre.hintKeys
                        KeyChip {}
                    }
                }

                ListView {
                    id: list
                    visible: rows.length > 0
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    implicitHeight: Math.min(contentHeight, 480)
                    clip: true
                    interactive: false
                    model: rows

                    delegate: Column {
                        id: item
                        required property var modelData
                        required property int index
                        readonly property bool current: index === centre.selected
                        readonly property Item box: rowBox
                        readonly property string age: ageLabel.text
                        readonly property Item headItem: headLabel
                        readonly property Item fileChip: [beforeChip, underChip, afterChip].find(f => f.visible) ?? null
                        width: list.width

                        // An app name can be any length; it elides inside the card, before its rule.
                        Item {
                            id: headLabel
                            readonly property string text: headName.text + headRule.text
                            readonly property bool truncated: headName.truncated
                            readonly property int lineCount: headName.lineCount
                            readonly property Text rule: headRule
                            visible: item.modelData.head !== ""
                            width: parent.width
                            implicitHeight: headName.implicitHeight

                            Text {
                                id: headName
                                textFormat: Text.PlainText
                                width: Math.min(implicitWidth, parent.width - headRule.implicitWidth)
                                elide: Text.ElideRight
                                leftPadding: 20
                                topPadding: 10
                                bottomPadding: 4
                                text: item.modelData.head
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                            }

                            Text {
                                id: headRule
                                textFormat: Text.PlainText
                                x: headName.width
                                rightPadding: 20
                                topPadding: 10
                                bottomPadding: 4
                                text: item.modelData.rule
                                color: look.small.color
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                            }
                        }

                        // The launcher's cursor row: Paper's runs edge to edge, the others sit inset as tiles.
                        Rectangle {
                            id: rowBox
                            x: look.voice === "plain" ? 8 : look.voice === "bracket" ? 10 : 0
                            width: parent.width - 2 * x
                            implicitHeight: entry.implicitHeight + 20
                            radius: look.cursor.radius
                            color: item.current ? look.cursor.fill : "transparent"

                            RowLayout {
                                id: entry
                                anchors.fill: parent
                                anchors.leftMargin: look.voice === "caps" ? 20 : 12
                                anchors.rightMargin: anchors.leftMargin
                                anchors.topMargin: 10
                                anchors.bottomMargin: 10
                                spacing: 12

                                Text {
                                    visible: look.slot === "marker"
                                    Layout.alignment: Qt.AlignTop
                                    textFormat: Text.PlainText
                                    text: "▸"
                                    color: item.current ? look.cursor.marker : "transparent"
                                    font.family: fonts.ui
                                    font.pixelSize: 15
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        textFormat: Text.PlainText
                                        width: parent.width
                                        text: look.title(item.modelData.entry.summary)
                                        elide: Text.ElideRight
                                        color: item.current ? look.cursor.text : look.name.color
                                        font.family: look.name.font
                                        font.pixelSize: look.name.size
                                        font.weight: item.current ? look.cursor.weight : look.name.weight
                                        font.letterSpacing: look.name.spacing
                                    }
                                    Text {
                                        visible: text !== ""
                                        width: parent.width
                                        text: look.detailText(item.modelData.entry.body)
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        color: item.current ? look.cursor.detail : look.detail.color
                                        font.family: look.detail.font
                                        font.italic: look.detail.italic
                                        font.pixelSize: look.detail.size
                                        font.letterSpacing: look.detail.spacing ?? 0
                                    }
                                }
                                RowChip {
                                    id: beforeChip
                                    place: "beforeAge"
                                    current: item.current
                                    note: item.modelData.entry
                                }
                                // Blueprint's chip sits under the age.
                                Column {
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 8

                                    Text {
                                        id: ageLabel
                                        x: parent.width - width
                                        textFormat: Text.PlainText
                                        text: look.ageText(centre.openedAt - item.modelData.entry.time)
                                        color: item.current ? look.cursor.detail : c.muted
                                        font.family: fonts.mono
                                        font.pixelSize: 11
                                    }
                                    RowChip {
                                        id: underChip
                                        x: parent.width - width
                                        place: "underAge"
                                        current: item.current
                                        note: item.modelData.entry
                                    }
                                }
                                RowChip {
                                    id: afterChip
                                    place: "afterAge"
                                    current: item.current
                                    note: item.modelData.entry
                                }

                                Rectangle {
                                    visible: item.current && look.cursor.badge !== ""
                                    Layout.alignment: Qt.AlignTop
                                    implicitWidth: badge.implicitWidth + 14
                                    implicitHeight: badge.implicitHeight + 4
                                    radius: 6
                                    color: c.surface
                                    Text {
                                        id: badge
                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        text: look.cursor.badge
                                        color: look.cursor.text
                                        font.family: fonts.mono
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            // As in the toast: a file notification drags from its chip, one with no file drags its body.
                            MouseArea {
                                id: rowArea
                                property bool onChip: false
                                anchors.fill: parent
                                drag.target: rowOffer
                                onPressed: mouse => {
                                    const f = item.fileChip;
                                    onChip = f !== null && f.contains(f.mapFromItem(rowArea, mouse.x, mouse.y));
                                    if (onChip)
                                        rowFace.grab();
                                }
                            }

                            Item {
                                id: rowOffer
                                readonly property var payload: Lib.dragPayload(item.modelData.entry)
                                Drag.active: rowArea.drag.active && (rowArea.onChip || payload.mime === "text/plain")
                                Drag.dragType: Drag.Automatic
                                Drag.supportedActions: Qt.CopyAction
                                Drag.mimeData: ({ [payload.mime]: payload.data })
                                Drag.imageSource: payload.mime === "text/uri-list" ? rowFace.url : ""
                                Drag.hotSpot.x: -14
                                Drag.hotSpot.y: -18
                                Drag.onDragStarted: centre.dragging = true
                                Drag.onDragFinished: centre.dragging = false
                            }

                            Item {
                                width: 0
                                height: 0
                                clip: true

                                Root.Island.DragFace {
                                    id: rowFace
                                    look: centre.chipLook
                                    files: item.modelData.entry.files ?? []
                                }
                            }
                        }
                    }
                }

                Rule {}

                // The keys as the launcher's legend draws them: chips in Artboard, tracked caps or brackets in the others.
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: look.voice === "plain" ? 14 : look.voice === "bracket" ? 22 : 20
                    Layout.rightMargin: Layout.leftMargin
                    Layout.topMargin: look.voice === "plain" ? 10 : 12
                    Layout.bottomMargin: look.voice === "bracket" ? 14 : Layout.topMargin
                    spacing: look.legend("").chips ? 8 : 14

                    Repeater {
                        model: centre.legendKeys
                        KeyChip {}
                    }
                }
            }
        }
    }

    // A key and its word as the legend draws them, a chip in Artboard.
    component KeyChip: Rectangle {
        required property var modelData
        width: pair.implicitWidth + (look.legend("").chips ? 14 : 0)
        height: pair.implicitHeight + (look.legend("").chips ? 6 : 0)
        radius: 6
        color: look.chip.fill

        Row {
            id: pair
            anchors.centerIn: parent
            spacing: look.legend("").chips ? 6 : 5

            Text {
                textFormat: Text.PlainText
                text: modelData.key
                color: look.chip.key
                font.family: fonts.mono
                font.pixelSize: look.small.size
                font.letterSpacing: look.small.spacing
                font.bold: true
            }
            Text {
                textFormat: Text.PlainText
                text: modelData.word
                color: c.muted
                font.family: look.small.font
                font.pixelSize: look.small.size
                font.letterSpacing: look.small.spacing
            }
        }
    }

    // A row's chip, in the place the theme gives it; a row about no file has none.
    component RowChip: Root.Island.FileChip {
        property string place: ""
        property bool current: false
        property var note: null
        Layout.alignment: Qt.AlignVCenter
        width: implicitWidth
        height: implicitHeight
        look: chipLook.rowPlace === place ? chipLook : null
        at: current ? chipLook.cursor : chipLook.row
        files: note?.files ?? []
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
}

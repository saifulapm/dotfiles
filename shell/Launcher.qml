import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/launcher.mjs" as Lib
import "lib/clips.mjs" as Clips
import "lib/emoji.mjs" as Emoji
import "lib/voice.mjs" as L
import "lib/reminders.mjs" as Rem
import "lib/notes.mjs" as N

// Apps, windows, clipboard, calculator and commands, picked by the query's prefix, drawn in the Surfaces window.
Item {
    id: launcher

    required property var theme
    property bool shown: false
    readonly property string query: input.text
    // selected counts from scrollTop, the first of the eight rows drawn out of every row found.
    property int selected: 0
    property int scrollTop: 0
    property real wheelRest: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    // Enter acted on a row and closed the launcher; Esc never sends it.
    signal launched
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    // {id, name, genericName, keywords, icon, entry} per desktop entry, from the shell's scan.
    required property var apps
    // themes.json's colorschemes, as the shell read them.
    property var schemes: []
    // The Desk's reminders service, null until the Desk loads.
    property var reminders: null
    readonly property var pending: reminders ? reminders.list : []
    readonly property var parsed: Lib.parseQuery(query)
    readonly property string mode: parsed.mode
    // niri's windows as of entering windows mode.
    property var windowList: []
    // cliphist list's output as of entering clipboard mode; bin/dots-clip-store writes the same db.
    property string clipList: ""
    // [emoji, name, group] triples, read from shell/data/emoji.json the first time emoji mode is entered.
    property var emojiList: []
    // bin/dots-zones' answer as of entering calculator mode, for `= 17:00 nyc`; null until it answers.
    property var zones: null
    property bool emojiWanted: false
    // This machine's id, read as Goals reads it; the Remote rows leave this machine out.
    readonly property string machine: N.machineId(Quickshell.env("DOTS_MACHINE"), chezmoiFile.text(), hostnameFile.text())
    readonly property string clipDb: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/clips.db"
    // Every mode supplies rows as {title, detail, exec?, copy?}; a new mode adds a case here.
    readonly property var found: {
        switch (mode) {
        case "windows":
            return Lib.windowRows(windowList, parsed.q);
        case "clipboard":
            return Clips.clipRows(clipList, parsed.q, clipDb);
        case "emoji":
            return Emoji.emojiRows(emojiList, parsed.q);
        case "calculator":
            {
                const sum = Lib.calcRows(parsed.q);
                return sum.length ? sum : Lib.convertRows(parsed.q, Date.now(), zones);
            }
        case "reminder":
            return Rem.reminderRows(parsed.q, Date.now(), pending, reminders ? reminders.broken : false);
        case "commands":
            return Lib.commandRows(parsed.q, Quickshell.shellDir + "/../bin", machine);
        case "colorschemes":
            return Lib.schemeRows(schemes, parsed.q, theme.name, Quickshell.shellDir + "/../bin");
        case "apps":
            return Lib.rank(apps, parsed.q).map(a => ({
                        title: a.name,
                        detail: a.genericName,
                        icon: a.icon,
                        exec: ["niri", "msg", "action", "spawn", "--"].concat(a.entry.command)
                    }));
        }
        return [];
    }
    readonly property var rows: found.slice(scrollTop, scrollTop + 8)
    readonly property var look: L.launcherLook(theme.tokens)
    readonly property Root.Motion motion: Root.Motion {
        shown: launcher.shown
        tokens: launcher.theme.tokens
    }

    // mode is clipboard, emoji or colorschemes when a key opened the launcher straight into one; typed is the key that opened it from the overview.
    function open(t0, mode, typed) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        input.text = typed || ({ clipboard: "v ", emoji: ": ", colorschemes: "c " })[mode] || "";
        selected = 0;
        scrollTop = 0;
        shown = true;
        // Mod+V lands on the results so plain j/k move; a second Mod+V keeps the mode, so it lists again here.
        if (launcher.mode === "clipboard") {
            listClips();
            results.forceActiveFocus();
        } else {
            input.forceActiveFocus();
        }
    }

    // A window's icon is its app's desktop entry icon, else the theme's icon named by its app_id.
    function iconFor(appId) {
        const app = apps.find(a => a.id.toLowerCase() === appId.toLowerCase());
        return app ? app.icon : appId ? Quickshell.iconPath(appId, true) : "";
    }

    function listClips() {
        if (!clipper.running)
            clipper.running = true;
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

    // d on a pending reminder deletes it, and the cursor stays on the row that takes its place.
    function deleteReminder() {
        const row = rows[selected];
        if (!row || !row.reminderId)
            return;
        reminders.remove(row.reminderId);
        // A scrolled list keeps its window on the rows that are left.
        const s = Lib.scroll(scrollTop, selected, 0, found.length, 8);
        scrollTop = s.top;
        selected = s.selected;
    }

    function move(by) {
        const s = Lib.scroll(scrollTop, selected, by, found.length, 8);
        scrollTop = s.top;
        selected = s.selected;
    }

    // The wheel moves the window of rows; wheelRest holds a touchpad's part of a row.
    function turn(angle) {
        const s = Lib.wheel({ top: scrollTop, selected, rest: wheelRest }, angle, found.length, 8);
        scrollTop = s.top;
        selected = s.selected;
        wheelRest = s.rest;
    }

    // A click on a shown row does what Enter does on it.
    function runRow(index) {
        selected = index;
        launch(false);
    }

    // An app is spawned through niri, so it is niri's child and outlives a shell restart; copyOnly (Shift+Enter) runs a row's copyExec instead, when it has one.
    function launch(copyOnly) {
        const row = rows[selected];
        // A pending reminder or one that cannot be set has nothing to run.
        if (!row || (mode === "reminder" && !row.remind))
            return;
        if (row.remind) {
            // "20m" counts from Enter, not from when it was typed; a refusal keeps the launcher open on the row that says why.
            const now = Date.now();
            if (!reminders.add(Rem.parseReminder(parsed.q, now), now)) {
                close();
                launched();
            }
            return;
        }
        close();
        launched();
        if (copyOnly && row.copyExec)
            Quickshell.execDetached(row.copyExec);
        else if (row.exec)
            Quickshell.execDetached(Lib.stampedExec(row, Date.now()));
        else if (row.copy)
            Quickshell.execDetached(["wl-copy", "--", row.copy]);
    }

    // The rows of the footer: one unless its prefixes wrap.
    function legendLines() {
        return Math.max(1, new Set(footer.children.filter(k => k.visible && k.width > 0).map(k => k.y)).size);
    }

    function state() {
        const cur = rowRepeater.itemAt(selected);
        const box = cur ? cur.box : null;
        const p = box ? box.mapToItem(null, 0, 0) : null;
        const q = input.mapToItem(null, 0, 0);
        const nameBox = cur ? cur.nameText : null;
        const n = nameBox ? nameBox.mapToItem(null, 0, 0) : null;
        return JSON.stringify({
            open: shown,
            mode: mode,
            query: query,
            results: rows.map(r => r.title),
            names: rows.map(r => r.name ?? null),
            ids: rows.map(r => r.id ?? null),
            icons: rows.map(r => r.icon ?? null),
            selected: selected,
            top: scrollTop,
            marks: rows.map(r => !!r.current),
            strips: rows.map((r, i) => rowRepeater.itemAt(i)?.stripColors ?? null),
            openMs: openMs,
            opens: opens,
            motion: motion.curves?.kind ?? null,
            settleMs: motion.settleMs,
            motionMs: motion.curves ? { open: motion.curves.openMs, close: motion.curves.closeMs } : null,
            curve: motion.curves?.curve ?? null,
            rise: motion.curves?.rise ?? 0,
            closeTookMs: motion.closeTook,
            settled: motion.settled,
            drawing: launcher.visible,
            cardBox: card.drawnBox(),
            glassFill: String(card.drawnFill),
            nameFont: nameBox ? nameBox.fontInfo.family : null,
            prompt: { text: look.prompt.text, color: look.prompt.color },
            keyColor: footerKeys.count > 0 ? String(footerKeys.itemAt(0).keyGlyph.color) : null,
            keyFont: footerKeys.count > 0 ? footerKeys.itemAt(0).keyGlyph.fontInfo.family : null,
            keyBox: footerKeys.count > 0 ? { x: footerKeys.itemAt(0).keyGlyph.mapToItem(null, 0, 0).x, y: footerKeys.itemAt(0).keyGlyph.mapToItem(null, 0, 0).y, w: footerKeys.itemAt(0).keyGlyph.width, h: footerKeys.itemAt(0).keyGlyph.height } : null,
            cursorBadge: cur ? cur.badgeText : null,
            label: pill.text,
            count: found.length,
            slots: rows.map(r => r.icon || r.glyph || "tile"),
            cursorName: nameBox ? nameBox.text : null,
            cursorNameBox: n ? { x: n.x, y: n.y, w: nameBox.width, h: nameBox.height } : null,
            cursorFill: box ? String(box.color) : null,
            cursorBox: box ? { x: p.x, y: p.y, w: box.width, h: box.height } : null,
            cursorElided: cur ? cur.elided : null,
            cursorDetailWidth: cur ? cur.detailWidth : null,
            keys: rows.map((r, i) => rowRepeater.itemAt(i)?.keyText ?? null),
            heads: rows.map((r, i) => rowRepeater.itemAt(i)?.headText ?? null),
            pending: pending.length,
            queryFont: [input.font.family, input.font.pixelSize],
            queryBox: { x: q.x, y: q.y, w: input.width, h: input.height },
            detailFont: [look.detail.font, look.detail.size, look.detail.italic],
            legend: look.legendLine(mode),
            legendKeys: footerKeys.count,
            legendLines: legendLines(),
            legendOverflow: legendLines() > 1,
            // The window has the keyboard; niri lists a layer Exclusive a moment before its keys arrive.
            keyboard: launcher.Window.active
        });
    }

    onQueryChanged: {
        selected = 0;
        scrollTop = 0;
    }
    onModeChanged: {
        if (mode === "windows" && !lister.running)
            lister.running = true;
        if (mode === "clipboard")
            listClips();
        if (mode === "emoji")
            emojiWanted = true;
        if (mode === "calculator" && !zoner.running)
            zoner.running = true;
    }

    FileView {
        id: chezmoiFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/chezmoi/chezmoi.toml"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: hostnameFile
        path: "/etc/hostname"
        blockLoading: true
        printErrors: false
    }

    FileView {
        path: launcher.emojiWanted ? Quickshell.shellPath("data/emoji.json") : ""
        onLoaded: launcher.emojiList = JSON.parse(text())
    }

    Process {
        id: lister
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            id: listed
        }
        onExited: code => {
            try {
                launcher.windowList = JSON.parse(listed.text).map(w => Object.assign({
                            icon: launcher.iconFor(w.app_id || "")
                        }, w));
            } catch (e) {
                console.warn("launcher: niri windows exited " + code + ": " + e.message);
            }
        }
    }

    Process {
        id: clipper
        command: ["cliphist", "-db-path", launcher.clipDb, "list"]
        stdout: StdioCollector {
            id: clipped
        }
        // cliphist exits 1 until the first copy creates its db, which is an empty history.
        onExited: code => launcher.clipList = code === 0 ? clipped.text : ""
    }

    Process {
        id: zoner
        command: [Quickshell.shellDir + "/../bin/dots-zones"]
        stdout: StdioCollector {
            id: zoned
        }
        onExited: code => {
            try {
                launcher.zones = code === 0 ? JSON.parse(zoned.text) : null;
            } catch (e) {
                launcher.zones = null;
            }
        }
    }

    Component.onCompleted: Root.State.loaded.push("launcher")

    visible: motion.drawing

    Item {
        anchors.fill: parent

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
            tokens: launcher.theme.tokens
            motion: launcher.motion

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 0

                RowLayout {
                    id: field
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: Layout.leftMargin
                    Layout.topMargin: 16
                    Layout.bottomMargin: 16
                    spacing: 12

                    // The magnifier: a ring and a handle at 45 degrees.
                    Item {
                        implicitWidth: 18
                        implicitHeight: 18
                        Rectangle {
                            x: 2.5
                            y: 2.5
                            width: 11
                            height: 11
                            radius: 5.5
                            color: "transparent"
                            border.width: 1.6
                            border.color: look.prompt.color
                        }
                        Rectangle {
                            x: 11.5
                            y: 13.3
                            width: 6
                            height: 1.6
                            radius: 0.8
                            rotation: 45
                            color: look.prompt.color
                        }
                    }

                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        color: c.ink
                        font.family: look.query.font
                        font.pixelSize: look.query.size
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
                                launcher.launch(event.modifiers & Qt.ShiftModifier);
                            else if (event.key === Qt.Key_Escape)
                                launcher.close();
                            else
                                return;
                            event.accepted = true;
                        }
                    }

                    Rectangle {
                        implicitWidth: pill.implicitWidth + 18
                        implicitHeight: pill.implicitHeight + 6
                        radius: 8
                        color: look.label.fill
                        Text {
                            id: pill
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: look.label.text(launcher.mode)
                            color: look.label.color
                            font.family: fonts.ui
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }
                }

                Rule {}

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
                        else if (event.key === Qt.Key_D && launcher.mode === "reminder")
                            launcher.deleteReminder();
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            launcher.launch(event.modifiers & Qt.ShiftModifier);
                        else if (event.key === Qt.Key_Escape)
                            launcher.close();
                        else
                            return;
                        event.accepted = true;
                    }

                    // Under the rows, so a turn anywhere over the list scrolls it; a row's click area takes no wheel.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: event => launcher.turn(event.angleDelta.y)
                    }

                    Column {
                        id: list
                        y: 8
                        x: 8
                        width: parent.width - 2 * x

                        Text {
                            textFormat: Text.PlainText
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
                            id: rowRepeater
                            model: rows

                            // A row, under the pending head when it is the first pending reminder.
                            Column {
                                required property var modelData
                                required property int index
                                readonly property bool current: index === launcher.selected
                                readonly property bool elided: title.truncated
                                readonly property real detailWidth: detail.width
                                readonly property string keyText: keyChip.visible ? keyLabel.text : ""
                                readonly property string badgeText: badgeBox.visible ? badge.text : ""
                                readonly property string headText: modelData.head ? headLabel.text : ""
                                // A colorscheme row's strip as drawn, for the state.
                                readonly property var stripColors: modelData.swatches ? strip.children.filter(s => s.width > 0).map(s => String(s.color)) : null
                                readonly property Item box: rowBox
                                readonly property Item nameText: title
                                width: list.width

                                RowLayout {
                                    visible: !!modelData.head
                                    width: parent.width
                                    Text {
                                        id: headLabel
                                        Layout.fillWidth: true
                                        leftPadding: 12
                                        topPadding: 10
                                        bottomPadding: 4
                                        textFormat: Text.PlainText
                                        text: look.pendingHead(launcher.pending.length).text
                                        color: look.small.color
                                        font.family: look.small.font
                                        font.pixelSize: look.small.size
                                        font.letterSpacing: look.small.spacing
                                    }
                                    Text {
                                        rightPadding: 12
                                        topPadding: 10
                                        bottomPadding: 4
                                        textFormat: Text.PlainText
                                        text: look.pendingHead(launcher.pending.length).right
                                        color: look.small.color
                                        font.family: look.small.font
                                        font.pixelSize: look.small.size
                                        font.letterSpacing: look.small.spacing
                                    }
                                }

                            Rectangle {
                                id: rowBox
                                width: list.width
                                implicitHeight: row.implicitHeight + 20
                                radius: look.cursor.radius
                                color: current ? look.cursor.fill : "transparent"

                                Root.Click {
                                    name: "launcher-row:" + index
                                    onTapped: launcher.runRow(index)
                                }

                                RowLayout {
                                    id: row
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: anchors.leftMargin
                                    spacing: 12

                                    // A colorscheme row's slot holds the current scheme's dot instead of a tile.
                                    Text {
                                        visible: !!modelData.swatches
                                        Layout.preferredWidth: 10
                                        textFormat: Text.PlainText
                                        text: modelData.current ? "●" : ""
                                        color: c.accent
                                        font.family: fonts.mono
                                        font.pixelSize: 12
                                    }

                                    // An app's own icon at 32 px, else a tile holding the row's glyph, or a plain tile when it has neither.
                                    Rectangle {
                                        visible: !modelData.swatches
                                        implicitWidth: look.tile.size
                                        implicitHeight: look.tile.size
                                        radius: look.tile.radius
                                        color: modelData.icon ? "transparent" : look.tile.fill
                                        Image {
                                            anchors.fill: parent
                                            visible: !!modelData.icon
                                            source: modelData.icon || ""
                                            sourceSize.width: look.tile.size
                                            sourceSize.height: look.tile.size
                                            asynchronous: true
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !modelData.icon && !!modelData.glyph
                                            textFormat: Text.PlainText
                                            text: modelData.glyph ?? ""
                                            color: c.ink
                                            font.family: fonts.mono
                                            font.pixelSize: 16
                                        }
                                    }

                                    // The detail sits under the name.
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 1
                                        rowSpacing: 0

                                        Text {
                                            id: title
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            // The slot shows the row's glyph, so the title drops it.
                                            text: look.title(modelData.bare ? modelData.bare : modelData.title)
                                            elide: Text.ElideRight
                                            color: current ? look.cursor.text : look.name.color
                                            font.family: look.name.font
                                            font.pixelSize: look.name.size
                                            font.weight: current ? look.cursor.weight : look.name.weight
                                            font.letterSpacing: look.name.spacing
                                        }
                                        Text {
                                            id: detail
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: look.rowDetail(modelData)
                                            elide: Text.ElideRight
                                            color: current ? look.cursor.detail : look.detail.color
                                            font.family: look.detail.font
                                            font.italic: look.detail.italic
                                            font.pixelSize: look.detail.size
                                            font.letterSpacing: look.detail.spacing ?? 0
                                        }
                                    }

                                    // A colorscheme's paper, surface, accent and four ANSI colours.
                                    Row {
                                        id: strip
                                        visible: !!modelData.swatches
                                        Repeater {
                                            model: modelData.swatches ?? []
                                            Rectangle {
                                                required property string modelData
                                                width: 14
                                                height: 14
                                                color: modelData
                                            }
                                        }
                                    }

                                    // A row with a global key names it.
                                    Item {
                                        visible: !!modelData.key
                                        implicitWidth: keyChip.implicitWidth
                                        implicitHeight: keyChip.implicitHeight
                                        Rectangle {
                                            id: keyChip
                                            anchors.right: parent.right
                                            visible: !!modelData.key
                                            implicitWidth: keyLabel.implicitWidth + 14
                                            implicitHeight: keyLabel.implicitHeight + 4
                                            radius: look.keyChip.radius
                                            color: current ? look.keyChip.cursorFill : look.keyChip.fill
                                            border.width: look.keyChip.border
                                            border.color: current ? look.keyChip.cursorBorder : look.keyChip.borderColor
                                            Text {
                                                id: keyLabel
                                                anchors.centerIn: parent
                                                textFormat: Text.PlainText
                                                text: look.rowKey(modelData.key)
                                                color: current ? look.keyChip.cursorText : look.keyChip.text
                                                font.family: look.small.font
                                                font.pixelSize: look.keyChip.size
                                                font.letterSpacing: look.keyChip.spacing
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: badgeBox
                                        visible: current && look.cursor.badge !== ""
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
                            }
                            }
                        }
                    }
                }

                Rule {}

                // The prefixes start at the left as chips, and the moving keys end the line at the right.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: Layout.leftMargin
                    Layout.topMargin: 10
                    Layout.bottomMargin: Layout.topMargin
                    spacing: 14

                    Flow {
                        id: footer
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            id: footerKeys
                            model: look.legend(launcher.mode).keys

                            Rectangle {
                                required property var modelData
                                width: pair.implicitWidth + 14
                                height: pair.implicitHeight + 6
                                radius: 6
                                color: look.chip.fill

                                property alias keyGlyph: pairKey

                                Row {
                                    id: pair
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        id: pairKey
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
                        }
                    }

                    Text {
                        id: tail
                        textFormat: Text.PlainText
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        topPadding: 3
                        text: look.legend(launcher.mode).tail
                        color: c.muted
                        font.family: look.small.font
                        font.pixelSize: look.small.size
                        font.letterSpacing: look.small.spacing
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
}

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
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T

// Apps, windows, clipboard, calculator and commands, picked by the query's prefix, drawn inside the island on its fill.
Item {
    id: launcher

    required property var theme
    // The island reports this as its surface while the launcher is shown.
    readonly property string name: "launcher"
    // The island grows to this width for the launcher, as board 3 draws it.
    readonly property int wantWidth: 640
    readonly property bool busy: false
    property bool shown: false
    // True once the island has come to rest on the launcher; the surfaces' window sets it.
    property bool settled: false
    // The mode a typed prefix or a mode key picked, shown as a chip in the field in place of its prefix; "" in apps mode.
    property string chipMode: ""
    readonly property var chip: Lib.chipOf(chipMode)
    readonly property string query: Lib.prefixOf(chipMode) + input.text
    // selected counts from scrollTop, the first of the eight rows drawn out of every row found.
    property int selected: 0
    property int scrollTop: 0
    property real wheelRest: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    // Enter acted on a row and closed the launcher; Esc never sends it.
    signal launched
    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and the tones lifted to read on its fill.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue" })
    // The search field's glyph, a magnifier from Symbols Nerd Font.
    readonly property string searchGlyph: String.fromCodePoint(0xF0349)
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
    // Every mode supplies rows as {title, detail, exec?, copy?}, a new mode adding a case here; nothing lists until a key is typed.
    readonly property var found: {
        if (query === "")
            return [];
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
            return Lib.commandRows(parsed.q, Quickshell.shellDir + "/bin", machine);
        case "colorschemes":
            return Lib.schemeRows(schemes, parsed.q, theme.name, Quickshell.shellDir + "/bin");
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
    implicitHeight: column.implicitHeight + 32

    // mode is clipboard, emoji or colorschemes when a key opened the launcher straight into one; typed is the key that opened it from the overview.
    function open(t0, mode, typed) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        chipMode = ["clipboard", "emoji", "colorschemes"].indexOf(mode) >= 0 ? mode : "";
        input.text = typed || "";
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

    function state() {
        const cur = rowRepeater.itemAt(selected);
        const box = cur ? cur.box : null;
        const p = box ? box.mapToItem(null, 0, 0) : null;
        const f = field.mapToItem(null, 0, 0);
        const k = column.mapToItem(null, 0, 0);
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
            drawing: shown,
            settled: settled,
            cardBox: { x: k.x, y: k.y, w: column.width, h: column.height },
            count: found.length,
            // Each row's icon, as its image source, its glyph, or the letter drawn in its circle.
            slots: rows.map((r, i) => rowRepeater.itemAt(i)?.slot ?? null),
            cursorElided: cur ? cur.nameText.truncated : null,
            cursorDetailWidth: cur ? cur.detailWidth : null,
            cursorName: cur ? cur.nameText.text : null,
            cursorFill: box ? String(box.color) : null,
            cursorBox: box ? { x: p.x, y: p.y, w: box.width, h: box.height } : null,
            // Each drawn row's height and whether it has a fill; only the selected one has.
            rowHeights: rows.map((r, i) => rowRepeater.itemAt(i)?.box.height ?? null),
            filled: rows.map((r, i) => rowRepeater.itemAt(i) ? rowRepeater.itemAt(i).box.color.a > 0 : null),
            field: { x: f.x, y: f.y, w: field.width, h: field.height, text: input.text, placeholder: placeholder.visible ? placeholder.text : null },
            chip: chip ? { name: chip.name, glyph: chip.glyph, inverted: String(chipBox.color) === String(launcher.on) } : null,
            // Each row's name as drawn, cleaned of any control or bidi character.
            drawn: rows.map((r, i) => rowRepeater.itemAt(i)?.nameText.text ?? null),
            empty: empty.visible ? empty.text : null,
            heads: rows.map((r, i) => rowRepeater.itemAt(i)?.headText ?? null),
            pending: pending.length,
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
        command: [Quickshell.shellDir + "/bin/dots-zones"]
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

    // The click-outside test reads a press on this as one on the launcher.
    Column {
        id: column
        objectName: "card"
        x: 16
        y: 16
        width: launcher.width - 32
        spacing: 8

        // The search field: a tile a shade above the island's fill, the magnifier, then the query.
        Rectangle {
            id: field
            width: parent.width
            height: 48
            radius: 14
            color: Qt.alpha(launcher.on, 0.07)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                Text {
                    textFormat: Text.PlainText
                    text: launcher.searchGlyph
                    color: launcher.tones.muted
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 18
                }

                // The mode as an inverted chip: its glyph and name in the island's fill on the island's text.
                Rectangle {
                    id: chipBox
                    visible: !!launcher.chip
                    implicitWidth: chipRow.implicitWidth + 20
                    implicitHeight: 26
                    radius: 13
                    color: launcher.on

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: launcher.chip?.glyph ?? ""
                            color: launcher.fill
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 13
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: launcher.chip?.name ?? ""
                            color: launcher.fill
                            font.family: launcher.fonts.ui ?? ""
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: input.implicitHeight

                    Text {
                        id: placeholder
                        anchors.fill: parent
                        visible: input.text === "" && !launcher.chip
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
                        text: "Search"
                        color: launcher.tones.muted
                        font: input.font
                    }

                    TextInput {
                        id: input
                        anchors.fill: parent
                        color: launcher.on
                        font.family: launcher.fonts.ui ?? ""
                        font.pixelSize: 15
                        clip: true
                        focus: true
                        // A typed prefix becomes the chip, and the field keeps only what follows it.
                        onTextChanged: {
                            if (launcher.chipMode !== "")
                                return;
                            const m = Lib.parseQuery(text).mode;
                            if (m !== "apps") {
                                launcher.chipMode = m;
                                text = text.slice(2);
                            }
                        }
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
                            else if (event.key === Qt.Key_Backspace && input.text === "" && launcher.chipMode !== "")
                                launcher.chipMode = "";
                            else
                                return;
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        // Holds focus after Tab, where plain j/k move and / returns to the query.
        Item {
            id: results
            width: parent.width
            visible: launcher.query !== ""
            height: visible ? list.implicitHeight : 0
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
                width: parent.width
                spacing: 4

                // Nothing found: a muted magnifier over the query as typed.
                Column {
                    visible: launcher.rows.length === 0
                    width: parent.width
                    height: 96
                    topPadding: 18
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText
                        text: launcher.searchGlyph
                        color: launcher.tones.muted
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 26
                    }

                    Text {
                        id: empty
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, parent.width)
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: "No match for '" + look.title(launcher.parsed.q) + "'"
                        color: launcher.tones.muted
                        font.family: launcher.fonts.ui ?? ""
                        font.pixelSize: 13
                    }
                }

                Repeater {
                    id: rowRepeater
                    model: launcher.rows

                    // A row, under the pending head when it is the first pending reminder.
                    Column {
                        required property var modelData
                        required property int index
                        readonly property bool current: index === launcher.selected
                        readonly property string headText: modelData.head ? headLabel.text : ""
                        // A colorscheme row's strip as drawn, for the state.
                        readonly property var stripColors: modelData.swatches ? strip.children.filter(s => s.width > 0).map(s => String(s.color)) : null
                        readonly property Item box: rowBox
                        readonly property Item nameText: title
                        readonly property real detailWidth: note.width
                        readonly property string slot: modelData.icon || letter.text
                        width: list.width

                        Text {
                            id: headLabel
                            visible: !!modelData.head
                            leftPadding: 10
                            topPadding: 6
                            bottomPadding: 4
                            textFormat: Text.PlainText
                            text: look.pendingHead(launcher.pending.length).text
                            color: launcher.tones.muted
                            font.family: launcher.fonts.ui ?? ""
                            font.pixelSize: 11
                        }

                        // 48 px and flat: only the selected row has a fill.
                        Rectangle {
                            id: rowBox
                            width: list.width
                            height: 48
                            radius: 12
                            color: current ? Qt.alpha(launcher.on, 0.07) : "transparent"

                            Root.Click {
                                name: "launcher-row:" + index
                                onTapped: launcher.runRow(index)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12

                                // The app's own icon at 32 px, else the row's glyph or its first letter in a circle.
                                Rectangle {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    radius: modelData.glyph ? 16 : 10
                                    color: modelData.icon ? "transparent" : Qt.alpha(launcher.on, 0.10)
                                    Image {
                                        anchors.fill: parent
                                        visible: !!modelData.icon
                                        source: modelData.icon || ""
                                        sourceSize.width: 32
                                        sourceSize.height: 32
                                        asynchronous: true
                                    }
                                    Text {
                                        id: letter
                                        anchors.centerIn: parent
                                        visible: !modelData.icon
                                        textFormat: Text.PlainText
                                        text: modelData.glyph || look.title(modelData.bare || modelData.title).charAt(0).toUpperCase()
                                        color: launcher.on
                                        font.family: launcher.fonts.ui ?? ""
                                        font.pixelSize: modelData.glyph ? 16 : 14
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    id: title
                                    textFormat: Text.PlainText
                                    // The name keeps its own width, up to 60% of the row, and the note takes what is left.
                                    Layout.preferredWidth: Math.min(implicitWidth, parent.width * 0.6)
                                    // The slot shows the row's glyph, so the title drops it.
                                    text: look.title(modelData.bare ? modelData.bare : modelData.title)
                                    elide: Text.ElideRight
                                    color: launcher.on
                                    font.family: launcher.fonts.ui ?? ""
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }

                                Text {
                                    id: note
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: look.rowDetail(modelData)
                                    elide: Text.ElideRight
                                    color: launcher.tones.muted
                                    font.family: launcher.fonts.ui ?? ""
                                    font.pixelSize: 12
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
                            }
                        }
                    }
                }
            }
        }
    }
}

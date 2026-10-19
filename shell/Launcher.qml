import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/launcher.mjs" as Lib
import "lib/clips.mjs" as Clips
import "lib/emoji.mjs" as Emoji
import "lib/notes-look.mjs" as K

// Apps, windows, clipboard, calculator and commands, picked by the query's prefix, drawn in the Surfaces window.
Item {
    id: launcher

    required property var theme
    property bool shown: false
    readonly property string query: input.text
    property int selected: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    // {id, name, genericName, keywords, icon, entry} per desktop entry, from the shell's scan.
    required property var apps
    readonly property var parsed: Lib.parseQuery(query)
    readonly property string mode: parsed.mode
    // niri's windows as of entering windows mode.
    property var windowList: []
    // cliphist list's output as of entering clipboard mode; bin/dots-clip-store writes the same db.
    property string clipList: ""
    // [emoji, name, group] triples, read from shell/data/emoji.json the first time emoji mode is entered.
    property var emojiList: []
    property bool emojiWanted: false
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
            return Lib.calcRows(parsed.q);
        case "commands":
            // The user manager's PATH lacks the repo's bin/, so dots is the one beside this shell.
            return Lib.commandRows(parsed.q).map(r => r.exec[0] === "dots" ? Object.assign({}, r, {
                        exec: [Quickshell.shellDir + "/../bin/dots"].concat(r.exec.slice(1))
                    }) : r);
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
    readonly property var rows: found.slice(0, 8)
    // In apps mode the footer names every prefix; inside a mode it keeps to the moving keys.
    readonly property string legend: theme.tokens ? K.keyLine(theme.tokens, mode === "apps" ? Lib.LEGEND : Lib.LEGEND.slice(5)) : ""
    readonly property var chipNames: ({ apps: "APPS", windows: "WINDOWS", clipboard: "CLIPBOARD", emoji: "EMOJI", calculator: "CALC", commands: "COMMANDS" })

    // mode is clipboard or emoji when a key opened the launcher straight into one.
    function open(t0, mode) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        input.text = ({ clipboard: "v ", emoji: ": " })[mode] || "";
        selected = 0;
        shown = true;
        // Mod+V lands on the results so plain j/k move; a second Mod+V keeps the mode, so it lists again here.
        if (launcher.mode === "clipboard") {
            listClips();
            results.forceActiveFocus();
        } else {
            input.forceActiveFocus();
        }
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

    function move(by) {
        selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }

    // An app is spawned through niri, so it is niri's child and outlives a shell restart.
    function launch() {
        const row = rows[selected];
        if (!row)
            return;
        close();
        if (row.exec)
            Quickshell.execDetached(row.exec);
        else if (row.copy)
            Quickshell.execDetached(["wl-copy", "--", row.copy]);
    }

    function state() {
        return JSON.stringify({
            open: shown,
            mode: mode,
            query: query,
            results: rows.map(r => r.title),
            ids: rows.map(r => r.id ?? null),
            icons: rows.map(r => r.icon ?? null),
            selected: selected,
            openMs: openMs,
            opens: opens,
            legend: legend,
            legendOverflow: footer.contentWidth > footer.width - footer.leftPadding - footer.rightPadding,
            // The window has the keyboard; niri lists a layer Exclusive a moment before its keys arrive.
            keyboard: launcher.Window.active
        });
    }

    onQueryChanged: selected = 0
    onModeChanged: {
        if (mode === "windows" && !lister.running)
            lister.running = true;
        if (mode === "clipboard")
            listClips();
        if (mode === "emoji")
            emojiWanted = true;
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
                launcher.windowList = JSON.parse(listed.text);
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

    Component.onCompleted: Root.State.loaded.push("launcher")

    visible: shown

    Item {
        anchors.fill: parent

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
            tokens: launcher.theme.tokens
            label: "Launcher"

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 18
                    Layout.bottomMargin: 14
                    spacing: 14

                    Rectangle {
                        implicitWidth: chip.implicitWidth + 14
                        implicitHeight: chip.implicitHeight + 6
                        color: c.ink
                        Text {
                            id: chip
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: launcher.chipNames[launcher.mode]
                            color: c.surface
                            font.family: fonts.ui
                            font.pixelSize: 10
                            font.letterSpacing: 1.4
                        }
                    }

                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        color: c.ink
                        font.family: fonts.display
                        font.pixelSize: 34
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
                                launcher.launch();
                            else if (event.key === Qt.Key_Escape)
                                launcher.close();
                            else
                                return;
                            event.accepted = true;
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: found.length + " FOUND"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 10
                        font.letterSpacing: 1.4
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.ink
                }

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
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            launcher.launch();
                        else if (event.key === Qt.Key_Escape)
                            launcher.close();
                        else
                            return;
                        event.accepted = true;
                    }

                    Column {
                        id: list
                        y: 8
                        width: parent.width

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
                            model: rows

                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool current: index === launcher.selected
                                width: list.width
                                implicitHeight: row.implicitHeight + 22
                                color: current ? c.ink : "transparent"

                                RowLayout {
                                    id: row
                                    anchors.fill: parent
                                    anchors.leftMargin: 20
                                    anchors.rightMargin: 20
                                    spacing: 14

                                    Text {
                                        textFormat: Text.PlainText
                                        text: "▸"
                                        color: current ? c.accent : "transparent"
                                        font.family: fonts.ui
                                        font.pixelSize: 15
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        elide: Text.ElideRight
                                        color: current ? c.surface : c.ink
                                        font.family: fonts.ui
                                        font.pixelSize: 15
                                        font.weight: current ? Font.Medium : Font.Normal
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.maximumWidth: 260
                                        text: modelData.detail
                                        elide: Text.ElideRight
                                        color: current ? c.line : c.muted
                                        font.family: fonts.display
                                        font.italic: true
                                        font.pixelSize: 16
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: c.ink
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    leftPadding: 20
                    rightPadding: 20
                    topPadding: 12
                    bottomPadding: 12
                    horizontalAlignment: Text.AlignRight
                    id: footer
                    text: launcher.legend
                    // Blueprint's bracketed keys run wider than the card, so the legend wraps onto a second line.
                    wrapMode: Text.Wrap
                    color: c.muted
                    font.family: fonts.ui
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
            }
        }
    }
}

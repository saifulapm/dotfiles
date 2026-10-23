//@ pragma AppId files
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "services" as Services
import "lib/files.mjs" as F
import "lib/picker.mjs" as P
import "lib/status.mjs" as Status
import "lib/voice.mjs" as L

// Files, an App: its own qs process started by bin/dots-files, a normal window in the shell's theme; the process ends with its window.
ShellRoot {
    id: app

    readonly property string home: Quickshell.env("HOME")
    property string folder: home
    // Process start to the window's first frame, set once.
    property var firstFrameMs: null
    property var entries: []
    property bool hidden: false
    // False from leaving a folder until its rows are listed, so no key acts on the last folder's rows.
    property bool listed: false
    // A folder changed while it was being listed is listed again.
    property bool stale: false
    // The row the cursor lands on once the folder is listed: the folder just left, after h.
    property string landOn: ""
    property int selected: 0
    property var marked: []
    // Keys typed before the folder's rows landed, played on them once they do.
    property var held: []
    // list or places: which pane j, k and Enter move in.
    property string side: "list"
    property int placeAt: 0
    property var pins: []

    readonly property var rows: P.shownRows(entries, {
        hidden: hidden
    })
    readonly property var cursorRow: rows[selected] ?? null
    readonly property var fixedPlaces: F.places(home).map(p => Object.assign({ group: "places" }, p))
    readonly property var trash: ({
            label: "Trash",
            path: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/Trash/files",
            group: "trash"
        })
    // Trash is drawn apart, at the foot of the column, and is last for the keys too.
    readonly property var allPlaces: fixedPlaces.concat(pins.map(p => ({
                label: p.label,
                path: p.path,
                group: "pinned"
            }))).concat([trash])
    readonly property var status: F.statusText(voice, rows, marked, selected)

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property string voice: look.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property var head: F.headText(voice, home, folder)

    // qs has no quit, so a child ends its parent: the process must not outlive the window.
    function quit() {
        ender.running = true;
    }

    function pathOf(row) {
        return (folder === "/" ? "" : folder) + "/" + row.name;
    }

    function enter(path) {
        folder = path;
        marked = [];
        selected = 0;
        landOn = "";
        entries = [];
        listed = false;
        list();
    }

    function up() {
        if (folder === "/")
            return;
        const left = folder.slice(folder.lastIndexOf("/") + 1);
        enter(folder.slice(0, folder.lastIndexOf("/")) || "/");
        landOn = left;
    }

    function list() {
        if (lister.running) {
            stale = true;
            return;
        }
        lister.command = ["python3", "-c", P.LIST_SCRIPT, folder];
        lister.running = true;
    }

    function move(by) {
        if (side === "places")
            placeAt = Math.max(0, Math.min(allPlaces.length - 1, placeAt + by));
        else
            selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }

    // l or Enter: into a folder, or the file opens in its default app.
    function choose() {
        if (side === "places") {
            side = "list";
            if (allPlaces[placeAt].path !== folder)
                enter(allPlaces[placeAt].path);
            return;
        }
        if (!cursorRow)
            return;
        if (cursorRow.dir)
            enter(pathOf(cursorRow));
        else if (!cursorRow.undecodable)
            Quickshell.execDetached(["gio", "open", pathOf(cursorRow)]);
    }

    // Space marks the cursor row and steps down, as yazi's does.
    function mark() {
        marked = F.toggleMark(marked, cursorRow);
        move(1);
    }

    function toSide() {
        if (side === "places") {
            side = "list";
            return;
        }
        const here = allPlaces.findIndex(p => p.path === folder);
        placeAt = here >= 0 ? here : 0;
        side = "places";
    }

    // The keys that act on the listed rows; before they land, they wait for them.
    function rowKey(k) {
        if (side === "list" && !listed) {
            held = held.concat([k]);
            return;
        }
        if (k === "down")
            move(1);
        else if (k === "up")
            move(-1);
        else if (k === "in")
            choose();
        else if (k === "out")
            up();
        else if (k === "mark")
            mark();
    }

    // The cursor row as drawn, for checks that read the window rather than the data.
    function drawnCursor() {
        const item = rowList.itemAtIndex(selected);
        return item ? item.drawn() : null;
    }

    onRowsChanged: if (selected >= rows.length)
        selected = Math.max(0, rows.length - 1)

    Component.onCompleted: list()

    Services.Theme {
        id: theme
    }

    Process {
        id: ender
        command: ["sh", "-c", "kill -TERM $PPID"]
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() {
            app.quit();
        }
    }

    // The folder's entries, listed off the render loop.
    Process {
        id: lister
        stdout: StdioCollector {
            id: listOut
        }
        onExited: {
            if (app.stale) {
                app.stale = false;
                Qt.callLater(app.list);
                return;
            }
            let found = [];
            try {
                found = JSON.parse(listOut.text);
            } catch (e) {
                found = [];
            }
            app.entries = Array.isArray(found) ? found : [];
            const back = app.rows.findIndex(r => r.name === app.landOn);
            app.selected = back >= 0 ? back : 0;
            app.listed = true;
            // An l here that opened a folder holds the keys after it again, for that folder's rows.
            const keys = app.held;
            app.held = [];
            for (const k of keys)
                app.rowKey(k);
        }
    }

    FileView {
        id: bookmarksFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || app.home + "/.config") + "/gtk-3.0/bookmarks"
        printErrors: false
        onLoaded: app.pins = P.parseBookmarks(text())
        onLoadFailed: app.pins = []
    }

    FileView {
        id: uptime
        path: "/proc/uptime"
        blockAllReads: true
    }

    FileView {
        id: selfStat
        path: "/proc/self/stat"
        blockLoading: true
    }

    // Read at call time; blockAllReads, or text() after reload() is the previous call's RSS.
    FileView {
        id: procStatus
        path: "/proc/self/status"
        blockAllReads: true
    }

    IpcHandler {
        target: "files"

        function state(): string {
            procStatus.reload();
            return JSON.stringify({
                folder: app.folder,
                title: win.title,
                head: app.head,
                voice: app.voice,
                firstFrameMs: app.firstFrameMs,
                rssKiB: Status.rssKiB(procStatus.text()),
                listed: app.listed,
                side: app.side,
                selected: app.selected,
                cursor: app.cursorRow ? app.cursorRow.name : null,
                rows: app.rows.map(r => r.name),
                dirs: app.rows.filter(r => r.dir).map(r => r.name),
                marked: app.marked,
                places: app.allPlaces.map(p => p.group + ":" + p.label),
                placeAt: app.placeAt,
                path: pathLine.text,
                count: countLabel.text,
                status: {
                    path: statusPath.text,
                    counts: statusCounts.text,
                    at: statusAt.text
                },
                drawn: app.drawnCursor()
            });
        }
    }

    FloatingWindow {
        id: win

        title: app.head.folder
        implicitWidth: 1200
        implicitHeight: 716
        color: c.surface ?? "white"

        Connections {
            target: win.contentItem.Window.window
            function onFrameSwapped() {
                if (app.firstFrameMs !== null)
                    return;
                uptime.reload();
                app.firstFrameMs = Status.processAgeMs(uptime.text(), selfStat.text());
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                const k = event.key;
                const t = event.text;
                if (k === Qt.Key_Escape)
                    app.quit();
                else if (k === Qt.Key_Tab)
                    app.toSide();
                else if (t === "j" || k === Qt.Key_Down)
                    app.rowKey("down");
                else if (t === "k" || k === Qt.Key_Up)
                    app.rowKey("up");
                else if (t === "l" || k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter)
                    app.rowKey("in");
                else if (t === "h" || k === Qt.Key_Left || k === Qt.Key_Backspace)
                    app.rowKey("out");
                else if (k === Qt.Key_Space)
                    app.rowKey("mark");
                else
                    return;
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The header: Files' label, the folder in the display face, the key that opens it.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                spacing: 10

                Text {
                    textFormat: Text.PlainText
                    text: app.head.label
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: 10
                    font.letterSpacing: plain ? 0 : 1.4
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: app.head.folder
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: c.ink ?? "black"
                    font.family: bracket ? fonts.mono ?? "" : fonts.display ?? ""
                    font.pixelSize: 18
                }
                Rectangle {
                    readonly property bool boxed: look.label.kind !== "header"
                    implicitWidth: chipText.implicitWidth + (boxed ? 14 : 0)
                    implicitHeight: chipText.implicitHeight + (boxed ? 4 : 0)
                    radius: look.label.kind === "pill" ? 8 : 0
                    color: boxed ? look.label.fill : "transparent"

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: app.head.chip
                        color: parent.boxed ? look.label.color : c.accent
                        font.family: look.small.font
                        font.pixelSize: 10
                        font.letterSpacing: plain ? 0 : 1.4
                    }
                }
            }

            Rule {}

            // The folder from ~, and how many rows it holds.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 9
                Layout.bottomMargin: 9
                spacing: 10

                Text {
                    id: pathLine
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: P.oneLine(F.tilde(app.home, app.folder))
                    maximumLineCount: 1
                    elide: Text.ElideMiddle
                    color: c.ink ?? "black"
                    font.family: fonts.mono ?? ""
                    font.pixelSize: 13
                }
                Text {
                    id: countLabel
                    textFormat: Text.PlainText
                    text: F.countText(app.voice, app.rows.length, app.hidden)
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: 11
                    font.letterSpacing: look.small.spacing
                }
            }

            Rule {}

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Home, Downloads, Codes, Pictures and Documents, the GTK bookmarks as PINNED, and Trash at the foot.
                ColumnLayout {
                    Layout.preferredWidth: 200
                    Layout.maximumWidth: 200
                    Layout.fillHeight: true
                    Layout.margins: 8
                    spacing: 0

                    Repeater {
                        model: app.allPlaces.slice(0, -1)

                        PlaceRow {
                            required property var modelData
                            required property int index
                            place: modelData
                            at: index
                            heading: index === 0 ? "places" : modelData.group !== app.allPlaces[index - 1].group ? modelData.group : ""
                        }
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                    PlaceRow {
                        place: app.trash
                        at: app.allPlaces.length - 1
                        heading: ""
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 1
                    color: look.rule.color
                }

                // The rows: folders first, each with its size or item count and when it changed.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 8
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        Layout.bottomMargin: 6
                        spacing: 12

                        Item {
                            implicitWidth: 20
                        }
                        Head {
                            Layout.fillWidth: true
                            text: plain ? "Name ↑" : "NAME"
                        }
                        Head {
                            Layout.preferredWidth: 90
                            horizontalAlignment: Text.AlignRight
                            text: plain ? "Size" : "SIZE"
                        }
                        Head {
                            Layout.preferredWidth: 130
                            horizontalAlignment: Text.AlignRight
                            text: plain ? "Modified" : "MODIFIED"
                        }
                    }

                    ListView {
                        id: rowList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: app.rows
                        currentIndex: app.selected
                        highlightMoveDuration: 0
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: index === app.selected && app.side === "list"
                            readonly property bool isMarked: app.marked.indexOf(modelData.name) >= 0
                            readonly property color ink: isCurrent ? look.cursor.text : c.ink ?? "black"
                            readonly property color dim: isCurrent ? look.cursor.detail : c.muted ?? "gray"
                            function drawn() {
                                return {
                                    name: nameText.text,
                                    lines: nameText.lineCount,
                                    elided: nameText.truncated,
                                    size: sizeLabel.text,
                                    modified: dateLabel.text,
                                    mark: markLabel.visible ? markLabel.text : ""
                                };
                            }
                            width: rowList.width
                            height: 32
                            radius: look.cursor.radius
                            // The cursor row is filled; a marked row is tinted and boxed, as the marked board draws it.
                            color: isCurrent ? look.cursor.fill : isMarked ? Qt.alpha(c.accent ?? "red", 0.1) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Item {
                                    implicitWidth: 20
                                    implicitHeight: 16

                                    Text {
                                        id: markLabel
                                        visible: rowItem.isMarked
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: bracket ? "[x]" : "■"
                                        color: rowItem.isCurrent ? look.cursor.text : bracket ? c.accent ?? "red" : c.ink ?? "black"
                                        font.family: fonts.mono ?? ""
                                        font.pixelSize: bracket ? 12 : 10
                                    }
                                }
                                Text {
                                    id: nameText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: P.oneLine(rowItem.modelData.name) + (rowItem.modelData.dir ? "/" : "")
                                    maximumLineCount: 1
                                    elide: Text.ElideMiddle
                                    color: rowItem.ink
                                    font.family: bracket ? fonts.mono ?? "" : fonts.ui ?? ""
                                    font.pixelSize: 13
                                    font.weight: rowItem.isCurrent ? look.cursor.weight : rowItem.modelData.dir ? Font.Medium : Font.Normal
                                }
                                Text {
                                    id: sizeLabel
                                    Layout.preferredWidth: 90
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: F.sizeText(app.voice, rowItem.modelData)
                                    color: rowItem.dim
                                    font.family: fonts.mono ?? ""
                                    font.pixelSize: 12
                                }
                                Text {
                                    id: dateLabel
                                    Layout.preferredWidth: 130
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: F.dateText(app.voice, rowItem.modelData.mtime, Date.now())
                                    color: rowItem.dim
                                    font.family: fonts.mono ?? ""
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }

            Rule {}

            // The status line: the cursor's path, the counts and where the cursor is.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                spacing: 16

                Text {
                    id: statusPath
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: app.cursorRow ? P.oneLine(F.tilde(app.home, app.pathOf(app.cursorRow))) : ""
                    maximumLineCount: 1
                    elide: Text.ElideMiddle
                    color: c.ink ?? "black"
                    font.family: fonts.mono ?? ""
                    font.pixelSize: 12
                }
                Text {
                    id: statusCounts
                    textFormat: Text.PlainText
                    text: app.status.counts
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: 11
                }
                Text {
                    id: statusAt
                    textFormat: Text.PlainText
                    text: app.status.at
                    color: c.ink ?? "black"
                    font.family: fonts.mono ?? ""
                    font.pixelSize: 11
                }
            }

            Rule {}

            // The keys, each with its word.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 8
                Layout.bottomMargin: 10
                spacing: 14

                Repeater {
                    model: F.keyStrip(app.voice)

                    Row {
                        required property var modelData
                        spacing: 6

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.key
                            color: bracket ? c.accent ?? "red" : c.ink ?? "black"
                            font.family: fonts.mono ?? ""
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: modelData.word
                            color: look.small.color
                            font.family: look.small.font
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: look.rule.color
    }

    component Head: Text {
        textFormat: Text.PlainText
        color: look.small.color
        font.family: look.small.font
        font.pixelSize: 10
        font.letterSpacing: look.small.spacing
    }

    // One place: its group's head above the first of the group, then the row, lit where the folder is and filled under the cursor.
    component PlaceRow: ColumnLayout {
        id: placeRow
        property var place
        property int at
        property string heading
        readonly property bool here: place.path === app.folder
        readonly property bool atCursor: app.side === "places" && app.placeAt === at
        Layout.fillWidth: true
        spacing: 0

        Text {
            visible: placeRow.heading !== ""
            topPadding: placeRow.at === 0 ? 4 : 10
            bottomPadding: 6
            leftPadding: 12
            textFormat: Text.PlainText
            text: plain ? placeRow.heading.charAt(0).toUpperCase() + placeRow.heading.slice(1) : placeRow.heading.toUpperCase()
            color: look.small.color
            font.family: look.small.font
            font.pixelSize: 10
            font.letterSpacing: look.small.spacing
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: plain ? 8 : look.cursor.radius
            color: placeRow.atCursor ? look.cursor.fill : placeRow.here ? Qt.alpha(c.ink ?? "black", 0.06) : "transparent"

            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                width: parent.width - 20
                textFormat: Text.PlainText
                // A pin is a folder's own name and keeps its case.
                text: P.oneLine(placeRow.place.label)
                maximumLineCount: 1
                elide: Text.ElideRight
                color: placeRow.atCursor ? look.cursor.text : placeRow.here ? c.ink ?? "black" : c.muted ?? "gray"
                font.family: bracket ? fonts.mono ?? "" : fonts.ui ?? ""
                font.pixelSize: 13
                font.weight: placeRow.here ? Font.Medium : Font.Normal
            }
        }
    }
}

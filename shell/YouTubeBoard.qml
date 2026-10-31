import QtQuick
import QtQuick.Layouts
import "lib/youtube-queue.mjs" as Q
import "lib/youtube.mjs" as YT

// The YouTube window as each theme's board draws it: the title strip, the sidebar of views beside the list pane, the now-playing line and the key legend.
Rectangle {
    id: board

    required property var yt

    readonly property var c: yt.c
    readonly property var look: yt.look
    readonly property string voice: yt.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property string bodyFont: (bracket ? yt.fonts.mono : yt.fonts.ui) ?? ""
    readonly property color ruleColor: (caps ? c.ink : c.line) ?? "gray"
    readonly property bool fieldFocused: field.activeFocus
    readonly property string queryText: field.text
    // Search draws no empty text but an opened channel's once it has answered with no uploads.
    readonly property var emptyText: yt.view !== "search" ? yt.look.empty(yt.view) : yt.opened && yt.opened.kind === "channel" && !yt.opened.list.loading && yt.failed === null ? yt.look.empty("channel") : null
    // A failed search's list is its error block.
    readonly property bool failing: yt.view === "search" && yt.failed !== null

    function focusField() {
        field.forceActiveFocus();
    }

    function focusKeys() {
        keyTarget.forceActiveFocus();
    }

    function state() {
        const sidebar = [];
        if (libraryLabel.visible)
            sidebar.push(libraryLabel.text);
        for (let i = 0; i < placeList.count; i++)
            sidebar.push(placeList.itemAt(i).drawn());
        sidebar.push(playlistsLabel.text);
        for (let i = 0; i < listList.count; i++)
            sidebar.push(listList.itemAt(i).drawn());
        if (noneLine.visible)
            sidebar.push([noneKey.text, noneRest.text].filter(t => t).join(" "));
        const drawn = [];
        for (let i = 0; i < rowList.count; i++) {
            const row = rowList.itemAtIndex(i);
            if (row)
                drawn.push(row.drawn());
        }
        return {
            drawn: rowList.visible ? drawn : [],
            // The list's own cursor and the rows at its top and bottom edges, so a check sees that a page landing below kept the cursor in view.
            listed: {
                current: rowList.currentIndex,
                top: rowList.indexAt(1, rowList.contentY + 1),
                bottom: rowList.indexAt(1, rowList.contentY + rowList.height - 2)
            },
            failed: failPane.visible ? {
                kicker: kickerText.text,
                head: failHead.text,
                fix: fixText.text,
                retry: retryKey.text + " " + retryWord.text,
                raw: rawBox.visible ? rawText.text : "",
                rawFont: rawText.fontInfo.family,
                rawSize: rawText.font.pixelSize,
                rawBelow: rawBox.y > fixText.y
            } : null,
            empty: emptyBlock.visible ? [emptyHead.text, [emptyKey.text, emptyRest.text].filter(t => t).join(" ")].filter(t => t) : [],
            look: {
                title: [labelText.text, viewName.text, fromText.text],
                viewFont: viewName.fontInfo.family,
                viewBold: viewName.font.weight >= Font.Bold,
                pills: [labelPill.color.a > 0, fromPill.color.a > 0],
                frameRadius: board.radius,
                fieldRadius: fieldBox.radius,
                ruleDashed: headRule.dashed,
                placeholder: placeholderText.text,
                hint: hintText.text,
                chips: Array.from({
                    length: chipList.count
                }, (_, i) => chipList.itemAt(i).text),
                chipsOn: Array.from({
                    length: chipList.count
                }, (_, i) => chipList.itemAt(i).chosen),
                results: [resultsHead.text, resultsCount.text],
                nowPlaying: [nowLine.text, repeatText.text],
                sidebar: sidebar,
                legend: Array.from({
                    length: legendList.count
                }, (_, i) => legendList.itemAt(i).drawn())
            }
        };
    }

    // Artboard's window is rounded as niri rounds its geometry; Paper and Blueprint are square.
    radius: plain ? 14 : 0
    color: c.surface ?? "white"
    clip: true

    Item {
        id: keyTarget
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text;
            if (t === "/")
                board.yt.focusField();
            else if (k === Qt.Key_Tab || k === Qt.Key_Backtab)
                board.yt.focusPane(board.yt.pane === "list" ? "sidebar" : "list");
            else if (t === "j" || k === Qt.Key_Down)
                board.yt.move(1);
            else if (t === "k" || k === Qt.Key_Up)
                board.yt.move(-1);
            else if ((t === "h" || k === Qt.Key_Left) && board.yt.pane === "list" && board.yt.view === "search")
                board.yt.moveType(-1);
            else if ((t === "l" || k === Qt.Key_Right) && board.yt.pane === "list" && board.yt.view === "search")
                board.yt.moveType(1);
            else if (k === Qt.Key_Escape)
                board.yt.back();
            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && board.yt.pane === "list" && board.failing)
                board.yt.retry();
            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && board.yt.pane === "list")
                board.yt.enter(board.yt.rows[board.yt.cursor]);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                board.yt.focusPane("list");
            else if (t === "s" && board.yt.pane === "list")
                board.yt.save(board.yt.rows[board.yt.cursor]);
            else if (t === "m" && board.yt.pane === "list")
                board.yt.queueItem(board.yt.rows[board.yt.cursor], "play");
            else if (t === "a" && board.yt.pane === "list")
                board.yt.queueItem(board.yt.rows[board.yt.cursor], "add");
            else if (k === Qt.Key_Space)
                board.yt.queueCommand(Q.pauseLine(board.yt.queue));
            else if (t === "r")
                board.yt.queueCommand(Q.repeatLine(board.yt.queue));
            else
                return;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The title strip: the App's label, the view's name, and how it opened; Artboard pills the label in its accent and the note in grey.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: plain ? 52 : -1
            Layout.leftMargin: plain ? 18 : 14
            Layout.rightMargin: plain ? 18 : 14
            Layout.topMargin: plain ? 0 : 12
            Layout.bottomMargin: plain ? 0 : 12
            spacing: plain ? 12 : 10

            Rectangle {
                id: labelPill
                implicitWidth: labelText.implicitWidth + (plain ? 18 : 0)
                implicitHeight: labelText.implicitHeight + (plain ? 6 : 0)
                radius: 8
                color: plain ? look.tint.tint : "transparent"

                Text {
                    id: labelText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: look.title.label
                    color: (plain ? c.accent : c.muted) ?? "gray"
                    font.family: board.bodyFont
                    font.pixelSize: plain ? 12 : 10
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.letterSpacing: plain ? 0 : 1.4
                }
            }
            Text {
                id: viewName
                textFormat: Text.PlainText
                text: board.yt.playlist ? board.yt.playlist.name : look.title.view(board.yt.view)
                elide: Text.ElideRight
                Layout.maximumWidth: 600
                color: c.ink ?? "black"
                font.family: look.viewFont ?? ""
                font.pixelSize: look.viewSize
                font.weight: caps ? Font.Normal : Font.Bold
            }
            Item {
                Layout.fillWidth: true
            }
            Rectangle {
                id: fromPill
                implicitWidth: fromText.implicitWidth + (plain ? 18 : 0)
                implicitHeight: fromText.implicitHeight + (plain ? 6 : 0)
                radius: 8
                color: plain ? look.tint.tile : "transparent"

                Text {
                    id: fromText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: look.title.from
                    color: c.muted ?? "gray"
                    font.family: board.bodyFont
                    font.pixelSize: bracket ? 10 : 11
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.letterSpacing: bracket ? 1.4 : 0
                }
            }
        }

        Rule {
            id: headRule
            Layout.fillWidth: true
            dashed: look.ruleDashed
            color: board.ruleColor
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // The sidebar: the views with their icons and counts, then the Playlists, or the key that makes one while there are none.
            Rectangle {
                id: sidebarPane
                Layout.preferredWidth: 219
                Layout.fillHeight: true
                color: "transparent"

                FocusMark {
                    shown: board.yt.focusAt === "sidebar"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.topMargin: plain ? 4 : 8
                    spacing: 0

                    Text {
                        id: libraryLabel
                        visible: text !== ""
                        Layout.leftMargin: 12
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        textFormat: Text.PlainText
                        text: look.library
                        color: c.muted ?? "gray"
                        font.family: board.bodyFont
                        font.pixelSize: 10
                        font.letterSpacing: 1.4
                    }

                    Repeater {
                        id: placeList
                        model: look.places.map(p => ({
                                    key: p.view,
                                    name: p.name,
                                    count: p.view === "saved" ? String(board.yt.savedCount) : p.view === "history" ? String(board.yt.historyCount) : ""
                                }))
                        delegate: sideRow
                    }

                    Text {
                        id: playlistsLabel
                        Layout.leftMargin: plain ? 10 : 12
                        Layout.topMargin: plain ? 12 : 12
                        Layout.bottomMargin: plain ? 2 : 6
                        textFormat: Text.PlainText
                        text: look.playlists
                        color: c.muted ?? "gray"
                        font.family: board.bodyFont
                        font.pixelSize: plain ? 11 : 10
                        font.letterSpacing: plain ? 0.66 : 1.4
                    }

                    // Each Playlist with its count, oldest first; its key is pl:<id>.
                    Repeater {
                        id: listList
                        model: board.yt.lists.map(l => ({
                                    key: "pl:" + l.id,
                                    name: l.name,
                                    count: String(l.count)
                                }))
                        delegate: sideRow
                    }

                    // A view or a Playlist in the sidebar: its icon, its name on one line, and its count.
                    Component {
                        id: sideRow

                        Rectangle {
                            id: place
                            required property var modelData
                            readonly property bool chosen: board.yt.sideKey === modelData.key
                            readonly property string countText: modelData.count

                            function drawn() {
                                return [placeName.text, placeCount.text].filter(t => t).join(" ");
                            }

                            Layout.fillWidth: true
                            implicitHeight: plain ? 38 : 34
                            radius: plain ? 10 : 0
                            color: !chosen || bracket ? "transparent" : plain ? look.tint.tint : look.tint.chosen
                            border.width: chosen && bracket ? 1 : 0
                            border.color: c.accent ?? "cyan"

                            // Blueprint fills the chosen view with its accent at a tenth.
                            Rectangle {
                                visible: place.chosen && bracket
                                anchors.fill: parent
                                color: c.accent ?? "cyan"
                                opacity: 0.1
                            }
                            // Paper marks the chosen view with a 2 px ink bar at its left.
                            Rectangle {
                                visible: place.chosen && caps
                                width: 2
                                height: parent.height
                                color: c.ink ?? "black"
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Rectangle {
                                    implicitWidth: plain ? 28 : 16
                                    implicitHeight: plain ? 28 : 16
                                    radius: 9
                                    color: !plain ? "transparent" : place.chosen ? c.surface ?? "white" : look.tint.tile

                                    FilesIcon {
                                        anchors.centerIn: parent
                                        path: ({
                                                search: "M7 2.5a4.5 4.5 0 1 0 0 9a4.5 4.5 0 1 0 0-9 M10.3 10.3L14 14",
                                                saved: "M4.5 2.5h7v11L8 10.8l-3.5 2.7z",
                                                history: "M8 2.5a5.5 5.5 0 1 0 0 11a5.5 5.5 0 1 0 0-11 M8 5v3.2l2 1.3"
                                            })[place.modelData.key] ?? "M3 4.5h10 M3 8h10 M3 11.5h6"
                                        color: (place.chosen ? (plain ? look.tint.deep : bracket ? c.accent : c.ink) : plain ? c.ink : c.muted) ?? "gray"
                                    }
                                }
                                Text {
                                    id: placeName
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: place.modelData.name
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    color: (place.chosen ? (plain ? look.tint.deep : bracket ? c.accent : c.ink) : plain ? c.ink : c.muted) ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 13
                                    font.weight: !place.chosen ? Font.Normal : bracket ? Font.Bold : Font.Medium
                                }
                                Text {
                                    id: placeCount
                                    textFormat: Text.PlainText
                                    text: place.countText
                                    color: (place.chosen && plain ? look.tint.deep : place.chosen && bracket ? c.accent : c.muted) ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 11
                                    font.letterSpacing: bracket ? 0.66 : 0
                                }
                            }
                        }
                    }

                    // n makes one, while there is none: Paper's italic serif, Artboard's key chip, Blueprint's plain line.
                    Row {
                        id: noneLine
                        visible: board.yt.lists.length === 0
                        Layout.leftMargin: 10
                        Layout.topMargin: 8
                        spacing: plain ? 8 : 0

                        Rectangle {
                            visible: plain
                            implicitWidth: noneKey.implicitWidth + 14
                            implicitHeight: noneKey.implicitHeight + 6
                            radius: 6
                            color: look.tint.tile ?? "transparent"

                            Text {
                                id: noneKey
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: plain ? look.noPlaylists.split(" ")[0] : ""
                                color: c.ink ?? "black"
                                font.family: board.bodyFont
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }
                        Text {
                            id: noneRest
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: plain ? look.noPlaylists.split(" ").slice(1).join(" ") : look.noPlaylists
                            color: c.muted ?? "gray"
                            font.family: caps ? look.viewFont ?? "" : board.bodyFont
                            font.pixelSize: caps ? 17 : 12
                            font.italic: caps
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            VRule {
                Layout.fillHeight: true
                dashed: look.ruleDashed
                color: board.ruleColor
            }

            // The list pane: on Search the field, the type chips and the results; on the other views their name and their rows or empty text.
            Item {
                id: listPane
                Layout.fillWidth: true
                Layout.fillHeight: true

                FocusMark {
                    shown: board.yt.focusAt !== "sidebar"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: bracket ? 8 : 18
                    anchors.rightMargin: bracket ? 8 : 18
                    anchors.topMargin: bracket ? 8 : 0
                    spacing: 0

                    // The field: Paper's ruled box, Artboard's filled pill, Blueprint's box in its line colour.
                    Rectangle {
                        id: fieldBox
                        visible: board.yt.view === "search"
                        Layout.fillWidth: true
                        Layout.topMargin: plain ? 12 : bracket ? 6 : 14
                        Layout.leftMargin: bracket ? 4 : 0
                        Layout.rightMargin: bracket ? 4 : 0
                        implicitHeight: plain ? 44 : 40
                        radius: look.fieldRadius
                        color: plain ? look.tint.field : "transparent"
                        border.width: plain ? 0 : 1
                        border.color: (bracket ? c.line : c.muted) ?? "gray"

                        FilesIcon {
                            id: searchIcon
                            anchors.left: parent.left
                            anchors.leftMargin: plain ? 16 : 14
                            anchors.verticalCenter: parent.verticalCenter
                            path: "M11.5 7A4.5 4.5 0 1 1 2.5 7A4.5 4.5 0 1 1 11.5 7M10.5 10.5L14 14"
                            stroke: 1.4
                            color: (plain ? c.muted : bracket ? c.accent : c.ink) ?? "black"
                        }
                        TextInput {
                            id: field
                            anchors.left: searchIcon.right
                            anchors.leftMargin: 12
                            anchors.right: hint.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            color: c.ink ?? "black"
                            selectionColor: c.accent ?? "red"
                            selectedTextColor: c.surface ?? "white"
                            font.family: board.bodyFont
                            font.pixelSize: caps ? 15 : 14
                            // Esc leaves the field for the list; Enter searches.
                            Keys.onEscapePressed: board.yt.focusPane("list")
                            onAccepted: board.yt.search()

                            Text {
                                id: placeholderText
                                anchors.fill: parent
                                visible: field.text === ""
                                textFormat: Text.PlainText
                                text: look.placeholder
                                color: c.muted ?? "gray"
                                font: field.font
                            }
                        }
                        Rectangle {
                            id: hint
                            anchors.right: parent.right
                            anchors.rightMargin: plain ? 16 : 14
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: hintText.implicitWidth + (plain ? 14 : 0)
                            implicitHeight: hintText.implicitHeight + (plain ? 4 : 0)
                            radius: 6
                            color: plain ? c.surface ?? "white" : "transparent"

                            Text {
                                id: hintText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: look.hint
                                color: c.muted ?? "gray"
                                font.family: board.bodyFont
                                font.pixelSize: bracket ? 10 : 11
                                font.weight: plain ? Font.Medium : Font.Normal
                                font.letterSpacing: bracket ? 1.4 : 0
                            }
                        }
                    }

                    // The type filter: the chip of the type Enter searches for is on, and h and l move it.
                    RowLayout {
                        visible: board.yt.view === "search"
                        Layout.topMargin: bracket ? 6 : 10
                        Layout.leftMargin: bracket ? 4 : 0
                        spacing: 8

                        Text {
                            visible: text !== ""
                            Layout.rightMargin: 6
                            textFormat: Text.PlainText
                            text: look.typeLabel
                            color: c.muted ?? "gray"
                            font.family: board.bodyFont
                            font.pixelSize: 10
                            font.letterSpacing: 1.4
                        }
                        Rectangle {
                            implicitWidth: chipRow.implicitWidth + (plain ? 6 : 0)
                            implicitHeight: chipRow.implicitHeight + (plain ? 6 : 0)
                            radius: 11
                            color: plain ? look.tint.tile : "transparent"

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: plain ? 2 : 8

                                Repeater {
                                    id: chipList
                                    model: look.chips

                                    Rectangle {
                                        id: chip
                                        required property string modelData
                                        required property int index
                                        readonly property bool chosen: index === board.yt.types.indexOf(board.yt.type)
                                        readonly property string text: chipText.text
                                        implicitWidth: chipText.implicitWidth + (bracket ? 20 : 24)
                                        implicitHeight: chipText.implicitHeight + 8
                                        radius: plain ? 8 : 0
                                        color: !chosen ? "transparent" : plain ? c.surface ?? "white" : bracket ? c.accent ?? "cyan" : c.ink ?? "black"
                                        border.width: plain ? 0 : 1
                                        border.color: (chosen ? (bracket ? c.accent : c.ink) : bracket ? c.line : c.muted) ?? "gray"

                                        Text {
                                            id: chipText
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: chip.modelData
                                            color: (chip.chosen ? (plain ? look.tint.deep : c.surface) : c.muted) ?? "gray"
                                            font.family: board.bodyFont
                                            font.pixelSize: plain ? 12 : 11
                                            font.weight: chip.chosen && plain ? Font.Medium : chip.chosen && bracket ? Font.Bold : Font.Normal
                                            font.letterSpacing: bracket ? 1.54 : 0
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The list's head: RESULTS and their count on Search, the view's name elsewhere; Paper's empty views draw none, and only Blueprint heads a failed search, with no count.
                    RowLayout {
                        visible: (board.yt.view === "search" || board.yt.playlist !== null || !caps) && (!board.failing || bracket)
                        Layout.fillWidth: true
                        Layout.topMargin: plain ? 8 : 10
                        Layout.preferredHeight: 26
                        Layout.leftMargin: caps ? 0 : 12
                        Layout.rightMargin: caps ? 0 : 12
                        spacing: 6

                        Text {
                            visible: bracket
                            textFormat: Text.PlainText
                            text: "◆"
                            color: c.accent ?? "cyan"
                            font.family: board.bodyFont
                            font.pixelSize: 11
                        }
                        Text {
                            id: resultsHead
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            // An opened playlist or channel, or a Playlist, heads its rows with its own name; a Playlist's is Paper's serif, Artboard's bold, Blueprint's as typed.
                            text: board.yt.view === "search" ? (board.yt.opened ? board.yt.opened.title : look.results) : board.yt.playlist ? board.yt.playlist.name : bracket ? look.title.view(board.yt.view).toUpperCase() : look.title.view(board.yt.view)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: (board.yt.playlist && !bracket || plain && board.yt.view !== "search" ? c.ink : c.muted) ?? "gray"
                            font.family: board.yt.playlist && caps ? look.viewFont ?? "" : board.bodyFont
                            font.pixelSize: board.yt.playlist && caps ? 18 : plain && board.yt.view !== "search" ? 16 : caps ? 10 : 11
                            font.weight: plain && board.yt.view !== "search" ? Font.Bold : Font.Normal
                            font.letterSpacing: plain || board.yt.playlist && caps ? 0 : bracket ? 1.54 : 1.4
                        }
                        Text {
                            id: resultsCount
                            textFormat: Text.PlainText
                            text: board.failing ? "—" : board.yt.playlist ? YT.count(board.yt.playlist.count) + " · " + YT.span(board.yt.playlist.secs) : plain && board.yt.view !== "search" ? board.yt.rows.length + " videos" : board.yt.listCount
                            color: c.muted ?? "gray"
                            font.family: board.bodyFont
                            font.pixelSize: caps ? 10 : 11
                            font.letterSpacing: plain ? 0 : bracket ? 1.54 : 1.4
                        }
                    }
                    Rule {
                        visible: !plain && (board.yt.view === "search" || board.yt.playlist !== null || !caps) && (!board.failing || bracket)
                        Layout.fillWidth: true
                        dashed: look.ruleDashed
                        color: (caps ? look.tint.rule : c.line) ?? "gray"
                    }

                    // The rows the list draws; a later search fills them.
                    ListView {
                        id: rowList
                        visible: !emptyBlock.visible && !board.failing
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        interactive: false
                        // A page's 20 rows stay made below the fold, so j shows a row whose thumbnail has already decoded.
                        cacheBuffer: 20 * 55
                        model: board.yt.rows
                        currentIndex: board.yt.cursor
                        // A new model resets the view to its first row, so a page landing below would take the cursor's row out of view; the cursor's binding comes back with it.
                        onCountChanged: currentIndex = Qt.binding(() => board.yt.cursor)

                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool lit: index === board.yt.cursor && board.yt.focusAt === "list"
                            // The channel and duration on the lit row: Paper's light ink, Blueprint's dark surface, Artboard's grey as on any row.
                            readonly property color litMuted: (caps ? look.tint.onInk : plain ? c.muted : c.surface) ?? "gray"

                            function drawn() {
                                return {
                                    id: rowItem.modelData.id,
                                    number: numberText.text,
                                    title: titleText.text,
                                    titleLines: titleText.lineCount,
                                    titleElided: titleText.truncated,
                                    channel: channelText.text,
                                    channelElided: channelText.truncated,
                                    duration: durationText.text,
                                    thumb: picture.drawn()
                                };
                            }
                            width: ListView.view.width
                            height: plain ? 54 : bracket ? 55 : 52
                            radius: look.rowRadius
                            color: !lit ? "transparent" : plain ? look.tint.tint : bracket ? c.accent ?? "cyan" : c.ink ?? "black"
                            // Artboard outlines the lit row in its accent.
                            border.width: lit && plain ? 1.5 : 0
                            border.color: c.accent ?? "blue"

                            // Paper marks the lit row with a 3 px accent bar at its left.
                            Rectangle {
                                visible: rowItem.lit && caps
                                width: 3
                                height: parent.height
                                color: c.accent ?? "red"
                            }

                            // The boards' columns: the thumbnail, the title over the channel, the download mark's slot, the duration, and Paper's 16 px end.
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 14

                                // A Playlist numbers its rows in its own order.
                                Text {
                                    id: numberText
                                    visible: board.yt.playlist !== null
                                    Layout.preferredWidth: plain ? 22 : 24
                                    horizontalAlignment: plain ? Text.AlignHCenter : Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: visible ? String(rowItem.index + 1) : ""
                                    color: rowItem.lit ? rowItem.litMuted : c.muted ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 12
                                }
                                YouTubeThumb {
                                    id: picture
                                    implicitWidth: caps ? 72 : 80
                                    implicitHeight: caps ? 40 : 45
                                    source: board.yt.thumbSource(rowItem.modelData.thumb)
                                    kind: caps ? "hatched" : plain ? "tile" : "crossed"
                                    radius: plain ? 8 : 0
                                    fill: (caps ? c.surface : plain ? look.tint.thumb : "transparent") ?? "transparent"
                                    stroke: (caps ? look.tint.rule : bracket && rowItem.lit ? c.surface : c.line) ?? "gray"
                                    edge: (caps ? c.muted : bracket && rowItem.lit ? c.surface : c.line) ?? "gray"
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: caps ? 3 : 4

                                    Text {
                                        id: titleText
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: rowItem.modelData.title
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: (rowItem.lit ? (plain ? look.tint.deep : c.surface) : c.ink) ?? "black"
                                        font.family: board.bodyFont
                                        font.pixelSize: plain ? 14 : 13
                                        font.weight: plain && !rowItem.lit ? Font.Normal : bracket && rowItem.lit ? Font.Bold : Font.Medium
                                    }
                                    Text {
                                        id: channelText
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: rowItem.modelData.channel
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: rowItem.lit ? rowItem.litMuted : c.muted ?? "gray"
                                        font.family: board.bodyFont
                                        font.pixelSize: 11
                                        font.letterSpacing: bracket ? 0.66 : 0
                                    }
                                }
                                Item {
                                    visible: !caps
                                    implicitWidth: plain ? 22 : 16
                                }
                                Text {
                                    id: durationText
                                    // A playlist's count may run wider than a duration, 1,234 videos.
                                    Layout.preferredWidth: Math.max(bracket ? 76 : 64, implicitWidth)
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: rowItem.modelData.duration
                                    color: rowItem.lit ? rowItem.litMuted : c.muted ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 12
                                    font.letterSpacing: bracket ? 0.72 : 0
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                                Item {
                                    visible: caps
                                    implicitWidth: 16
                                }
                            }
                        }
                    }

                    // A failed search, as the error boards draw it: Paper's ruled box under its kicker, Artboard's orange card, Blueprint's amber box; each holds the headline, the CLI's fix line, try again, and yt-dlp's raw line in small mono.
                    Item {
                        id: failPane
                        visible: board.failing
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: caps ? 22 : plain ? 14 : 4
                            anchors.leftMargin: bracket ? 4 : 0
                            anchors.rightMargin: bracket ? 4 : 0
                            implicitHeight: failColumn.implicitHeight + (caps ? 46 : 44)
                            radius: plain ? 14 : 0
                            color: plain ? look.tint.errFill : "transparent"
                            // Artboard outlines the block in its accent while the list has focus, as it outlines a lit row.
                            border.width: plain ? (board.yt.focusAt === "list" ? 1.5 : 0) : 1
                            border.color: (plain ? c.accent : caps ? c.ink : look.tint.warn) ?? "gray"

                            ColumnLayout {
                                id: failColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 24
                                anchors.topMargin: 22
                                spacing: bracket ? 14 : 12

                                Row {
                                    spacing: 12

                                    Rectangle {
                                        implicitWidth: plain ? 22 : 18
                                        implicitHeight: plain ? 22 : 18
                                        radius: plain ? 11 : 0
                                        color: (plain ? look.tint.errInk : caps ? c.ink : look.tint.warn) ?? "red"

                                        Text {
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: "!"
                                            color: c.surface ?? "white"
                                            font.family: board.bodyFont
                                            font.pixelSize: plain ? 13 : caps ? 11 : 10
                                            font.weight: Font.Bold
                                        }
                                    }
                                    Text {
                                        id: kickerText
                                        visible: caps
                                        anchors.verticalCenter: parent.verticalCenter
                                        textFormat: Text.PlainText
                                        text: board.yt.failed ? look.failed.kicker(board.yt.failed) : ""
                                        color: c.muted ?? "gray"
                                        font.family: board.bodyFont
                                        font.pixelSize: 10
                                        font.letterSpacing: 1.4
                                    }
                                    Text {
                                        visible: !caps
                                        anchors.verticalCenter: parent.verticalCenter
                                        textFormat: Text.PlainText
                                        text: failHead.text
                                        color: (plain ? look.tint.errInk : c.ink) ?? "black"
                                        font.family: board.bodyFont
                                        font.pixelSize: plain ? 18 : 16
                                        font.weight: Font.Bold
                                    }
                                }
                                // Paper sets the headline on its own line in its serif; the others draw it beside the mark above.
                                Text {
                                    id: failHead
                                    visible: caps
                                    textFormat: Text.PlainText
                                    text: look.failed.head
                                    color: c.ink ?? "black"
                                    font.family: look.viewFont ?? ""
                                    font.pixelSize: 25
                                }
                                Text {
                                    id: fixText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: board.yt.failed ? board.yt.failed.error : ""
                                    wrapMode: Text.Wrap
                                    color: (plain ? look.tint.errText : c.ink) ?? "black"
                                    font.family: board.bodyFont
                                    font.pixelSize: plain ? 14 : 13
                                }
                                Item {
                                    implicitWidth: retryBox.width + (caps ? 3 : 0)
                                    implicitHeight: retryBox.height + (caps ? 3 : 0)

                                    // Paper's button casts a hard 3 px accent shadow.
                                    Rectangle {
                                        visible: caps
                                        x: 3
                                        y: 3
                                        width: retryBox.width
                                        height: retryBox.height
                                        color: c.accent ?? "red"
                                    }
                                    Rectangle {
                                        id: retryBox
                                        width: retryRow.implicitWidth + (caps ? 28 : plain ? 18 : 0)
                                        height: retryRow.implicitHeight + (caps ? 16 : plain ? 6 : 0)
                                        radius: plain ? 6 : 0
                                        color: (caps ? c.ink : plain ? c.surface : "transparent") ?? "transparent"

                                        Row {
                                            id: retryRow
                                            anchors.centerIn: parent
                                            spacing: bracket ? 8 : 4

                                            Text {
                                                id: retryKey
                                                textFormat: Text.PlainText
                                                text: look.failed.key
                                                color: (caps ? c.surface : bracket ? c.accent : c.ink) ?? "black"
                                                font.family: board.bodyFont
                                                font.pixelSize: plain ? 12 : 13
                                                font.weight: Font.Bold
                                            }
                                            Text {
                                                id: retryWord
                                                textFormat: Text.PlainText
                                                text: look.failed.word
                                                color: (caps ? c.surface : c.ink) ?? "black"
                                                font.family: board.bodyFont
                                                font.pixelSize: plain ? 12 : 13
                                            }
                                        }
                                    }
                                }
                                // yt-dlp's own line: Paper's tinted strip with an accent edge, the others under a rule.
                                Rectangle {
                                    id: rawBox
                                    visible: rawText.text !== ""
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    implicitHeight: rawText.implicitHeight + (caps ? 20 : 12)
                                    color: caps ? look.tint.chosen : "transparent"

                                    Rectangle {
                                        visible: caps
                                        width: 2
                                        height: parent.height
                                        color: c.accent ?? "red"
                                    }
                                    Rule {
                                        visible: !caps
                                        width: parent.width
                                        dashed: bracket
                                        color: plain ? Qt.rgba(180 / 255, 56 / 255, 11 / 255, 0.22) : c.line ?? "gray"
                                    }
                                    Text {
                                        id: rawText
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: caps ? 12 : 0
                                        anchors.rightMargin: caps ? 12 : 0
                                        anchors.bottomMargin: caps ? 10 : 0
                                        textFormat: Text.PlainText
                                        text: board.yt.failed ? board.yt.failed.raw : ""
                                        wrapMode: Text.WrapAnywhere
                                        color: c.muted ?? "gray"
                                        font.family: board.yt.fonts.mono ?? ""
                                        font.pixelSize: 11
                                        font.letterSpacing: bracket ? 0.44 : 0
                                    }
                                }
                            }
                        }
                    }

                    // An empty view names the key that fills it: Paper's serif headline at the top, Artboard's and Blueprint's centred lines.
                    Item {
                        id: emptyBlock
                        visible: board.emptyText !== null && board.yt.rows.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            x: caps ? 22 : (parent.width - width) / 2
                            y: caps ? 64 : (parent.height - 80 - height) / 2
                            spacing: 10

                            Text {
                                id: emptyHead
                                visible: text !== ""
                                anchors.horizontalCenter: caps ? undefined : parent.horizontalCenter
                                textFormat: Text.PlainText
                                text: board.emptyText ? board.emptyText.head : ""
                                color: (bracket ? c.ink : c.muted) ?? "gray"
                                font.family: caps ? look.viewFont ?? "" : board.bodyFont
                                font.pixelSize: caps ? 25 : 16
                                font.weight: bracket ? Font.Medium : Font.Normal
                            }
                            Row {
                                anchors.horizontalCenter: caps ? undefined : parent.horizontalCenter
                                spacing: emptyKey.text ? 6 : 0

                                Rectangle {
                                    visible: emptyKey.text !== ""
                                    implicitWidth: emptyKey.implicitWidth + (plain ? 14 : 0)
                                    implicitHeight: emptyKey.implicitHeight + (plain ? 6 : 0)
                                    radius: 6
                                    color: plain ? look.tint.tile : "transparent"

                                    Text {
                                        id: emptyKey
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: board.emptyText ? board.emptyText.key : ""
                                        color: (bracket ? c.accent : c.ink) ?? "black"
                                        font.family: board.bodyFont
                                        font.pixelSize: 13
                                        font.weight: plain ? Font.Medium : Font.Bold
                                    }
                                }
                                Text {
                                    id: emptyRest
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: board.emptyText ? board.emptyText.rest : ""
                                    color: c.muted ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }
                }
            }
        }

        Rule {
            Layout.fillWidth: true
            dashed: look.ruleDashed
            color: board.ruleColor
        }

        // The now-playing line: empty while the Queue is stopped, with the repeat state at its right.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: plain ? 40 : bracket ? 34 : 38
            Layout.leftMargin: plain ? 18 : 16
            Layout.rightMargin: plain ? 18 : 16
            spacing: 10

            Text {
                id: nowLine
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: board.yt.nowPlaying
                elide: Text.ElideRight
                maximumLineCount: 1
                color: c.ink ?? "black"
                font.family: board.bodyFont
                font.pixelSize: 12
            }
            Text {
                id: repeatText
                textFormat: Text.PlainText
                text: look.repeat(board.yt.queue.loop)
                color: c.muted ?? "gray"
                font.family: board.bodyFont
                font.pixelSize: plain ? 12 : 11
                font.letterSpacing: bracket ? 1.54 : 0
            }
        }

        Rule {
            Layout.fillWidth: true
            dashed: look.ruleDashed
            color: board.ruleColor
        }

        // The keys, as each board strips them: Paper's tracked caps, Artboard's grey chips, Blueprint's bracketed accent keys.
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: plain ? 14 : 16
            Layout.rightMargin: plain ? 14 : 16
            Layout.topMargin: plain ? 10 : 11
            Layout.bottomMargin: plain ? 10 : 11
            spacing: plain ? 8 : 16

            Repeater {
                id: legendList
                model: look.legend(board.yt.view, board.failing)

                Rectangle {
                    required property var modelData

                    function drawn() {
                        return keyName.text + " " + keyWord.text;
                    }
                    implicitWidth: keyPair.implicitWidth + (plain ? 14 : 0)
                    implicitHeight: keyPair.implicitHeight + (plain ? 6 : 0)
                    radius: 6
                    color: plain ? look.tint.tile : "transparent"

                    Row {
                        id: keyPair
                        anchors.centerIn: parent
                        spacing: bracket ? 8 : 6

                        Text {
                            id: keyName
                            textFormat: Text.PlainText
                            text: modelData.key
                            color: (bracket ? c.accent : c.ink) ?? "black"
                            font.family: board.bodyFont
                            font.pixelSize: caps ? 10 : 11
                            font.weight: plain ? Font.Medium : Font.Bold
                            font.letterSpacing: caps ? 1 : bracket ? 1.54 : 0
                        }
                        Text {
                            id: keyWord
                            textFormat: Text.PlainText
                            text: modelData.word
                            color: c.muted ?? "gray"
                            font.family: board.bodyFont
                            font.pixelSize: caps ? 10 : 11
                            font.letterSpacing: caps ? 1 : bracket ? 1.54 : 0
                        }
                    }
                }
            }
        }
    }

    // Paper marks the pane with focus by a 2 px accent line along its top.
    component FocusMark: Rectangle {
        property bool shown: false
        visible: shown && board.caps
        width: parent.width
        height: 2
        color: board.c.accent ?? "red"
    }

    // A one-pixel rule, solid, or dashed as Blueprint draws its rules.
    component Rule: Item {
        property bool dashed: false
        property color color: "black"
        implicitHeight: 1

        Rectangle {
            anchors.fill: parent
            visible: !parent.dashed
            color: parent.color
        }
        Dashed {
            anchors.fill: parent
            visible: parent.dashed
            color: parent.color
        }
    }

    // The sidebar's edge: a one-pixel column, the dashed one a turned rule.
    component VRule: Item {
        id: vrule
        property bool dashed: false
        property color color: "black"
        implicitWidth: 1

        Rectangle {
            anchors.fill: parent
            visible: !vrule.dashed
            color: vrule.color
        }
        Dashed {
            visible: vrule.dashed
            x: 1
            width: vrule.height
            height: 1
            rotation: 90
            transformOrigin: Item.TopLeft
            color: vrule.color
        }
    }
}

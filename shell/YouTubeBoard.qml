import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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
    readonly property bool nameFocused: nameInput.activeFocus
    readonly property string queryText: field.text
    // Search draws no empty text but an opened channel's once it has answered with no uploads.
    readonly property var emptyText: yt.view !== "search" ? yt.look.empty(yt.view) : yt.opened && yt.opened.kind === "channel" && !yt.opened.list.loading && yt.failed === null ? yt.look.empty("channel") : null
    // A failed search's list is its error block.
    readonly property bool failing: yt.view === "search" && yt.failed !== null

    // The boards' download arrow into a tray, on Artboard's grey tile; on a lit row Paper's and Blueprint's take the row's light colour.
    component DownloadMark: Rectangle {
        id: mark
        property bool lit: false
        // A ShapePath is no Item and has no parent of its own, so it reads the stroke from here by id.
        readonly property color ink: lit && !board.plain ? board.c.surface ?? "white" : board.look.mark.stroke || (board.c.ink ?? "black")
        anchors.centerIn: parent
        width: board.look.mark.tile ? board.look.mark.tile.width : board.look.mark.size
        height: board.look.mark.tile ? board.look.mark.tile.height : board.look.mark.size
        radius: board.look.mark.tile ? board.look.mark.tile.radius : 0
        color: board.look.mark.tile ? board.look.mark.tile.color : "transparent"

        Shape {
            anchors.centerIn: parent
            width: board.look.mark.size
            height: board.look.mark.size
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: mark.ink
                strokeWidth: board.look.mark.width
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                scale: Qt.size(board.look.mark.size / 16, board.look.mark.size / 16)
                PathSvg {
                    path: "M8 2.5v8M4.8 7.5L8 10.7l3.2-3.2M3 13.5h10"
                }
            }
        }
    }

    function focusField() {
        field.forceActiveFocus();
    }

    function focusKeys() {
        keyTarget.forceActiveFocus();
    }

    // Scrolls a Flickable just enough that the band y to y + h of its content shows.
    function reveal(flick, y, h) {
        if (y < flick.contentY)
            flick.contentY = y;
        else if (y + h > flick.contentY + flick.height)
            flick.contentY = Math.max(0, y + h - flick.height);
    }

    function shown(flick, item) {
        return item.y >= flick.contentY - 0.5 && item.y + item.height <= flick.contentY + flick.height + 0.5;
    }

    function chosenPlace() {
        for (let i = 0; i < listList.count; i++) {
            const it = listList.itemAt(i);
            if (it && it.chosen)
                return it;
        }
        return null;
    }

    // The name field, else the chosen Playlist with any question under it, stays in view.
    function revealSidebar() {
        const it = nameBox.visible ? nameBox : chosenPlace();
        if (it)
            reveal(listScroll, it.y, it.height);
    }

    function revealPick() {
        const it = yt.picking ? pickRows.itemAt(yt.picking.cursor) : null;
        if (it)
            reveal(pickScroll, it.y, it.height);
    }

    // Each waits a turn for the layout to place what changed.
    Connections {
        target: board.yt
        function onSideKeyChanged() {
            Qt.callLater(board.revealSidebar);
        }
        function onNamingChanged() {
            Qt.callLater(board.revealSidebar);
        }
        function onConfirmingChanged() {
            Qt.callLater(board.revealSidebar);
        }
        function onListsChanged() {
            Qt.callLater(board.revealSidebar);
        }
        function onPickingChanged() {
            Qt.callLater(board.revealPick);
        }
    }

    function focusName(text) {
        nameInput.text = text;
        nameInput.forceActiveFocus();
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
        let asked = null;
        let askedLook = null;
        for (let i = 0; i < listList.count; i++) {
            asked = asked || listList.itemAt(i).asked();
            askedLook = askedLook || listList.itemAt(i).askedLook();
        }
        const drawn = [];
        for (let i = 0; i < rowList.count; i++) {
            const row = rowList.itemAtIndex(i);
            if (row)
                drawn.push(row.drawn());
        }
        const chosen = chosenPlace();
        return {
            // Whether the chosen Playlist and the name field sit wholly inside the sidebar's view.
            seen: {
                chosen: chosen ? shown(listScroll, chosen) : null,
                name: nameBox.visible ? shown(listScroll, nameBox) : null
            },
            nameField: nameBox.visible ? nameInput.text : null,
            confirm: asked,
            confirmLook: askedLook,
            dimmed: listColumn.opacity < 1,
            toast: toastBox.visible ? toastText.text : "",
            picker: picker.visible ? {
                title: [pickChip.text, pickTitle.text],
                rows: Array.from({
                    length: pickRows.count
                }, (_, i) => pickRows.itemAt(i).drawn()),
                fresh: [pickNewKey.text, pickNewWord.text].join(" "),
                lit: board.yt.picking.cursor,
                litSeen: board.yt.picking.cursor >= pickRows.count || shown(pickScroll, pickRows.itemAt(board.yt.picking.cursor)),
                bottom: picker.y + picker.height <= board.height,
                keys: Array.from({
                    length: pickKeys.count
                }, (_, i) => pickKeys.itemAt(i).text),
                below: picker.y >= board.pickAt - 1
            } : null,
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
                searchIcon: String(searchIcon.color),
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
            // While x asks, only y and Esc answer it.
            if (board.yt.confirming) {
                if (t === "y")
                    board.yt.deleteNow();
                else if (k === Qt.Key_Escape)
                    board.yt.confirming = false;
                event.accepted = true;
                return;
            }
            // While p's picker is open its own keys move, add, make a new Playlist or cancel.
            if (board.yt.picking) {
                if (t === "j" || k === Qt.Key_Down)
                    board.yt.movePick(1);
                else if (t === "k" || k === Qt.Key_Up)
                    board.yt.movePick(-1);
                else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                    board.yt.choosePick(false);
                else if (t === "n")
                    board.yt.choosePick(true);
                else if (k === Qt.Key_Escape)
                    board.yt.picking = null;
                event.accepted = true;
                return;
            }
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
            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && board.yt.pane === "list" && board.yt.rows[board.yt.cursor] && board.yt.downloadFailed(board.yt.rows[board.yt.cursor].id))
                board.yt.retryDownload(board.yt.rows[board.yt.cursor]);
            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && board.yt.pane === "list" && board.yt.playlist)
                board.yt.playPlaylist();
            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && board.yt.pane === "list")
                board.yt.enter(board.yt.rows[board.yt.cursor]);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                board.yt.focusPane("list");
            else if (t === "s" && board.yt.pane === "list")
                board.yt.save(board.yt.rows[board.yt.cursor]);
            else if ((t === "m" || t === "a" || t === "S") && board.yt.playlist)
                board.yt.queuePlaylist(t === "m" ? "play" : t === "a" ? "add" : "shuffle");
            else if (t === "m" && board.yt.pane === "list")
                board.yt.queueItem(board.yt.rows[board.yt.cursor], "play");
            else if (t === "a" && board.yt.pane === "list")
                board.yt.queueItem(board.yt.rows[board.yt.cursor], "add");
            else if (t === "d" || t === "D")
                board.yt.downloadKey(t === "d" ? "audio" : "video");
            else if (t === "p" && board.yt.pane === "list")
                board.yt.pick(board.yt.rows[board.yt.cursor]);
            else if (t === "x" && board.yt.pane === "list" && board.yt.playlist)
                board.yt.removeItem(board.yt.rows[board.yt.cursor]);
            else if ((t === "J" || t === "K") && board.yt.pane === "list" && board.yt.playlist)
                board.yt.moveItem(t === "J" ? 1 : -1);
            else if (t === "n" && board.yt.pane === "sidebar")
                board.yt.startName("new");
            else if (t === "e" && board.yt.pane === "sidebar" && board.yt.playlist)
                board.yt.startName(board.yt.playlistId);
            else if (t === "x" && board.yt.pane === "sidebar" && board.yt.playlist)
                board.yt.confirming = true;
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

                    // The Playlists scroll beneath PLAYLISTS once they outgrow the sidebar, keeping the chosen one, its question and the name field in view.
                    Flickable {
                        id: listScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        interactive: false
                        contentWidth: width
                        contentHeight: listsColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: listsColumn
                            width: listScroll.width
                            spacing: 0

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

                            // n and e name a Playlist here: Enter keeps a name with something in it, Esc leaves things as they were.
                            Rectangle {
                                id: nameBox
                                visible: board.yt.naming !== ""
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                implicitHeight: plain ? 36 : 32
                                radius: plain ? 10 : 0
                                color: plain ? look.tint.field : "transparent"
                                border.width: plain ? 1.5 : 1
                                border.color: (caps ? c.ink : c.accent) ?? "black"

                                TextInput {
                                    id: nameInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    color: c.ink ?? "black"
                                    selectionColor: c.accent ?? "red"
                                    selectedTextColor: c.surface ?? "white"
                                    font.family: board.bodyFont
                                    font.pixelSize: 13
                                    Keys.onEscapePressed: board.yt.cancelName()
                                    onAccepted: board.yt.commitName(text)

                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: nameInput.text === ""
                                        textFormat: Text.PlainText
                                        text: look.namePlaceholder
                                        color: c.muted ?? "gray"
                                        font: nameInput.font
                                    }
                                }
                            }
                        }
                    }

                    // A view or a Playlist in the sidebar: its icon, its name on one line, and its count.
                    Component {
                        id: sideRow

                        ColumnLayout {
                            id: place
                            required property var modelData
                            readonly property bool chosen: board.yt.sideKey === modelData.key
                            readonly property string countText: modelData.count

                            function drawn() {
                                return [placeName.text, freshMark.visible ? freshMark.text : "", placeCount.text].filter(t => t).join(" ");
                            }

                            // The question x asks under the row, or null while none is asked.
                            function asked() {
                                return confirmBox.visible ? [confirmText.text].concat(Array.from({
                                    length: confirmKeys.count
                                }, (_, i) => confirmKeys.itemAt(i).text)) : null;
                            }

                            // The question's frame and Blueprint's warning mark, as drawn.
                            function askedLook() {
                                return confirmBox.visible ? {
                                    border: String(confirmBox.border.color),
                                    cut: confirmText.truncated,
                                    mark: confirmMark.visible ? confirmMark.text : ""
                                } : null;
                            }

                            Layout.fillWidth: true
                            spacing: 0

                        Rectangle {
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
                                // The Playlist a snapshot just made, until it is opened.
                                Rectangle {
                                    visible: place.modelData.key === "pl:" + board.yt.freshId
                                    implicitWidth: freshMark.implicitWidth + 8
                                    implicitHeight: freshMark.implicitHeight + 2
                                    radius: plain ? 4 : 0
                                    color: plain ? look.tint.tint : "transparent"
                                    border.width: plain ? 0 : 1
                                    border.color: c.accent ?? "red"

                                    Text {
                                        id: freshMark
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: look.fresh
                                        color: c.accent ?? "red"
                                        font.family: board.bodyFont
                                        font.pixelSize: plain ? 10 : 9
                                        font.weight: bracket ? Font.Bold : Font.Medium
                                        font.letterSpacing: plain ? 0 : 1.26
                                    }
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

                        // x asks under the row: Paper's box ruled in its accent, Artboard's orange card, Blueprint's amber box with its mark.
                        Rectangle {
                            id: confirmBox
                            visible: place.chosen && board.yt.confirming
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 6
                            implicitHeight: confirmColumn.implicitHeight + 18
                            radius: plain ? 10 : 0
                            color: (plain ? look.tint.errFill : caps ? c.surface : "transparent") ?? "transparent"
                            border.width: plain ? 0 : 1
                            border.color: (bracket ? look.tint.warn : c.accent) ?? "red"

                            Column {
                                id: confirmColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 9
                                spacing: 8

                                Row {
                                    spacing: 6

                                    // Blueprint warns with an amber ! before the question.
                                    Text {
                                        id: confirmMark
                                        visible: bracket
                                        textFormat: Text.PlainText
                                        text: "!"
                                        color: look.tint.warn ?? "orange"
                                        font.family: board.bodyFont
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        id: confirmText
                                        width: confirmColumn.width - (confirmMark.visible ? confirmMark.implicitWidth + 6 : 0)
                                        textFormat: Text.PlainText
                                        text: board.yt.playlist ? look.confirm.question(board.yt.playlist.name, board.yt.playlist.count) : ""
                                        // The name is cut already, so the question wraps, anywhere a long word needs, and is never elided before its count.
                                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                        color: (plain ? look.tint.errInk : c.ink) ?? "black"
                                        font.family: board.bodyFont
                                        font.pixelSize: bracket ? 12 : 11
                                        font.weight: plain ? Font.Bold : Font.Normal
                                    }
                                }
                                Row {
                                    spacing: plain ? 6 : 14

                                    Repeater {
                                        id: confirmKeys
                                        model: look.confirm.keys

                                        Rectangle {
                                            required property var modelData
                                            required property int index
                                            readonly property string text: modelData.key + " " + modelData.word
                                            implicitWidth: confirmRow.implicitWidth + (plain ? 14 : 0)
                                            implicitHeight: confirmRow.implicitHeight + (plain ? 6 : 0)
                                            radius: 6
                                            color: plain ? c.surface ?? "white" : "transparent"

                                            Row {
                                                id: confirmRow
                                                anchors.centerIn: parent
                                                spacing: 5

                                                Text {
                                                    textFormat: Text.PlainText
                                                    text: modelData.key
                                                    color: (plain ? look.tint.errInk : bracket || index === 0 ? c.accent : c.ink) ?? "black"
                                                    font.family: board.bodyFont
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: bracket ? 1.54 : 0
                                                }
                                                Text {
                                                    textFormat: Text.PlainText
                                                    text: modelData.word
                                                    color: (plain ? look.tint.errInk : c.ink) ?? "black"
                                                    font.family: board.bodyFont
                                                    font.pixelSize: 11
                                                    font.letterSpacing: bracket ? 1.54 : 0
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
                    id: listColumn
                    anchors.fill: parent
                    // The list beside a delete question dims until it is answered.
                    opacity: board.yt.confirming || board.yt.picking ? (plain ? 0.45 : 0.4) : 1
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
                            text: board.failing ? "—" : board.yt.snapshot && board.yt.view === "search" ? YT.readingText(board.yt.snapshot) : board.yt.playlist ? YT.count(board.yt.playlist.count) + " · " + YT.span(board.yt.playlist.secs) : plain && board.yt.view !== "search" ? board.yt.rows.length + " videos" : board.yt.listCount
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
                            // A file on disk for this video, and its last download's failure, from the App's download index.
                            readonly property bool saved: rowItem.modelData.kind === "video" && board.yt.hasFile(rowItem.modelData.id)
                            readonly property var failure: rowItem.modelData.kind === "video" ? board.yt.downloadFailed(rowItem.modelData.id) : null

                            function drawn() {
                                return {
                                    id: rowItem.modelData.id,
                                    number: numberText.text,
                                    title: titleText.text,
                                    titleLines: titleText.lineCount,
                                    titleElided: titleText.truncated,
                                    dimmed: rowItem.opacity < 1,
                                    channel: channelText.text,
                                    channelElided: channelText.truncated,
                                    channelColor: String(channelText.color),
                                    mark: rowItem.saved,
                                    markInk: String((look.mark.at === "end" ? endMark : beforeMark).ink),
                                    duration: durationText.text,
                                    thumb: picture.drawn()
                                };
                            }
                            width: ListView.view.width
                            height: plain ? 54 : bracket ? 55 : 52
                            opacity: modelData.unavailable && !lit ? 0.6 : 1
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
                                        // A video gone from YouTube stays in its Playlist, marked, and is skipped.
                                        text: rowItem.modelData.unavailable ? look.unavailable(rowItem.modelData.unavailable) : rowItem.modelData.title
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
                                        text: rowItem.failure ? look.retry(rowItem.failure.reason) : rowItem.modelData.channel
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: rowItem.lit ? rowItem.litMuted : rowItem.failure ? look.retryColor : c.muted ?? "gray"
                                        font.family: board.bodyFont
                                        font.pixelSize: 11
                                        font.letterSpacing: bracket ? 0.66 : 0
                                    }
                                }
                                Item {
                                    visible: !caps
                                    implicitWidth: plain ? 22 : 16
                                    implicitHeight: 20

                                    DownloadMark {
                                        id: beforeMark
                                        visible: rowItem.saved && look.mark.at === "before"
                                        lit: rowItem.lit
                                    }
                                }
                                Text {
                                    id: durationText
                                    // A playlist's count may run wider than a duration, 1,234 videos.
                                    Layout.preferredWidth: Math.max(bracket ? 76 : 64, implicitWidth)
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: rowItem.modelData.unavailable ? "—" : rowItem.modelData.duration
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
                                    implicitHeight: 16

                                    DownloadMark {
                                        id: endMark
                                        visible: rowItem.saved && look.mark.at === "end"
                                        lit: rowItem.lit
                                    }
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
                model: look.legend(board.yt.view, board.failing, board.yt.focusAt, board.yt.opened ? board.yt.opened.kind : "")

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

    // A snapshot's toast above the now-playing line: Paper's ink box with its hard accent shadow, Artboard's white card, Blueprint's box in its accent.
    Rectangle {
        id: toastBox
        visible: board.yt.toast !== ""
        anchors.right: parent.right
        anchors.rightMargin: 22
        y: board.height - height - 104
        width: toastRow.implicitWidth + 30
        height: toastRow.implicitHeight + 20
        radius: plain ? 12 : 0
        color: (caps ? c.ink : c.surface) ?? "black"
        border.width: bracket ? 1 : plain ? 1 : 0
        border.color: (bracket ? c.accent : c.line) ?? "gray"

        Rectangle {
            visible: caps
            z: -1
            x: 3
            y: 3
            width: parent.width
            height: parent.height
            color: c.accent ?? "red"
        }

        Row {
            id: toastRow
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: caps ? "■" : "✓"
                color: c.accent ?? "red"
                font.family: board.bodyFont
                font.pixelSize: caps ? 9 : 12
            }
            Text {
                id: toastText
                textFormat: Text.PlainText
                text: board.yt.toast
                color: (caps ? c.surface : c.ink) ?? "black"
                font.family: board.bodyFont
                font.pixelSize: plain ? 13 : 12
            }
        }
    }

    // Where the picker's top goes: under the cursor's row, or above the window's foot when the row is low.
    readonly property real pickAt: {
        const row = yt.picking && rowList.currentItem;
        return row ? row.mapToItem(board, 0, row.height).y : 200;
    }

    // p's picker over the dimmed list, under the cursor's row: Paper's hard-shadowed box, Artboard's rounded card outlined in its accent, Blueprint's box in its accent.
    Rectangle {
        id: picker
        visible: board.yt.picking !== null
        x: sidebarPane.width + 120
        y: Math.max(60, Math.min(board.pickAt, board.height - height - 90))
        width: bracket ? 440 : 360
        height: pickColumn.implicitHeight
        radius: plain ? 14 : 0
        color: c.surface ?? "white"
        border.width: caps || plain ? 1.5 : 1
        border.color: (caps ? c.ink : c.accent) ?? "black"

        // Paper's 6 px hard shadow.
        Rectangle {
            visible: caps
            z: -1
            x: 6
            y: 6
            width: parent.width
            height: parent.height
            color: c.ink ?? "black"
        }

        Column {
            id: pickColumn
            width: parent.width

            Row {
                leftPadding: 16
                topPadding: 12
                bottomPadding: 12
                spacing: 12

                Rectangle {
                    implicitWidth: pickChip.implicitWidth + (bracket ? 0 : 14)
                    implicitHeight: pickChip.implicitHeight + (bracket ? 0 : 4)
                    radius: plain ? 8 : 0
                    color: (plain ? look.tint.tint : caps ? c.ink : "transparent") ?? "transparent"

                    Text {
                        id: pickChip
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: look.pick.chip
                        color: (plain || bracket ? c.accent : c.surface) ?? "black"
                        font.family: board.bodyFont
                        font.pixelSize: bracket || caps ? 10 : 12
                        font.weight: bracket ? Font.Bold : Font.Medium
                        font.letterSpacing: bracket || caps ? 1.4 : 0
                    }
                }
                Text {
                    id: pickTitle
                    width: picker.width - pickChip.implicitWidth - 60
                    textFormat: Text.PlainText
                    text: board.yt.picking ? look.pick.title(board.yt.picking.video.title) : ""
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: c.ink ?? "black"
                    font.family: caps ? look.viewFont ?? "" : board.bodyFont
                    font.pixelSize: caps ? 20 : bracket ? 12 : 14
                    font.weight: plain ? Font.Bold : Font.Normal
                }
            }
            Rule {
                width: parent.width
                dashed: look.ruleDashed
                color: (caps ? look.tint.rule : c.line) ?? "gray"
            }

            // One row per Playlist with its count; the one holding the video says so; past eight they scroll, the lit one kept in view.
            Flickable {
                id: pickScroll
                width: parent.width
                height: Math.min(pickList.implicitHeight, (plain ? 38 : 36) * 8)
                clip: true
                interactive: false
                contentWidth: width
                contentHeight: pickList.implicitHeight

                Column {
                    id: pickList
                    width: parent.width

                    Repeater {
                        id: pickRows
                        model: board.yt.picking ? board.yt.lists : []

                        Rectangle {
                            id: pickRow
                            required property var modelData
                            required property int index
                            readonly property bool lit: board.yt.picking !== null && index === board.yt.picking.cursor
                            readonly property bool holds: board.yt.picking !== null && board.yt.holds(modelData.id, board.yt.picking.video.id)

                            function drawn() {
                                return [pickName.text, pickCount.text].concat(pickHas.visible ? [pickHas.text] : []).join(" ");
                            }

                            x: plain ? 8 : 0
                            width: picker.width - (plain ? 16 : 0)
                            height: plain ? 38 : 36
                            radius: plain ? 10 : 0
                            color: !lit ? "transparent" : plain ? look.tint.tint : bracket ? c.accent ?? "cyan" : c.ink ?? "black"
                            border.width: lit && plain ? 1.5 : 0
                            border.color: c.accent ?? "blue"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: plain ? 12 : 16
                                anchors.rightMargin: plain ? 12 : 16
                                spacing: 10

                                Text {
                                    id: pickName
                                    Layout.maximumWidth: picker.width - 170
                                    textFormat: Text.PlainText
                                    text: pickRow.modelData.name
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    color: (pickRow.lit ? (plain ? look.tint.deep : c.surface) : pickRow.holds ? c.muted : c.ink) ?? "black"
                                    font.family: board.bodyFont
                                    font.pixelSize: plain ? 14 : 13
                                    font.weight: pickRow.lit && bracket ? Font.Bold : Font.Medium
                                }
                                Text {
                                    id: pickCount
                                    textFormat: Text.PlainText
                                    text: String(pickRow.modelData.count)
                                    color: (pickRow.lit && !plain ? c.surface : c.muted) ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 11
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Rectangle {
                                    visible: pickRow.holds
                                    implicitWidth: pickHas.implicitWidth + 12
                                    implicitHeight: pickHas.implicitHeight + 4
                                    radius: plain ? 6 : 0
                                    color: plain ? look.tint.tile : "transparent"
                                    border.width: plain ? 0 : 1
                                    border.color: (bracket ? c.line : c.muted) ?? "gray"

                                    Text {
                                        id: pickHas
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: look.pick.already
                                        color: c.muted ?? "gray"
                                        font.family: board.bodyFont
                                        font.pixelSize: plain ? 11 : 9
                                        font.letterSpacing: plain ? 0 : 1.26
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rule {
                width: parent.width
                dashed: look.ruleDashed
                color: (caps ? look.tint.rule : c.line) ?? "gray"
            }
            // The last place: n, or Enter on it, names a new Playlist for the video.
            Rectangle {
                readonly property bool lit: board.yt.picking !== null && board.yt.picking.cursor === board.yt.lists.length
                x: plain ? 8 : 0
                width: picker.width - (plain ? 16 : 0)
                height: plain ? 38 : 36
                radius: plain ? 10 : 0
                color: !lit ? "transparent" : plain ? look.tint.tint : bracket ? c.accent ?? "cyan" : c.ink ?? "black"
                border.width: lit && plain ? 1.5 : 0
                border.color: c.accent ?? "blue"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: plain ? 12 : 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        id: pickNewKey
                        textFormat: Text.PlainText
                        text: look.pick.newKey
                        color: (parent.parent.lit ? (plain ? look.tint.deep : c.surface) : bracket ? c.accent : c.ink) ?? "black"
                        font.family: board.bodyFont
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        id: pickNewWord
                        textFormat: Text.PlainText
                        text: look.pick.newWord
                        color: (parent.parent.lit ? (plain ? look.tint.deep : c.surface) : c.ink) ?? "black"
                        font.family: board.bodyFont
                        font.pixelSize: 13
                    }
                }
            }
            Rule {
                width: parent.width
                dashed: look.ruleDashed
                color: (caps ? c.ink : c.line) ?? "gray"
            }
            Flow {
                width: parent.width
                padding: 11
                leftPadding: 16
                spacing: 16

                Repeater {
                    id: pickKeys
                    model: look.pick.keys

                    Text {
                        required property var modelData
                        textFormat: Text.PlainText
                        text: modelData.key + " " + modelData.word
                        color: c.muted ?? "gray"
                        font.family: board.bodyFont
                        font.pixelSize: plain ? 11 : 10
                        font.letterSpacing: plain ? 0 : 1.4
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

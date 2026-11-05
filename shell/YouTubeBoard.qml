import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "lib/youtube-queue.mjs" as Q
import "lib/youtube.mjs" as YT
import "lib/dekho.mjs" as D

// The YouTube window as its board draws it: the title strip, the sidebar of views beside the list pane, the now-playing line and the key legend.
Rectangle {
    id: board

    required property var yt

    readonly property var c: yt.c
    readonly property var look: yt.look
    readonly property string bodyFont: yt.fonts.ui ?? ""
    readonly property color ruleColor: c.line ?? "gray"
    readonly property bool fieldFocused: field.activeFocus
    readonly property bool nameFocused: nameInput.activeFocus
    readonly property string queryText: field.text
    // Search draws no empty text but an opened channel's once it has answered with no uploads.
    readonly property var emptyText: yt.view !== "search" ? yt.look.empty(yt.view) : yt.opened && yt.opened.kind === "channel" && !yt.opened.list.loading && yt.failed === null ? yt.look.empty("channel") : null
    // A failed search's list is its error block.
    readonly property bool failing: yt.view === "search" && yt.failed !== null

    // The download arrow into a tray, on a grey tile.
    component DownloadMark: Rectangle {
        id: mark
        // A ShapePath is no Item and has no parent of its own, so it reads the stroke from here by id.
        readonly property color ink: board.look.mark.stroke || (board.c.ink ?? "black")
        anchors.centerIn: parent
        width: board.look.mark.tile.width
        height: board.look.mark.tile.height
        radius: board.look.mark.tile.radius
        color: board.look.mark.tile.color

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

    // Enter in the list, and a click on a row once the cursor is on it: a failed search asks again, a failed download downloads again, a Playlist plays, else the row plays or opens.
    function enterList() {
        const row = yt.rows[yt.cursor];
        if (failing)
            yt.retry();
        else if (row && yt.downloadFailed(row.id))
            yt.retryDownload(row);
        else if (yt.playlist)
            yt.playPlaylist();
        else
            yt.enter(row);
    }

    function focusName(text) {
        nameInput.text = text;
        nameInput.forceActiveFocus();
    }

    function state() {
        const sidebar = [];
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

    // The window is rounded as niri rounds its geometry.
    radius: 14
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
            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && board.yt.pane === "list")
                board.enterList();
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

        // The title strip: the App's label, the view's name, and how it opened; the label is pilled in the accent and the note in grey.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.topMargin: 0
            Layout.bottomMargin: 0
            spacing: 12

            Rectangle {
                id: labelPill
                implicitWidth: labelText.implicitWidth + 18
                implicitHeight: labelText.implicitHeight + 6
                radius: 8
                color: look.tint.tint

                Text {
                    id: labelText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: look.title.label
                    color: look.tint.word ?? "gray"
                    font.family: board.bodyFont
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.letterSpacing: 0
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
                font.weight: Font.Bold
            }
            Item {
                Layout.fillWidth: true
            }
            Rectangle {
                id: fromPill
                implicitWidth: fromText.implicitWidth + 18
                implicitHeight: fromText.implicitHeight + 6
                radius: 8
                color: look.tint.tile

                Text {
                    id: fromText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: look.title.from
                    color: c.muted ?? "gray"
                    font.family: board.bodyFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.letterSpacing: 0
                }
            }
        }

        Rule {
            Layout.fillWidth: true
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

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.topMargin: 4
                    spacing: 0

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
                        Layout.leftMargin: 10
                        Layout.topMargin: 12
                        Layout.bottomMargin: 2
                        textFormat: Text.PlainText
                        text: look.playlists
                        color: c.muted ?? "gray"
                        font.family: board.bodyFont
                        font.pixelSize: 11
                        font.letterSpacing: 0.66
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

                            // n makes one, while there is none: its key on a chip.
                            Row {
                                id: noneLine
                                visible: board.yt.lists.length === 0
                                Layout.leftMargin: 10
                                Layout.topMargin: 8
                                spacing: 8

                                Rectangle {
                                    implicitWidth: noneKey.implicitWidth + 14
                                    implicitHeight: noneKey.implicitHeight + 6
                                    radius: 6
                                    color: look.tint.tile ?? "transparent"

                                    Text {
                                        id: noneKey
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: look.noPlaylists.split(" ")[0]
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
                                    text: look.noPlaylists.split(" ").slice(1).join(" ")
                                    color: c.muted ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 12
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
                                implicitHeight: 36
                                radius: 10
                                color: look.tint.field
                                border.width: 1.5
                                border.color: c.accent ?? "black"

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

                            // The question's frame, as drawn.
                            function askedLook() {
                                return confirmBox.visible ? {
                                    border: String(confirmBox.border.color),
                                    cut: confirmText.truncated
                                } : null;
                            }

                            Layout.fillWidth: true
                            spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: 10
                            color: !chosen ? "transparent" : look.tint.tint

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Rectangle {
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: 9
                                    color: place.chosen ? c.surface ?? "white" : look.tint.tile

                                    FilesIcon {
                                        anchors.centerIn: parent
                                        path: ({
                                                search: "M7 2.5a4.5 4.5 0 1 0 0 9a4.5 4.5 0 1 0 0-9 M10.3 10.3L14 14",
                                                saved: "M4.5 2.5h7v11L8 10.8l-3.5 2.7z",
                                                history: "M8 2.5a5.5 5.5 0 1 0 0 11a5.5 5.5 0 1 0 0-11 M8 5v3.2l2 1.3"
                                            })[place.modelData.key] ?? "M3 4.5h10 M3 8h10 M3 11.5h6"
                                        color: (place.chosen ? look.tint.deep : c.ink) ?? "gray"
                                    }
                                }
                                Text {
                                    id: placeName
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: place.modelData.name
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    color: (place.chosen ? look.tint.deep : c.ink) ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 13
                                    font.weight: !place.chosen ? Font.Normal : Font.Medium
                                }
                                // The Playlist a snapshot just made, until it is opened.
                                Rectangle {
                                    visible: place.modelData.key === "pl:" + board.yt.freshId
                                    implicitWidth: freshMark.implicitWidth + 8
                                    implicitHeight: freshMark.implicitHeight + 2
                                    radius: 4
                                    color: look.tint.tint

                                    Text {
                                        id: freshMark
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: look.fresh
                                        color: c.accent ?? "red"
                                        font.family: board.bodyFont
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        font.letterSpacing: 0
                                    }
                                }
                                Text {
                                    id: placeCount
                                    textFormat: Text.PlainText
                                    text: place.countText
                                    color: (place.chosen ? look.tint.deep : c.muted) ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 11
                                    font.letterSpacing: 0
                                }
                            }
                        }

                        // x asks under the row, on an orange card.
                        Rectangle {
                            id: confirmBox
                            visible: place.chosen && board.yt.confirming
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 6
                            implicitHeight: confirmColumn.implicitHeight + 18
                            radius: 10
                            color: look.tint.errFill ?? "transparent"
                            border.width: 0
                            border.color: c.accent ?? "red"

                            Column {
                                id: confirmColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 9
                                spacing: 8

                                Row {
                                    spacing: 6

                                    Text {
                                        id: confirmText
                                        width: confirmColumn.width
                                        textFormat: Text.PlainText
                                        text: board.yt.playlist ? look.confirm.question(board.yt.playlist.name, board.yt.playlist.count) : ""
                                        // The name is cut already, so the question wraps, anywhere a long word needs, and is never elided before its count.
                                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                        color: look.tint.errInk ?? "black"
                                        font.family: board.bodyFont
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }
                                Row {
                                    spacing: 6

                                    Repeater {
                                        id: confirmKeys
                                        model: look.confirm.keys

                                        Rectangle {
                                            required property var modelData
                                            readonly property string text: modelData.key + " " + modelData.word
                                            implicitWidth: confirmRow.implicitWidth + 14
                                            implicitHeight: confirmRow.implicitHeight + 6
                                            radius: 6
                                            color: c.surface ?? "white"

                                            Row {
                                                id: confirmRow
                                                anchors.centerIn: parent
                                                spacing: 5

                                                Text {
                                                    textFormat: Text.PlainText
                                                    text: modelData.key
                                                    color: look.tint.errInk ?? "black"
                                                    font.family: board.bodyFont
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 0
                                                }
                                                Text {
                                                    textFormat: Text.PlainText
                                                    text: modelData.word
                                                    color: look.tint.errInk ?? "black"
                                                    font.family: board.bodyFont
                                                    font.pixelSize: 11
                                                    font.letterSpacing: 0
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
                color: board.ruleColor
            }

            // The list pane: on Search the field, the type chips and the results; on the other views their name and their rows or empty text.
            Item {
                id: listPane
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: listColumn
                    anchors.fill: parent
                    // The list beside a delete question dims until it is answered.
                    opacity: board.yt.confirming || board.yt.picking ? 0.45 : 1
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.topMargin: 0
                    spacing: 0

                    // The field: a filled pill.
                    Rectangle {
                        id: fieldBox
                        visible: board.yt.view === "search"
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        implicitHeight: 44
                        radius: look.fieldRadius
                        color: look.tint.field

                        FilesIcon {
                            id: searchIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            path: "M11.5 7A4.5 4.5 0 1 1 2.5 7A4.5 4.5 0 1 1 11.5 7M10.5 10.5L14 14"
                            stroke: 1.4
                            color: c.muted ?? "black"
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
                            font.pixelSize: 14
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
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: hintText.implicitWidth + 14
                            implicitHeight: hintText.implicitHeight + 4
                            radius: 6
                            color: c.surface ?? "white"

                            Text {
                                id: hintText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: look.hint
                                color: c.muted ?? "gray"
                                font.family: board.bodyFont
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.letterSpacing: 0
                            }
                        }
                    }

                    // The type filter: the chip of the type Enter searches for is on, and h and l move it.
                    RowLayout {
                        visible: board.yt.view === "search"
                        Layout.topMargin: 10
                        spacing: 8

                        Rectangle {
                            implicitWidth: chipRow.implicitWidth + 6
                            implicitHeight: chipRow.implicitHeight + 6
                            radius: 11
                            color: look.tint.tile

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 2

                                Repeater {
                                    id: chipList
                                    model: look.chips

                                    Rectangle {
                                        id: chip
                                        required property string modelData
                                        required property int index
                                        readonly property bool chosen: index === board.yt.types.indexOf(board.yt.type)
                                        readonly property string text: chipText.text
                                        implicitWidth: chipText.implicitWidth + 24
                                        implicitHeight: chipText.implicitHeight + 8
                                        radius: 8
                                        color: !chosen ? "transparent" : c.surface ?? "white"

                                        Text {
                                            id: chipText
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: chip.modelData
                                            color: (chip.chosen ? look.tint.deep : c.muted) ?? "gray"
                                            font.family: board.bodyFont
                                            font.pixelSize: 12
                                            font.weight: chip.chosen ? Font.Medium : Font.Normal
                                            font.letterSpacing: 0
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The list's head: Results and their count on Search, the view's name elsewhere; a failed search draws none.
                    RowLayout {
                        visible: !board.failing
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        Layout.preferredHeight: 26
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        spacing: 6

                        Text {
                            id: resultsHead
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            // An opened playlist or channel, or a Playlist, heads its rows with its own name.
                            text: board.yt.view === "search" ? (board.yt.opened ? board.yt.opened.title : look.results) : board.yt.playlist ? board.yt.playlist.name : look.title.view(board.yt.view)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: (board.yt.playlist || board.yt.view !== "search" ? c.ink : c.muted) ?? "gray"
                            font.family: board.bodyFont
                            font.pixelSize: board.yt.view !== "search" ? 16 : 11
                            font.weight: board.yt.view !== "search" ? Font.Bold : Font.Normal
                            font.letterSpacing: 0
                        }
                        Text {
                            id: resultsCount
                            textFormat: Text.PlainText
                            text: board.failing ? "—" : board.yt.snapshot && board.yt.view === "search" ? YT.readingText(board.yt.snapshot) : board.yt.playlist ? YT.count(board.yt.playlist.count) + " · " + YT.span(board.yt.playlist.secs) : board.yt.view !== "search" ? board.yt.rows.length + " videos" : board.yt.listCount
                            color: c.muted ?? "gray"
                            font.family: board.bodyFont
                            font.pixelSize: 11
                            font.letterSpacing: 0
                        }
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

                        // Under the rows, the wheel scrolls the list and leaves the cursor where it is; j or k brings the cursor's row back into view.
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: event => rowList.contentY = D.wheeled(rowList.contentY, event.angleDelta.y, rowList.contentHeight, rowList.height)
                        }

                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool lit: index === board.yt.cursor && board.yt.focusAt === "list"
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
                                    markInk: String(beforeMark.ink),
                                    duration: durationText.text,
                                    thumb: picture.drawn()
                                };
                            }
                            width: ListView.view.width
                            height: 54
                            opacity: modelData.unavailable && !lit ? 0.6 : 1
                            radius: look.rowRadius
                            color: !lit ? "transparent" : look.tint.tint
                            // The lit row is outlined in the accent.
                            border.width: lit ? 1.5 : 0
                            border.color: c.accent ?? "blue"

                            Click {
                                name: "yt-row:" + rowItem.index
                                onTapped: {
                                    board.yt.cursor = rowItem.index;
                                    board.yt.focusPane("list");
                                    board.enterList();
                                }
                            }

                            // The columns: the thumbnail, the title over the channel, the download mark's slot and the duration.
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 14

                                // A Playlist numbers its rows in its own order.
                                Text {
                                    id: numberText
                                    visible: board.yt.playlist !== null
                                    Layout.preferredWidth: 22
                                    horizontalAlignment: Text.AlignHCenter
                                    textFormat: Text.PlainText
                                    text: visible ? String(rowItem.index + 1) : ""
                                    color: c.muted ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 12
                                }
                                YouTubeThumb {
                                    id: picture
                                    implicitWidth: 80
                                    implicitHeight: 45
                                    source: board.yt.thumbSource(rowItem.modelData.thumb)
                                    radius: 8
                                    fill: look.tint.thumb ?? "transparent"
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        id: titleText
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        // A video gone from YouTube stays in its Playlist, marked, and is skipped.
                                        text: rowItem.modelData.unavailable ? look.unavailable(rowItem.modelData.unavailable) : rowItem.modelData.title
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: (rowItem.lit ? look.tint.deep : c.ink) ?? "black"
                                        font.family: board.bodyFont
                                        font.pixelSize: 14
                                        font.weight: !rowItem.lit ? Font.Normal : Font.Medium
                                    }
                                    Text {
                                        id: channelText
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: rowItem.failure ? look.retry(rowItem.failure.reason) : rowItem.modelData.channel
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: rowItem.lit ? c.muted ?? "gray" : rowItem.failure ? look.retryColor : c.muted ?? "gray"
                                        font.family: board.bodyFont
                                        font.pixelSize: 11
                                        font.letterSpacing: 0
                                    }
                                }
                                Item {
                                    implicitWidth: 22
                                    implicitHeight: 20

                                    DownloadMark {
                                        id: beforeMark
                                        visible: rowItem.saved
                                    }
                                }
                                Text {
                                    id: durationText
                                    // A playlist's count may run wider than a duration, 1,234 videos.
                                    Layout.preferredWidth: Math.max(64, implicitWidth)
                                    horizontalAlignment: Text.AlignRight
                                    textFormat: Text.PlainText
                                    text: rowItem.modelData.unavailable ? "—" : rowItem.modelData.duration
                                    color: c.muted ?? "gray"
                                    font.family: board.bodyFont
                                    font.pixelSize: 12
                                    font.letterSpacing: 0
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                            }
                        }
                    }

                    // A failed search draws an orange card: the headline, the CLI's fix line, try again, and yt-dlp's raw line in small mono.
                    Item {
                        id: failPane
                        visible: board.failing
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 14
                            implicitHeight: failColumn.implicitHeight + 44
                            radius: 14
                            color: look.tint.errFill
                            // The block is outlined in the accent while the list has focus, as a lit row is.
                            border.width: board.yt.focusAt === "list" ? 1.5 : 0
                            border.color: c.accent ?? "gray"

                            ColumnLayout {
                                id: failColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 24
                                anchors.topMargin: 22
                                spacing: 12

                                Row {
                                    spacing: 12

                                    Rectangle {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        radius: 11
                                        color: look.tint.errInk ?? "red"

                                        Text {
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: "!"
                                            color: c.surface ?? "white"
                                            font.family: board.bodyFont
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                        }
                                    }
                                    Text {
                                        id: failHead
                                        anchors.verticalCenter: parent.verticalCenter
                                        textFormat: Text.PlainText
                                        text: look.failed.head
                                        color: look.tint.errInk ?? "black"
                                        font.family: board.bodyFont
                                        font.pixelSize: 18
                                        font.weight: Font.Bold
                                    }
                                }
                                Text {
                                    id: fixText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: board.yt.failed ? board.yt.failed.error : ""
                                    wrapMode: Text.Wrap
                                    color: look.tint.errText ?? "black"
                                    font.family: board.bodyFont
                                    font.pixelSize: 14
                                }
                                Rectangle {
                                    id: retryBox
                                    implicitWidth: retryRow.implicitWidth + 18
                                    implicitHeight: retryRow.implicitHeight + 6
                                    radius: 6
                                    color: c.surface ?? "transparent"

                                    Row {
                                        id: retryRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            id: retryKey
                                            textFormat: Text.PlainText
                                            text: look.failed.key
                                            color: c.ink ?? "black"
                                            font.family: board.bodyFont
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            id: retryWord
                                            textFormat: Text.PlainText
                                            text: look.failed.word
                                            color: c.ink ?? "black"
                                            font.family: board.bodyFont
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                                // yt-dlp's own line, under a rule.
                                Rectangle {
                                    id: rawBox
                                    visible: rawText.text !== ""
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    implicitHeight: rawText.implicitHeight + 12
                                    color: "transparent"

                                    Rule {
                                        width: parent.width
                                        color: Qt.rgba(180 / 255, 56 / 255, 11 / 255, 0.22)
                                    }
                                    Text {
                                        id: rawText
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        textFormat: Text.PlainText
                                        text: board.yt.failed ? board.yt.failed.raw : ""
                                        wrapMode: Text.WrapAnywhere
                                        color: c.muted ?? "gray"
                                        font.family: board.yt.fonts.mono ?? ""
                                        font.pixelSize: 11
                                        font.letterSpacing: 0
                                    }
                                }
                            }
                        }
                    }

                    // An empty view names the key that fills it, in centred lines.
                    Item {
                        id: emptyBlock
                        visible: board.emptyText !== null && board.yt.rows.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            x: (parent.width - width) / 2
                            y: (parent.height - 80 - height) / 2
                            spacing: 10

                            Text {
                                id: emptyHead
                                visible: text !== ""
                                anchors.horizontalCenter: parent.horizontalCenter
                                textFormat: Text.PlainText
                                text: board.emptyText ? board.emptyText.head : ""
                                color: c.muted ?? "gray"
                                font.family: board.bodyFont
                                font.pixelSize: 16
                                font.weight: Font.Normal
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: emptyKey.text ? 6 : 0

                                Rectangle {
                                    visible: emptyKey.text !== ""
                                    implicitWidth: emptyKey.implicitWidth + 14
                                    implicitHeight: emptyKey.implicitHeight + 6
                                    radius: 6
                                    color: look.tint.tile

                                    Text {
                                        id: emptyKey
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: board.emptyText ? board.emptyText.key : ""
                                        color: c.ink ?? "black"
                                        font.family: board.bodyFont
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
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
            color: board.ruleColor
        }

        // The now-playing line: empty while the Queue is stopped, with the repeat state at its right.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            Layout.leftMargin: 18
            Layout.rightMargin: 18
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
                font.pixelSize: 12
                font.letterSpacing: 0
            }
        }

        Rule {
            Layout.fillWidth: true
            color: board.ruleColor
        }

        // The keys, each on a grey chip.
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 8

            Repeater {
                id: legendList
                model: look.legend(board.yt.view, board.failing, board.yt.focusAt, board.yt.opened ? board.yt.opened.kind : "")

                Rectangle {
                    required property var modelData

                    function drawn() {
                        return keyName.text + " " + keyWord.text;
                    }
                    implicitWidth: keyPair.implicitWidth + 14
                    implicitHeight: keyPair.implicitHeight + 6
                    radius: 6
                    color: look.tint.tile

                    Row {
                        id: keyPair
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            id: keyName
                            textFormat: Text.PlainText
                            text: modelData.key
                            color: c.ink ?? "black"
                            font.family: board.bodyFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 0
                        }
                        Text {
                            id: keyWord
                            textFormat: Text.PlainText
                            text: modelData.word
                            color: c.muted ?? "gray"
                            font.family: board.bodyFont
                            font.pixelSize: 11
                            font.letterSpacing: 0
                        }
                    }
                }
            }
        }
    }

    // A snapshot's toast above the now-playing line, on a white card.
    Rectangle {
        id: toastBox
        visible: board.yt.toast !== ""
        anchors.right: parent.right
        anchors.rightMargin: 22
        y: board.height - height - 104
        width: toastRow.implicitWidth + 30
        height: toastRow.implicitHeight + 20
        radius: 12
        color: c.surface ?? "black"
        border.width: 1
        border.color: c.line ?? "gray"

        Row {
            id: toastRow
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "✓"
                color: c.accent ?? "red"
                font.family: board.bodyFont
                font.pixelSize: 12
            }
            Text {
                id: toastText
                textFormat: Text.PlainText
                text: board.yt.toast
                color: c.ink ?? "black"
                font.family: board.bodyFont
                font.pixelSize: 13
            }
        }
    }

    // Where the picker's top goes: under the cursor's row, or above the window's foot when the row is low.
    readonly property real pickAt: {
        const row = yt.picking && rowList.currentItem;
        return row ? row.mapToItem(board, 0, row.height).y : 200;
    }

    // p's picker over the dimmed list, under the cursor's row: a rounded card outlined in the accent.
    Rectangle {
        id: picker
        visible: board.yt.picking !== null
        x: sidebarPane.width + 120
        y: Math.max(60, Math.min(board.pickAt, board.height - height - 90))
        width: 360
        height: pickColumn.implicitHeight
        radius: 14
        color: c.surface ?? "white"
        border.width: 1.5
        border.color: c.accent ?? "black"

        Column {
            id: pickColumn
            width: parent.width

            Row {
                leftPadding: 16
                topPadding: 12
                bottomPadding: 12
                spacing: 12

                Rectangle {
                    implicitWidth: pickChip.implicitWidth + 14
                    implicitHeight: pickChip.implicitHeight + 4
                    radius: 8
                    color: look.tint.tint ?? "transparent"

                    Text {
                        id: pickChip
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: look.pick.chip
                        color: c.accent ?? "black"
                        font.family: board.bodyFont
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        font.letterSpacing: 0
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
                    font.family: board.bodyFont
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }
            }
            Rule {
                width: parent.width
                color: c.line ?? "gray"
            }

            // One row per Playlist with its count; the one holding the video says so; past eight they scroll, the lit one kept in view.
            Flickable {
                id: pickScroll
                width: parent.width
                height: Math.min(pickList.implicitHeight, 38 * 8)
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

                            x: 8
                            width: picker.width - 16
                            height: 38
                            radius: 10
                            color: !lit ? "transparent" : look.tint.tint
                            border.width: lit ? 1.5 : 0
                            border.color: c.accent ?? "blue"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    id: pickName
                                    Layout.maximumWidth: picker.width - 170
                                    textFormat: Text.PlainText
                                    text: pickRow.modelData.name
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    color: (pickRow.lit ? look.tint.deep : pickRow.holds ? c.muted : c.ink) ?? "black"
                                    font.family: board.bodyFont
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }
                                Text {
                                    id: pickCount
                                    textFormat: Text.PlainText
                                    text: String(pickRow.modelData.count)
                                    color: c.muted ?? "gray"
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
                                    radius: 6
                                    color: look.tint.tile

                                    Text {
                                        id: pickHas
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: look.pick.already
                                        color: c.muted ?? "gray"
                                        font.family: board.bodyFont
                                        font.pixelSize: 11
                                        font.letterSpacing: 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rule {
                width: parent.width
                color: c.line ?? "gray"
            }
            // The last place: n, or Enter on it, names a new Playlist for the video.
            Rectangle {
                readonly property bool lit: board.yt.picking !== null && board.yt.picking.cursor === board.yt.lists.length
                x: 8
                width: picker.width - 16
                height: 38
                radius: 10
                color: !lit ? "transparent" : look.tint.tint
                border.width: lit ? 1.5 : 0
                border.color: c.accent ?? "blue"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        id: pickNewKey
                        textFormat: Text.PlainText
                        text: look.pick.newKey
                        color: (parent.parent.lit ? look.tint.deep : c.ink) ?? "black"
                        font.family: board.bodyFont
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        id: pickNewWord
                        textFormat: Text.PlainText
                        text: look.pick.newWord
                        color: (parent.parent.lit ? look.tint.deep : c.ink) ?? "black"
                        font.family: board.bodyFont
                        font.pixelSize: 13
                    }
                }
            }
            Rule {
                width: parent.width
                color: c.line ?? "gray"
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
                        font.pixelSize: 11
                        font.letterSpacing: 0
                    }
                }
            }
        }
    }

    // A one-pixel rule.
    component Rule: Rectangle {
        implicitHeight: 1
    }

    // The sidebar's edge: a one-pixel column.
    component VRule: Rectangle {
        implicitWidth: 1
    }
}

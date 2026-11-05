import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib/deen.mjs" as D
import "lib/deen-hadith.mjs" as H

// Deen's Hadith: the corpus saved on this machine browsed by collection, book and narration, or searched, a list on the left and the open narration on the right; until the corpus is here, the download Deen started when it opened.
FocusScope {
    id: page

    required property var deen

    readonly property var c: deen.c
    readonly property var fonts: deen.fonts
    readonly property var look: deen.look
    readonly property string bodyFont: fonts.ui ?? ""
    readonly property var tones: deen.tones
    readonly property string tint: tones.tint ?? "transparent"
    readonly property string deep: tones.deep ?? "gray"
    readonly property string tile: tones.tile ?? "transparent"

    // True once status reads ready: the browse is on and the download view goes.
    property bool ready: false
    property var download: H.START
    property string dir: ""
    property string narrations: ""
    property var collections: []
    // Collections, a book list, a book's narrations, an open narration or search, each over the one Esc returns to.
    property var levels: H.LEVELS
    // The levels an Enter is loading the next level from, and the Enters and Escs typed meanwhile: an Enter counts on, an Esc takes one back, so keys act in the order typed.
    property var pending: null
    property int ahead: 0
    readonly property var here: levels[levels.length - 1]
    readonly property var listing: H.listEntry(levels)
    readonly property int cursor: listing.cursor
    // Set when the list changes, not on each cursor move, so the view keeps its place.
    property var rows: []
    // The query whose answer is awaited; an answer for an older one is dropped.
    property string asked: ""
    property var hits: []
    property int total: 0
    property string failure: ""
    property string copied: ""
    readonly property var hit: here.level === "narration" ? H.listHit(listing.data, listing.data.hadiths[cursor]) : here.level === "search" && hits.length > 0 ? hits[Math.min(cursor, hits.length - 1)] : null
    readonly property var opened: hit ? H.pane(hit) : null
    readonly property var shown: H.progress(download)

    function checkStatus() {
        deen.api(["hadith", "status"], answer => {
            if (!answer || answer.error) {
                page.download = H.afterEvent(page.download, {
                    event: "error",
                    message: answer && answer.error ? answer.error : "deen hadith status gave no answer"
                });
            } else if (answer.state === "ready") {
                page.becomeReady();
            } else {
                page.dir = answer.dir || "";
                page.download = H.afterEvent(page.download, {
                    event: "progress",
                    done: answer.done,
                    total: answer.total,
                    rate: 0
                });
                page.startFetch();
            }
        });
    }

    function becomeReady() {
        ready = true;
        deen.api(["hadith", "collections"], answer => {
            page.narrations = H.narrations(answer);
            page.collections = answer && Array.isArray(answer.collections) ? answer.collections : [];
            page.showList();
        });
    }

    function showList() {
        const e = listing;
        rows = e.level === "collections" ? collections.map(H.collectionRow) : e.level === "books" ? e.data.books.map(H.bookRow) : e.level === "narrations" ? e.data.hadiths.map(H.narrationRow) : hits.map(H.hitRow);
        list.positionViewAtIndex(cursor, ListView.Contain);
    }

    function goTo(s) {
        levels = s;
        pending = null;
        ahead = 0;
        failure = "";
        showList();
        if (here.level === "search")
            field.forceActiveFocus();
        else
            listKeys.forceActiveFocus();
    }

    // A level's list is asked of deen; an answer that comes after the cursor or the level moved on is dropped.
    function ask(args, level, has) {
        const from = levels;
        pending = from;
        deen.api(args, answer => {
            if (page.levels !== from || page.pending !== from)
                return;
            const more = page.ahead;
            if (answer && Array.isArray(answer[has])) {
                page.goTo(H.down(from, {
                    level: level,
                    data: answer
                }));
                if (more > 0) {
                    page.enter();
                    if (page.pending)
                        page.ahead = more - 1;
                }
            } else {
                page.pending = null;
                page.ahead = 0;
                page.failure = D.oneLine(answer && answer.error ? answer.error : "deen " + args.slice(0, 2).join(" ") + " gave no answer");
            }
        });
    }

    function enter() {
        if (pending) {
            ahead += 1;
            return;
        }
        const e = listing;
        if (here.level !== e.level || rows.length === 0)
            return;
        if (e.level === "collections")
            ask(["hadith", "books", collections[cursor].slug], "books", "books");
        else if (e.level === "books")
            ask(["hadith", "list", e.data.collection, String(e.data.books[cursor].n)], "narrations", "hadiths");
        else if (e.level === "narrations")
            goTo(H.down(levels, {
                level: "narration"
            }));
    }

    // Esc goes up one level; on the collections it is left to the frame, which closes Deen.
    function back() {
        if (pending) {
            if (ahead > 0)
                ahead -= 1;
            else
                pending = null;
            return true;
        }
        const s = H.up(levels);
        if (!s)
            return false;
        if (here.level === "search")
            clearSearch();
        goTo(s);
        return true;
    }

    function clearSearch() {
        debounce.stop();
        field.text = "";
        asked = "";
        hits = [];
        total = 0;
    }

    function openSearch() {
        if (here.level === "search") {
            newSearch();
            return;
        }
        clearSearch();
        goTo(H.search(levels));
    }

    function startFetch() {
        if (fetch.running)
            return;
        download = H.afterEvent(download, {
            event: "progress",
            done: download.done,
            total: download.total,
            rate: 0
        });
        fetch.running = true;
    }

    function take(line) {
        const e = H.event(line);
        if (!e)
            return;
        download = H.afterEvent(download, e);
        if (e.event === "done")
            checkStatus();
    }

    function runSearch() {
        debounce.stop();
        const q = field.text;
        if (q === asked)
            return;
        asked = q;
        const args = H.searchArgs(q);
        if (!args) {
            hits = [];
            total = 0;
            failure = "";
            showList();
            return;
        }
        deen.api(args, answer => {
            if (page.asked !== q || page.here.level !== "search")
                return;
            page.levels = H.withCursor(page.levels, 0);
            page.failure = !answer || answer.error ? D.oneLine(answer && answer.error ? answer.error : "deen hadith search gave no answer") : "";
            page.hits = answer && Array.isArray(answer.hits) ? answer.hits : [];
            page.total = answer && answer.total ? answer.total : page.hits.length;
            page.showList();
        });
    }

    function newSearch() {
        field.text = "";
        runSearch();
        field.focus = true;
    }

    // In search, k on the first hit goes back to the field.
    function moveCursor(by) {
        if (here.level === "search" && by < 0 && cursor === 0) {
            field.forceActiveFocus();
            return;
        }
        if (rows.length === 0)
            return;
        const to = Math.max(0, Math.min(rows.length - 1, cursor + by));
        levels = H.withCursor(levels, to);
        list.positionViewAtIndex(to, ListView.Contain);
    }

    function copyHit() {
        if (!hit)
            return;
        copier.command = ["wl-copy", "--", H.copyText(hit)];
        copier.running = true;
        copied = "copied " + H.boardName(hit.collection, hit.name) + " " + D.oneLine(hit.hadith.n);
    }

    // Only the rows the view has made: a long book's far rows are not drawn until the cursor nears them.
    function rowsDrawn() {
        const out = [];
        for (let i = 0; i < list.count; i++) {
            const r = list.itemAtIndex(i);
            if (r)
                out.push(r.drawn());
        }
        return out;
    }

    function state() {
        return {
            ready: ready,
            focus: field.activeFocus ? "field" : listKeys.activeFocus ? "list" : downloadKeys.activeFocus ? "download" : "",
            download: {
                shown: downloadView.visible,
                label: cardLabel.text,
                title: cardTitle.text,
                percent: barPercent.visible ? barPercent.text : "",
                size: barSize.visible ? barSize.text : "",
                saving: savingRow.visible ? savingRow.value : "",
                speed: speedRow.visible ? speedRow.value : "",
                left: leftRow.visible ? leftRow.value : "",
                fail: failText.visible ? failText.text : "",
                noData: noDataText.visible ? noDataText.text : "",
                noDataAboveKeys: noDataText.visible && noDataText.mapToItem(page, 0, noDataText.height).y < keyStrip.mapToItem(page, 0, 0).y,
                savedIn: savedRow.visible ? savedRow.value : "",
                meanwhile: [meanwhileHead.text, meanwhileLine.drawn(), meanwhileWait.text],
                keyLine: cardKeys.drawn(),
                look: {
                    radius: card.radius,
                    fill: String(card.color),
                    border: card.border.width,
                    titleColor: String(cardTitle.color),
                    titleFont: cardTitle.font.family
                }
            },
            browse: browseView.visible,
            level: here.level,
            heading: headingText.visible ? headingText.text : "",
            error: errorText.visible ? errorText.text : "",
            cursor: cursor,
            count: rows.length,
            rows: rowsDrawn(),
            pane: {
                shown: detail.visible,
                title: detailTitle.text,
                grade: detailGrade.visible ? detailGrade.drawn() : "",
                ar: detailArabic.text,
                arFont: detailArabic.font.family,
                arAlign: detailArabic.horizontalAlignment === Text.AlignRight ? "right" : "left",
                meaningLabel: meaningLabel.text,
                meaning: meaningText.text,
                meaningFamily: meaningText.font.family,
                narrator: detailNarrator.visible ? detailNarrator.text : "",
                sourceLabel: sourceLabel.text,
                reference: referenceText.text,
                referenceFamily: referenceText.font.family
            },
            search: {
                shown: fieldBox.visible,
                text: field.text,
                count: countText.text
            },
            foot: footText.text,
            copied: copiedText.text,
            look: {
                fieldRadius: fieldBox.radius,
                fieldBorder: fieldBox.border.width,
                titleFont: detailTitle.font.family
            },
            keys: keyStrip.drawn()
        };
    }

    // The download starts when Deen opens, whether or not this tab shows.
    Component.onCompleted: checkStatus()

    // One JSON event per line; fetch that ends without done has failed.
    Process {
        id: fetch
        command: [page.deen.backend, "hadith", "fetch", "--json"]
        stdout: SplitParser {
            onRead: data => page.take(data)
        }
        onExited: page.download = H.afterExit(page.download)
    }

    Process {
        id: copier
    }

    Tick {
        id: debounce
        interval: 300
        onTriggered: page.runSearch()
    }

    // r is the download view's one key; Tab and Esc go on to the frame.
    Item {
        id: downloadKeys
        focus: !page.ready
        Keys.onPressed: event => {
            if (event.text === "r" && page.download.phase === "failed") {
                page.startFetch();
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // In place of the tab's body, as Read and Duas draw it.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !page.ready && H.noData(page.download)

            Text {
                id: noDataText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: D.NO_DATA
                color: page.c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: 14
            }
        }

        // Until the corpus is here: the download's progress, or where it stopped.
        ColumnLayout {
            id: downloadView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !page.ready && !H.noData(page.download)
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 16
                Layout.bottomMargin: 6
                spacing: 14

                Text {
                    textFormat: Text.PlainText
                    text: "Hadith"
                    color: page.c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: "search is off until the corpus is on this machine; after that it works offline"
                    color: page.c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // One box at a time, at the width the board gives each: the download running, or failed.
            Rectangle {
                id: card
                readonly property bool failed: page.download.phase === "failed"
                Layout.preferredWidth: 571
                Layout.fillHeight: true
                Layout.leftMargin: 20
                Layout.topMargin: 12
                Layout.bottomMargin: 20
                radius: 14
                color: failed ? page.tones.field : page.tones.card
                border.width: failed ? 0 : 1.5
                border.color: page.c.accent ?? "black"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 18

                    RowLayout {
                        Layout.fillWidth: true

                        Rectangle {
                            implicitWidth: cardLabel.implicitWidth + 18
                            implicitHeight: cardLabel.implicitHeight + 6
                            radius: 8
                            color: page.tint

                            Text {
                                id: cardLabel
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: card.failed ? "2 · if it fails" : "1 · downloading"
                                color: page.c.accent ?? "white"
                                font.family: page.bodyFont
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Text {
                            textFormat: Text.PlainText
                            visible: !card.failed
                            text: "first open only"
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                        }
                    }

                    Text {
                        id: cardTitle
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: card.failed ? "The download did not finish" : page.download.phase === "converting" ? "Putting the corpus together" : "Getting the hadith corpus"
                        color: (card.failed ? page.tones.warn : page.c.ink) ?? "black"
                        font.family: page.bodyFont
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }

                    // The bar, its percent and its size.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !card.failed
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: page.tones.rule ?? "gray"

                            Rectangle {
                                width: parent.width * (page.download.phase === "converting" ? 1 : page.shown.fraction)
                                height: parent.height
                                radius: parent.radius
                                color: page.c.accent ?? "red"
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                id: barPercent
                                textFormat: Text.PlainText
                                text: page.shown.percent
                                color: page.c.ink ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: 12
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                id: barSize
                                textFormat: Text.PlainText
                                text: page.shown.size
                                color: page.c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 12
                            }
                        }
                    }

                    Text {
                        id: failText
                        Layout.fillWidth: true
                        visible: card.failed
                        textFormat: Text.PlainText
                        text: H.failText(page.download)
                        color: page.tones.strong ?? "black"
                        font.family: page.bodyFont
                        font.pixelSize: 14
                        lineHeight: 1.5
                        wrapMode: Text.Wrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Pair {
                            id: savingRow
                            host: page
                            visible: !card.failed
                            label: "saving to"
                            value: H.tilde(page.dir, Quickshell.env("HOME"))
                        }
                        Pair {
                            id: speedRow
                            host: page
                            visible: !card.failed && page.shown.speed !== ""
                            label: "speed"
                            value: page.shown.speed
                        }
                        Pair {
                            id: leftRow
                            host: page
                            visible: !card.failed && page.shown.left !== ""
                            label: "left"
                            value: page.shown.left
                        }
                        Pair {
                            id: savedRow
                            host: page
                            visible: card.failed
                            label: "saved in"
                            value: H.tilde(page.dir, Quickshell.env("HOME"))
                        }
                    }

                    // What works while the download runs.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rule {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 6
                            color: page.tones.rule ?? "gray"
                        }
                        Text {
                            id: meanwhileHead
                            textFormat: Text.PlainText
                            text: "Meanwhile"
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 11
                        }
                        Row {
                            id: meanwhileLine
                            function drawn() {
                                const out = [];
                                for (let i = 0; i < meanwhileParts.count; i++)
                                    out.push(meanwhileParts.itemAt(i).text);
                                return out.join("");
                            }

                            Repeater {
                                id: meanwhileParts
                                model: [["Read", true], [", ", false], ["Duas", true], [" and ", false], ["Prayer", true], [" work now.", false]]

                                Text {
                                    required property var modelData
                                    textFormat: Text.PlainText
                                    text: modelData[0]
                                    color: page.c.ink ?? "black"
                                    font.family: page.bodyFont
                                    font.pixelSize: 14
                                    font.weight: modelData[1] ? Font.Bold : Font.Normal
                                }
                            }
                        }
                        Text {
                            id: meanwhileWait
                            textFormat: Text.PlainText
                            text: "Hadith search waits for the download."
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 14
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    // The board's line: Esc leaves the tab, and the next open resumes what it cut.
                    Row {
                        id: cardKeys
                        spacing: 6
                        function drawn() {
                            const out = [];
                            for (let i = 0; i < cardKeyList.count; i++)
                                out.push(cardKeyList.itemAt(i).drawn());
                            return out.join(" ");
                        }

                        Repeater {
                            id: cardKeyList
                            model: card.failed ? [["r", "retry"], ["esc", "leave"]] : [["esc", "closes; the next open carries on"]]

                            Rectangle {
                                required property var modelData
                                required property int index
                                function drawn() {
                                    return keyName.text + " " + keyWord.text;
                                }
                                implicitWidth: keyRow.implicitWidth + 14
                                implicitHeight: keyRow.implicitHeight + 6
                                radius: 6
                                color: page.tile

                                Row {
                                    id: keyRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        id: keyName
                                        textFormat: Text.PlainText
                                        text: modelData[0]
                                        color: page.c.ink ?? "black"
                                        font.family: page.bodyFont
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        id: keyWord
                                        textFormat: Text.PlainText
                                        text: modelData[1]
                                        color: page.c.ink ?? "black"
                                        font.family: page.bodyFont
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Once the corpus is here: the list of the level on the left, a collection's books, a book's narrations or search's hits, and the open narration on the right.
        FocusScope {
            id: browseView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.ready
            focus: page.ready

            RowLayout {
                anchors.fill: parent
                spacing: 0

                ColumnLayout {
                    Layout.preferredWidth: 495
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    Layout.margins: 12
                    spacing: 10

                    // Search's field: a rounded accent outline.
                    Rectangle {
                        id: fieldBox
                        Layout.fillWidth: true
                        visible: page.here.level === "search"
                        implicitHeight: 44
                        radius: 14
                        color: "transparent"
                        border.width: 1.5
                        border.color: page.c.accent ?? "red"

                        TextInput {
                            id: field
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.right: countBox.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            color: page.c.ink ?? "black"
                            selectionColor: page.c.accent ?? "red"
                            selectedTextColor: page.c.surface ?? "white"
                            font.family: page.bodyFont
                            font.pixelSize: 15
                            onTextEdited: debounce.restart()
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Down) {
                                    page.runSearch();
                                    listKeys.forceActiveFocus();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    event.accepted = page.back();
                                }
                            }
                        }
                        Rectangle {
                            id: countBox
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: countText.implicitWidth + 14
                            implicitHeight: countText.implicitHeight + 4
                            radius: 6
                            visible: countText.text !== ""
                            color: page.tint

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: page.asked.trim() === "" ? "" : H.resultsText(page.total)
                                color: page.deep ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // Where the list is: the collections, a collection's Bangla name, or it and the book's.
                    Text {
                        id: headingText
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.topMargin: 6
                        visible: !fieldBox.visible
                        textFormat: Text.PlainText
                        text: page.here.level === "collections" ? page.look.tabText(H.heading(page.levels)) : H.heading(page.levels)
                        color: page.c.muted ?? "gray"
                        font.family: page.here.level === "collections" ? page.bodyFont : page.deen.bengali
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        id: errorText
                        Layout.fillWidth: true
                        visible: page.failure !== ""
                        textFormat: Text.PlainText
                        text: page.failure
                        color: page.c.danger ?? "red"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    // j and k, or the arrows, move the cursor, Enter goes down a level, Esc up one, / searches; search's field keeps the letters until ↓ or Enter leaves it.
                    Item {
                        id: listKeys
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        focus: true
                        Keys.onPressed: event => {
                            const k = event.key;
                            const t = event.text;
                            if (t === "j" || k === Qt.Key_Down)
                                page.moveCursor(1);
                            else if (t === "k" || k === Qt.Key_Up)
                                page.moveCursor(-1);
                            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                                page.enter();
                            else if (t === "/")
                                page.openSearch();
                            else if (t === "y")
                                page.copyHit();
                            else if (k === Qt.Key_Escape) {
                                event.accepted = page.back();
                                return;
                            } else
                                return;
                            event.accepted = true;
                        }

                        ListView {
                            id: list
                            anchors.fill: parent
                            clip: true
                            spacing: 2
                            model: page.rows
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property bool on: index === page.cursor

                                function drawn() {
                                    const y = mapToItem(list, 0, 0).y;
                                    const texts = [];
                                    const families = [];
                                    for (let i = 0; i < cells.count; i++) {
                                        texts.push(cells.itemAt(i).text);
                                        families.push(cells.itemAt(i).font.family);
                                    }
                                    return {
                                        index: index,
                                        text: texts.join("  "),
                                        families: families,
                                        english: modelData.english,
                                        on: on,
                                        truncated: cells.count > 0 && cells.itemAt(cells.count - 1).truncated,
                                        fill: on ? String(color) : "",
                                        inView: y >= 0 && y + height <= list.height
                                    };
                                }
                                width: ListView.view.width
                                height: 34
                                radius: page.look.cursor.radius
                                color: on ? page.look.cursor.fill ?? "black" : "transparent"

                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    // Each cell in its face; the last one takes the rest of the line and elides.
                                    Repeater {
                                        id: cells
                                        model: row.modelData.cells

                                        Text {
                                            required property var modelData
                                            required property int index
                                            readonly property string face: modelData.face
                                            readonly property bool last: index === row.modelData.cells.length - 1
                                            Layout.fillWidth: last
                                            Layout.preferredWidth: last ? 0 : implicitWidth
                                            textFormat: Text.PlainText
                                            text: face === "mark" ? page.look.tabText(modelData.text) : modelData.text
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            color: (row.on ? (face === "bn" || face === "en" ? page.look.cursor.text : page.look.cursor.detail) : face === "bn" || face === "en" ? page.c.ink : page.c.muted) ?? "black"
                                            font.family: face === "bn" || face === "ref" ? page.deen.bengali : page.bodyFont
                                            font.pixelSize: face === "mark" ? 11 : face === "count" ? 12 : 14
                                            font.weight: row.on && face !== "mark" ? Font.Medium : Font.Normal
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // The pane's left rule.
                Rule {
                    Layout.fillHeight: true
                    implicitWidth: 1
                    color: page.c.line ?? "gray"
                }

                // The open narration as Duas draws a dua: its Arabic, its Bangla meaning, or the English marked where it has none, and its Bangla reference.
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: detail.implicitHeight + 52
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: detail
                        x: 34
                        y: 26
                        width: parent.width - 68
                        spacing: 22
                        visible: page.opened !== null

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                id: detailTitle
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.opened ? page.opened.title : ""
                                color: page.c.ink ?? "black"
                                font.family: page.deen.bengali
                                font.pixelSize: 20
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            // An English grade is drawn only beside English.
                            Grade {
                                id: detailGrade
                                Layout.maximumWidth: 320
                                visible: !!page.opened && page.opened.grade !== ""
                                host: page
                                on: false
                                words: page.opened ? page.opened.grade : ""
                            }
                        }
                        Text {
                            id: detailArabic
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: page.opened ? page.opened.ar : ""
                            color: page.c.ink ?? "black"
                            font.family: page.deen.arabic
                            font.pixelSize: 34
                            lineHeight: 1.7
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.Wrap
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 14

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    id: meaningLabel
                                    textFormat: Text.PlainText
                                    // Where the narration has no Bangla, the label marks the English that stands in.
                                    text: page.look.tabText(page.opened && page.opened.english ? "English" : "Meaning")
                                    color: page.c.muted ?? "gray"
                                    font.family: page.bodyFont
                                    font.pixelSize: 11
                                }
                                Text {
                                    id: meaningText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: page.opened ? page.opened.text : ""
                                    wrapMode: Text.Wrap
                                    color: page.c.ink ?? "black"
                                    font.family: page.opened && page.opened.english ? page.bodyFont : page.deen.bengali
                                    font.pixelSize: 16
                                    lineHeight: 1.4
                                }
                                Text {
                                    id: detailNarrator
                                    Layout.fillWidth: true
                                    visible: !!page.opened && page.opened.by !== ""
                                    textFormat: Text.PlainText
                                    text: page.opened ? "Narrated by " + page.opened.by : ""
                                    color: page.c.muted ?? "gray"
                                    font.family: page.bodyFont
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    id: sourceLabel
                                    textFormat: Text.PlainText
                                    text: page.look.tabText("Source")
                                    color: page.c.muted ?? "gray"
                                    font.family: page.bodyFont
                                    font.pixelSize: 11
                                }
                                Text {
                                    id: referenceText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: page.opened ? page.opened.reference : ""
                                    wrapMode: Text.Wrap
                                    color: page.c.ink ?? "black"
                                    font.family: page.deen.bengali
                                    font.pixelSize: 14
                                }
                            }
                        }
                    }
                }
            }
        }

        // The foot: offline, the corpus's size, and what y last copied.
        Rule {
            Layout.fillWidth: true
            visible: page.ready
            color: page.c.line ?? "gray"
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            visible: page.ready
            spacing: 18

            Text {
                id: footText
                textFormat: Text.PlainText
                text: page.narrations ? "offline · " + page.narrations + " narrations" : "offline"
                color: page.c.ink ?? "black"
                font.family: page.bodyFont
                font.pixelSize: 12
            }
            Text {
                id: copiedText
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: page.copied
                color: page.c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
        DeenKeys {
            id: keyStrip
            Layout.fillWidth: true
            deen: page.deen
            pairs: !page.ready ? [["r", "retry after a failure"], ["tab", "other section"], ["esc", "close"]] : page.here.level === "search" ? [["type", "search"], ["↓", "results"], ["y", "copy"], ["/", "new search"], ["tab", "section"], ["esc", "back"]] : page.here.level === "narration" ? [["j/k", "narration"], ["y", "copy"], ["/", "search"], ["tab", "section"], ["esc", "back"]] : [["j/k", "move"], ["↵", "open"], ["/", "search"], ["tab", "section"], ["esc", page.here.level === "collections" ? "close" : "back"]]
        }
    }

    // A label and its value across a line of the download box.
    component Pair: RowLayout {
        required property var host
        property string label: ""
        property string value: ""
        Layout.fillWidth: true

        Text {
            textFormat: Text.PlainText
            text: parent.label
            color: parent.host.c.muted ?? "gray"
            font.family: parent.host.bodyFont
            font.pixelSize: 12
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            textFormat: Text.PlainText
            text: parent.value
            color: parent.host.c.ink ?? "black"
            font.family: parent.host.bodyFont
            font.pixelSize: 12
        }
    }

    // A grade as a grey chip, or a card-coloured one on the cursor's row.
    component Grade: Rectangle {
        id: grade
        required property var host
        property bool on: false
        property string words: ""
        function drawn() {
            return gradeText.text;
        }
        implicitWidth: gradeText.implicitWidth + 16
        implicitHeight: gradeText.implicitHeight + 4
        radius: 8
        color: on ? grade.host.tones.card : grade.host.tile
        border.width: 0

        Text {
            id: gradeText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, grade.width - 16)
            textFormat: Text.PlainText
            text: grade.words
            color: (grade.on ? grade.host.deep : grade.host.c.ink) ?? "black"
            font.family: grade.host.bodyFont
            font.pixelSize: 11
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    // A one-pixel rule.
    component Rule: Rectangle {
        implicitHeight: 1
    }
}

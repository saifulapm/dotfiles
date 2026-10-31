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
    readonly property string voice: deen.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""
    readonly property string headFont: (caps ? fonts.display : bodyFont) ?? ""
    // Artboard's tints, which no token carries.
    readonly property string tint: "#EEF1FF"
    readonly property string deep: "#2638C9"
    readonly property string tile: "#F2F3F6"

    // True once status reads ready: the browse is on and the download view goes.
    property bool ready: false
    property var download: H.START
    property string dir: ""
    property string narrations: ""
    property var collections: []
    // Collections, a book list, a book's narrations, an open narration or search, each over the one Esc returns to.
    property var levels: H.LEVELS
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

    function say(s) {
        return bracket ? String(s).toUpperCase() : s;
    }

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
        deen.api(args, answer => {
            if (page.levels !== from)
                return;
            if (answer && Array.isArray(answer[has]))
                page.goTo(H.down(from, {
                    level: level,
                    data: answer
                }));
            else
                page.failure = D.oneLine(answer && answer.error ? answer.error : "deen " + args.slice(0, 2).join(" ") + " gave no answer");
        });
    }

    function enter() {
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
                savedIn: savedRow.visible ? savedRow.value : "",
                meanwhile: [meanwhileHead.text, meanwhileLine.drawn(), meanwhileWait.text],
                keyLine: cardKeys.drawn(),
                look: {
                    radius: card.radius,
                    fill: String(card.color),
                    border: card.border.width,
                    titleColor: String(cardTitle.color),
                    ruleDashed: meanwhileRule.dashed,
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
                paneRuleDashed: paneRule.dashed,
                titleFont: detailTitle.font.family
            },
            keys: keyStrip.drawn()
        };
    }

    // The download starts when Deen opens, whether or not this tab shows.
    Component.onCompleted: checkStatus()

    // In place of the tab's body, as Read and Duas draw it.
    Text {
        id: noDataText
        anchors.centerIn: parent
        visible: !page.ready && H.noData(page.download)
        textFormat: Text.PlainText
        text: D.NO_DATA
        color: page.c.muted ?? "gray"
        font.family: page.bodyFont
        font.pixelSize: 14
    }

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
                    font.family: page.headFont
                    font.pixelSize: page.caps ? 25 : page.plain ? 20 : 18
                    font.weight: page.caps ? Font.Normal : Font.Bold
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: page.say("search is off until the corpus is on this machine; after that it works offline")
                    color: page.c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 12
                    font.letterSpacing: page.bracket ? 0.72 : 0
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
                radius: page.plain ? 14 : 0
                color: page.plain && failed ? "#F6F7F9" : page.plain ? "#FFFFFF" : "transparent"
                border.width: page.plain ? (failed ? 0 : 1.5) : page.caps && !failed ? 2 : 1
                border.color: (page.plain || page.bracket && !failed ? page.c.accent : page.bracket ? page.c.line : failed ? page.c.muted : page.c.ink) ?? "black"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 18

                    RowLayout {
                        Layout.fillWidth: true

                        Rectangle {
                            implicitWidth: cardLabel.implicitWidth + (page.bracket ? 0 : page.plain ? 18 : 14)
                            implicitHeight: cardLabel.implicitHeight + (page.bracket ? 0 : page.plain ? 6 : 4)
                            radius: page.plain ? 8 : 0
                            color: page.plain ? page.tint : page.caps ? page.c.ink ?? "black" : "transparent"

                            Text {
                                id: cardLabel
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                readonly property string words: card.failed ? "2 · if it fails" : "1 · downloading"
                                text: page.bracket ? "[" + words.toUpperCase() + "]" : page.caps ? words.toUpperCase() : words
                                color: (page.plain || page.bracket ? page.c.accent : page.c.surface) ?? "white"
                                font.family: page.bodyFont
                                font.pixelSize: page.plain ? 12 : 10
                                font.weight: page.plain ? Font.Medium : page.bracket ? Font.Bold : Font.Normal
                                font.letterSpacing: page.plain ? 0 : 1.3
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Text {
                            textFormat: Text.PlainText
                            visible: !card.failed
                            text: page.say("first open only")
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.letterSpacing: page.bracket ? 0.72 : 0
                        }
                    }

                    Text {
                        id: cardTitle
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: card.failed ? "The download did not finish" : page.download.phase === "converting" ? "Putting the corpus together" : "Getting the hadith corpus"
                        color: (page.plain && card.failed ? "#B4380B" : page.c.ink) ?? "black"
                        font.family: page.headFont
                        font.pixelSize: page.caps ? 25 : page.plain ? 18 : 16
                        font.weight: page.caps ? Font.Normal : Font.Bold
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
                            radius: page.plain ? 4 : 0
                            color: (page.plain ? "#E3E6EB" : page.bracket ? page.c.line : "#E8DEC6") ?? "gray"

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
                                font.letterSpacing: page.bracket ? 0.72 : 0
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                id: barSize
                                textFormat: Text.PlainText
                                text: page.say(page.shown.size)
                                color: page.c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 12
                                font.letterSpacing: page.bracket ? 0.72 : 0
                            }
                        }
                    }

                    Text {
                        id: failText
                        Layout.fillWidth: true
                        visible: card.failed
                        textFormat: Text.PlainText
                        text: H.failText(page.download)
                        color: (page.plain ? "#2B2F36" : page.c.ink) ?? "black"
                        font.family: page.bracket ? page.fonts.ui ?? "" : page.bodyFont
                        font.pixelSize: page.plain ? 14 : 13
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
                            value: page.say(page.shown.speed)
                        }
                        Pair {
                            id: leftRow
                            host: page
                            visible: !card.failed && page.shown.left !== ""
                            label: "left"
                            value: page.say(page.shown.left)
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
                            id: meanwhileRule
                            Layout.fillWidth: true
                            Layout.bottomMargin: 6
                            dashed: page.bracket
                            color: (page.plain ? "#E3E6EB" : page.c.line) ?? "gray"
                        }
                        Text {
                            id: meanwhileHead
                            textFormat: Text.PlainText
                            text: page.plain ? "Meanwhile" : "MEANWHILE"
                            color: page.c.muted ?? "gray"
                            font.family: page.bracket ? page.fonts.mono ?? "" : page.bodyFont
                            font.pixelSize: page.plain ? 11 : 10
                            font.letterSpacing: page.plain ? 0 : 1.4
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
                                    font.family: page.bracket ? page.fonts.ui ?? "" : page.bodyFont
                                    font.pixelSize: page.plain ? 14 : 13
                                    font.weight: modelData[1] ? Font.Bold : Font.Normal
                                }
                            }
                        }
                        Text {
                            id: meanwhileWait
                            textFormat: Text.PlainText
                            text: "Hadith search waits for the download."
                            color: page.c.muted ?? "gray"
                            font.family: page.bracket ? page.fonts.ui ?? "" : page.bodyFont
                            font.pixelSize: page.plain ? 14 : 13
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
                                implicitWidth: keyRow.implicitWidth + (page.plain ? 14 : 0)
                                implicitHeight: keyRow.implicitHeight + (page.plain ? 6 : 0)
                                radius: 6
                                color: page.plain ? page.tile : "transparent"

                                Row {
                                    id: keyRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        id: keyName
                                        textFormat: Text.PlainText
                                        text: page.bracket ? "[" + modelData[0].toUpperCase() + "]" : modelData[0]
                                        color: (page.bracket ? page.c.accent : page.c.ink) ?? "black"
                                        font.family: page.bodyFont
                                        font.pixelSize: 12
                                        font.weight: page.plain ? Font.Medium : Font.Bold
                                        font.letterSpacing: page.bracket ? 0.72 : 0
                                    }
                                    Text {
                                        id: keyWord
                                        textFormat: Text.PlainText
                                        text: page.say(modelData[1]) + (index < cardKeyList.count - 1 && !page.plain ? " ·" : "")
                                        color: page.c.ink ?? "black"
                                        font.family: page.bodyFont
                                        font.pixelSize: 12
                                        font.letterSpacing: page.bracket ? 0.72 : 0
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

                    // Search's field: Paper's two-pixel accent box, Artboard's rounded outline, Blueprint's one-pixel accent box.
                    Rectangle {
                        id: fieldBox
                        Layout.fillWidth: true
                        visible: page.here.level === "search"
                        implicitHeight: page.plain ? 44 : 42
                        radius: page.plain ? 14 : 0
                        color: "transparent"
                        border.width: page.caps ? 2 : page.plain ? 1.5 : 1
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
                            font.pixelSize: page.plain ? 15 : 14
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
                            implicitWidth: countText.implicitWidth + (page.plain ? 14 : 0)
                            implicitHeight: countText.implicitHeight + (page.plain ? 4 : 0)
                            radius: 6
                            visible: countText.text !== ""
                            color: page.plain ? page.tint : "transparent"

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: page.asked.trim() === "" ? "" : page.say(H.resultsText(page.total))
                                color: (page.plain ? page.deep : page.c.muted) ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: page.bracket ? 10 : 11
                                font.weight: page.plain ? Font.Medium : Font.Normal
                                font.letterSpacing: page.bracket ? 1.4 : 0
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
                        font.pixelSize: page.plain ? 12 : 11
                        font.letterSpacing: page.here.level === "collections" && !page.plain ? 1.4 : 0
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
                                radius: page.plain ? page.look.cursor.radius : 0
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
                                            font.pixelSize: face === "mark" ? (page.plain ? 11 : 10) : face === "count" ? 12 : page.plain ? 14 : 13
                                            font.letterSpacing: face === "mark" && !page.plain ? 1.4 : 0
                                            font.weight: row.on && !page.bracket && face !== "mark" ? Font.Medium : Font.Normal
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // The pane's left rule, dashed under Blueprint.
                Item {
                    Layout.fillHeight: true
                    implicitWidth: 1

                    Rule {
                        id: paneRule
                        width: parent.height
                        rotation: 90
                        transformOrigin: Item.TopLeft
                        x: 1
                        dashed: page.bracket
                        color: (page.caps ? page.c.ink : page.c.line) ?? "gray"
                    }
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
                                font.pixelSize: page.caps ? 25 : page.plain ? 20 : 18
                                font.weight: page.caps ? Font.Normal : Font.Bold
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
                                    font.pixelSize: page.plain ? 11 : 10
                                    font.letterSpacing: page.plain ? 0 : 1.4
                                }
                                Text {
                                    id: meaningText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: page.opened ? page.opened.text : ""
                                    wrapMode: Text.Wrap
                                    color: page.c.ink ?? "black"
                                    font.family: page.opened && page.opened.english ? page.bodyFont : page.deen.bengali
                                    font.pixelSize: page.plain ? 16 : page.bracket ? 14 : 15
                                    lineHeight: 1.4
                                }
                                Text {
                                    id: detailNarrator
                                    Layout.fillWidth: true
                                    visible: !!page.opened && page.opened.by !== ""
                                    textFormat: Text.PlainText
                                    text: page.opened ? page.say("Narrated by " + page.opened.by) : ""
                                    color: page.c.muted ?? "gray"
                                    font.family: page.bodyFont
                                    font.pixelSize: 12
                                    font.letterSpacing: page.bracket ? 0.72 : 0
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
                                    font.pixelSize: page.plain ? 11 : 10
                                    font.letterSpacing: page.plain ? 0 : 1.4
                                }
                                Text {
                                    id: referenceText
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: page.opened ? page.opened.reference : ""
                                    wrapMode: Text.Wrap
                                    color: page.c.ink ?? "black"
                                    font.family: page.deen.bengali
                                    font.pixelSize: page.plain ? 14 : 13
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
            dashed: page.bracket
            color: (page.caps ? page.c.ink : page.c.line) ?? "gray"
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            Layout.leftMargin: page.plain ? 20 : 16
            Layout.rightMargin: page.plain ? 20 : 16
            visible: page.ready
            spacing: 18

            Text {
                id: footText
                textFormat: Text.PlainText
                text: page.say(page.narrations ? "offline · " + page.narrations + " narrations" : "offline")
                color: page.c.ink ?? "black"
                font.family: page.bodyFont
                font.pixelSize: 12
                font.letterSpacing: page.bracket ? 0.72 : 0
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
            text: parent.host.say(parent.label)
            color: parent.host.c.muted ?? "gray"
            font.family: parent.host.bodyFont
            font.pixelSize: 12
            font.letterSpacing: parent.host.bracket ? 0.72 : 0
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
            font.letterSpacing: parent.host.bracket ? 0.72 : 0
        }
    }

    // A grade: Paper's ruled box in caps, Artboard's grey chip, Blueprint's bracketed accent caps.
    component Grade: Rectangle {
        id: grade
        required property var host
        property bool on: false
        property string words: ""
        function drawn() {
            return gradeText.text;
        }
        implicitWidth: gradeText.implicitWidth + (grade.host.bracket ? 0 : grade.host.plain ? 16 : 12)
        implicitHeight: gradeText.implicitHeight + (grade.host.bracket ? 0 : grade.host.plain ? 4 : 2)
        radius: grade.host.plain ? 8 : 0
        color: grade.host.plain ? (on ? "#FFFFFF" : grade.host.tile) : "transparent"
        border.width: grade.host.caps ? 1 : 0
        border.color: (on ? grade.host.c.surface : grade.host.c.ink) ?? "black"

        Text {
            id: gradeText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, grade.width - (grade.host.bracket ? 0 : grade.host.plain ? 16 : 12))
            textFormat: Text.PlainText
            text: grade.host.bracket ? "[" + grade.words.toUpperCase() + "]" : grade.host.caps && !grade.on ? grade.words.toUpperCase() : grade.words
            color: (grade.host.plain ? (grade.on ? grade.host.deep : grade.host.c.ink) : grade.on ? grade.host.c.surface : grade.host.bracket ? grade.host.c.accent : grade.host.c.ink) ?? "black"
            font.family: grade.host.bodyFont
            font.pixelSize: grade.host.plain || grade.on && grade.host.caps ? 11 : 10
            font.weight: grade.host.plain ? Font.Medium : grade.host.bracket ? Font.Bold : Font.Normal
            font.letterSpacing: grade.host.plain || grade.on && grade.host.caps ? 0 : 1.2
            elide: Text.ElideRight
            maximumLineCount: 1
        }
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
}

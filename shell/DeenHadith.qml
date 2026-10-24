import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib/deen.mjs" as D
import "lib/deen-hadith.mjs" as H

// Deen's Hadith: a search of the corpus saved on this machine, its hits on the left and the cursored one in full on the right; until the corpus is here, the download Deen started when it opened.
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

    // True once status reads ready: search is on and the download view goes.
    property bool ready: false
    property var download: H.START
    property string dir: ""
    property string narrations: ""
    // The query whose answer is awaited; an answer for an older one is dropped.
    property string asked: ""
    property var hits: []
    property int total: 0
    property string searchError: ""
    property int cursor: 0
    property string copied: ""
    readonly property var hit: hits.length > 0 ? hits[Math.min(cursor, hits.length - 1)] : null
    readonly property var told: hit ? H.narrator(hit.hadith.en) : ({
            by: "",
            body: ""
        })
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
        deen.api(["hadith", "collections"], answer => page.narrations = H.narrations(answer));
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
            searchError = "";
            return;
        }
        deen.api(args, answer => {
            if (page.asked !== q)
                return;
            page.cursor = 0;
            page.searchError = !answer || answer.error ? D.oneLine(answer && answer.error ? answer.error : "deen hadith search gave no answer") : "";
            page.hits = answer && Array.isArray(answer.hits) ? answer.hits : [];
            page.total = answer && answer.total ? answer.total : page.hits.length;
        });
    }

    function newSearch() {
        field.text = "";
        runSearch();
        field.focus = true;
    }

    function moveCursor(by) {
        if (by < 0 && cursor === 0) {
            field.focus = true;
            return;
        }
        cursor = Math.max(0, Math.min(hits.length - 1, cursor + by));
        resultList.positionViewAtIndex(cursor, ListView.Contain);
    }

    function copyHit() {
        if (!hit)
            return;
        copier.command = ["wl-copy", "--", H.copyText(hit)];
        copier.running = true;
        copied = "copied " + H.boardName(hit.collection, hit.name) + " " + D.oneLine(hit.hadith.n);
    }

    function rowsDrawn() {
        const out = [];
        for (let i = 0; i < resultList.count; i++) {
            const r = resultList.itemAtIndex(i);
            if (r)
                out.push(r.drawn());
        }
        return out;
    }

    function state() {
        return {
            ready: ready,
            focus: field.activeFocus ? "field" : resultKeys.activeFocus ? "results" : downloadKeys.activeFocus ? "download" : "",
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
                kept: keptRow.visible ? keptRow.value : "",
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
            search: {
                shown: searchView.visible,
                text: field.text,
                count: countText.text,
                error: errorText.visible ? errorText.text : "",
                cursor: cursor,
                rows: rowsDrawn(),
                detail: {
                    title: detailTitle.visible ? detailTitle.text : "",
                    grade: detailGrade.visible ? detailGrade.drawn() : "",
                    ar: detailArabic.visible ? detailArabic.text : "",
                    arFont: detailArabic.font.family,
                    arAlign: detailArabic.horizontalAlignment === Text.AlignRight ? "right" : "left",
                    en: detailEnglish.visible ? detailEnglish.text : "",
                    narrator: detailNarrator.visible ? detailNarrator.text : ""
                },
                foot: footText.text,
                copied: copiedText.text,
                look: {
                    fieldRadius: fieldBox.radius,
                    fieldBorder: fieldBox.border.width,
                    paneRuleDashed: paneRule.dashed,
                    titleFont: detailTitle.font.family
                }
            },
            keys: keyStrip.drawn()
        };
    }

    // The download starts when Deen opens, whether or not this tab shows.
    Component.onCompleted: checkStatus()

    // One JSON event per line; fetch that ends without done has failed, and keeps what it saved.
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
            visible: !page.ready
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
                            id: keptRow
                            host: page
                            visible: card.failed
                            label: "kept"
                            value: page.say(H.mb(page.download.done))
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

        // Search, once the corpus is here: the field and the hits on the left, the cursored hadith on the right.
        FocusScope {
            id: searchView
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

                    // Paper's two-pixel accent box, Artboard's rounded outline, Blueprint's one-pixel accent box.
                    Rectangle {
                        id: fieldBox
                        Layout.fillWidth: true
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
                            focus: true
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
                                    resultKeys.focus = true;
                                    event.accepted = true;
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

                    Text {
                        id: errorText
                        Layout.fillWidth: true
                        visible: page.searchError !== ""
                        textFormat: Text.PlainText
                        text: page.searchError
                        color: page.c.danger ?? "red"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    // j and k, or the arrows, move the cursor; the field keeps the letters until ↓ or Enter leaves it.
                    Item {
                        id: resultKeys
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Keys.onPressed: event => {
                            const k = event.key;
                            const t = event.text;
                            if (t === "j" || k === Qt.Key_Down)
                                page.moveCursor(1);
                            else if (t === "k" || k === Qt.Key_Up)
                                page.moveCursor(-1);
                            else if (t === "/")
                                page.newSearch();
                            else if (t === "y")
                                page.copyHit();
                            else if (k !== Qt.Key_Return && k !== Qt.Key_Enter)
                                return;
                            event.accepted = true;
                        }

                        ListView {
                            id: resultList
                            anchors.fill: parent
                            clip: true
                            spacing: 2
                            model: page.hits
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: hitRow
                                required property var modelData
                                required property int index
                                readonly property bool on: index === page.cursor
                                readonly property var told: H.narrator(modelData.hadith.en)

                                function drawn() {
                                    return {
                                        name: hitName.text,
                                        n: hitNumber.text,
                                        grade: hitGrade.drawn(),
                                        text: hitText.text,
                                        truncated: hitText.truncated,
                                        lineCount: hitText.lineCount,
                                        on: on,
                                        fill: String(color)
                                    };
                                }
                                width: ListView.view.width
                                implicitHeight: hitColumn.implicitHeight + 20
                                radius: page.plain ? 12 : 0
                                color: on ? page.look.cursor.fill ?? "black" : "transparent"
                                border.width: on && page.plain ? 1.5 : 0
                                border.color: page.c.accent ?? "blue"

                                ColumnLayout {
                                    id: hitColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 5

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Text {
                                            id: hitName
                                            textFormat: Text.PlainText
                                            text: H.boardName(hitRow.modelData.collection, hitRow.modelData.name)
                                            color: (hitRow.on ? page.look.cursor.text : page.c.ink) ?? "black"
                                            font.family: page.bracket ? page.fonts.ui ?? "" : page.bodyFont
                                            font.pixelSize: page.plain ? 14 : 13
                                            font.weight: hitRow.on && page.bracket ? Font.Bold : Font.Medium
                                        }
                                        Text {
                                            id: hitNumber
                                            textFormat: Text.PlainText
                                            text: "#" + D.oneLine(hitRow.modelData.hadith.n)
                                            color: (hitRow.on && !page.plain ? page.look.cursor.detail : page.c.muted) ?? "gray"
                                            font.family: page.bodyFont
                                            font.pixelSize: 12
                                            font.letterSpacing: page.bracket ? 0.72 : 0
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Grade {
                                            id: hitGrade
                                            Layout.maximumWidth: 260
                                            host: page
                                            on: hitRow.on
                                            words: H.gradeText(hitRow.modelData.collection, hitRow.modelData.hadith.grades)
                                        }
                                    }
                                    Text {
                                        id: hitText
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: D.oneLine(hitRow.told.body)
                                        color: (hitRow.on && !page.plain ? page.look.cursor.detail : page.plain ? "#2B2F36" : page.c.ink) ?? "black"
                                        font.family: page.bracket ? page.fonts.ui ?? "" : page.bodyFont
                                        font.pixelSize: page.plain ? 13 : 12
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
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

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: detail.implicitHeight + 52
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: detail
                        x: 32
                        y: 26
                        width: parent.width - 64
                        spacing: 18
                        visible: page.hit !== null

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                id: detailTitle
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.hit ? H.boardName(page.hit.collection, page.hit.name) + " · " + D.oneLine(page.hit.hadith.n) : ""
                                color: page.c.ink ?? "black"
                                font.family: page.headFont
                                font.pixelSize: page.caps ? 25 : page.plain ? 18 : 16
                                font.weight: page.caps ? Font.Normal : Font.Bold
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Grade {
                                id: detailGrade
                                Layout.maximumWidth: 320
                                host: page
                                on: false
                                words: page.hit ? H.gradeText(page.hit.collection, page.hit.hadith.grades) : ""
                            }
                        }
                        Text {
                            id: detailArabic
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: page.hit ? H.wrapped(page.hit.hadith.ar) : ""
                            color: page.c.ink ?? "black"
                            font.family: page.deen.arabic
                            font.pixelSize: 34
                            lineHeight: 1.7
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.Wrap
                        }
                        Text {
                            id: detailEnglish
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: H.wrapped(page.told.body)
                            color: page.c.ink ?? "black"
                            font.family: page.bracket ? page.fonts.ui ?? "" : page.bodyFont
                            font.pixelSize: page.caps ? 15 : page.plain ? 16 : 14
                            lineHeight: 1.55
                            wrapMode: Text.Wrap
                        }
                        Text {
                            id: detailNarrator
                            Layout.fillWidth: true
                            visible: page.told.by !== ""
                            textFormat: Text.PlainText
                            text: page.say("Narrated by " + D.oneLine(page.told.by))
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.letterSpacing: page.bracket ? 0.72 : 0
                            wrapMode: Text.Wrap
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
            pairs: page.ready ? [["type", "search"], ["↓", "results"], ["↵", "open"], ["y", "copy"], ["/", "new search"], ["tab", "section"], ["esc", "close"]] : [["r", "retry after a failure"], ["tab", "other section"], ["esc", "close"]]
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

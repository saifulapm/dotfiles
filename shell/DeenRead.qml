import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib/deen.mjs" as D
import "lib/deen-read.mjs" as R

// Deen's Read: a surah word by word, right to left, each word's Bangla pronunciation and meaning under it and the ayah's under its words; the boxed word's pronunciation, meaning and root show in the bar, and Enter or p plays it.
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
    // The check puts a logging stub here, as no machine running it should make a sound.
    readonly property string player: Quickshell.env("DOTS_DEEN_MPV") || "mpv"

    property var surahs: []
    // The open surah's answer: surah, ayahs and words.
    property var surah: null
    property bool failed: false
    // deen has no Bangla to draw, so the page says how to fetch it in place of its body.
    property bool noData: false
    property var cursor: ({
            a: 1,
            i: 1
        })
    // What m answered, drawn in the bar's hint place until the cursor moves.
    property string note: ""
    property var playerProc: null
    property string playing: ""
    property bool picking: false
    property int pickAt: 0

    readonly property var lengths: surah ? surah.words.map(w => w.length) : []
    readonly property var focused: surah ? surah.words[cursor.a - 1][cursor.i - 1] : null
    readonly property var matches: R.surahsMatching(surahs, field.text)

    // The boxed word as each board draws it: Paper's red rule on cream, Artboard's accent line on its tint, Blueprint's thin accent line.
    readonly property color boxFill: caps ? "#F3E6CF" : plain ? look.label.fill : "transparent"
    readonly property real boxBorder: caps ? 2 : plain ? 1.5 : 1

    function openSurah(n) {
        deen.api(["api", "surah", String(n)], answer => {
            if (D.noData(answer)) {
                page.noData = true;
                return;
            }
            // A surah that fails to open while another shows leaves that one on the page, with a note in the bar.
            if (!R.readable(answer)) {
                if (page.surah)
                    page.note = "Could not open surah " + n;
                else
                    page.failed = true;
                return;
            }
            page.failed = false;
            // The cursor first: the boxed word is read from both, and the old cursor may point past the new surah's last ayah.
            page.cursor = {
                a: 1,
                i: 1
            };
            page.surah = answer;
            page.note = "";
            ayahList.positionViewAtBeginning();
        });
    }

    function moveTo(at) {
        if (!surah)
            return;
        cursor = at;
        note = "";
        keepInView();
    }

    // The cursor's ayah whole in the list, and in an ayah taller than the list (2:282) its boxed word in sight.
    function keepInView() {
        if (!surah)
            return;
        ayahList.positionViewAtIndex(cursor.a - 1, ListView.Contain);
        const row = ayahList.itemAtIndex(cursor.a - 1);
        const box = row ? row.boxAt(cursor.i) : null;
        if (!box)
            return;
        const top = box.mapToItem(ayahList.contentItem, 0, 0).y;
        if (top < ayahList.contentY)
            ayahList.contentY = top;
        else if (top + box.height > ayahList.contentY + ayahList.height)
            ayahList.contentY = top + box.height - ayahList.height;
    }

    // A theme change gives every row a new height, which moves the cursor's ayah, so it is brought back once the rows have their new sizes; so does a list that shrinks.
    onCChanged: keepTimer.restart()

    Tick {
        id: keepTimer
        interval: 50
        onTriggered: page.keepInView()
    }

    function stopPlaying() {
        if (playerProc)
            playerProc.running = false;
        playerProc = null;
        playing = "";
    }

    function play(kind, paths) {
        stopPlaying();
        const p = playerKind.createObject(page, {
            command: [player, "--no-video", "--really-quiet"].concat(paths)
        });
        playerProc = p;
        playing = kind;
        p.running = true;
    }

    function hearWord() {
        if (!focused)
            return;
        stopPlaying();
        const at = surah.surah.n + ":" + cursor.a + ":" + cursor.i;
        deen.api(["audio", at], answer => {
            if (answer && answer.path)
                page.play("word", [answer.path]);
            else
                page.note = answer && answer.error ? String(answer.error) : "No audio for " + at;
        });
    }

    function playSurah() {
        if (!surah)
            return;
        if (playing === "surah") {
            stopPlaying();
            return;
        }
        stopPlaying();
        const from = surah.surah.n + ":" + cursor.a;
        deen.api(["audio", from, "--to-end"], answer => {
            if (answer && Array.isArray(answer.queue) && answer.queue.length > 0)
                page.play("surah", answer.queue);
            else
                page.note = answer && answer.error ? String(answer.error) : "No audio from " + from;
        });
    }

    function memorise() {
        if (!surah)
            return;
        const name = surah.surah.en;
        deen.api(["hifz", "add", String(surah.surah.n)], answer => page.note = R.addedText(answer, name));
    }

    function openPicker() {
        if (surahs.length === 0)
            return;
        field.text = "";
        pickAt = 0;
        picking = true;
        field.forceActiveFocus();
    }

    function closePicker() {
        picking = false;
        wordKeys.forceActiveFocus();
    }

    function pick() {
        const s = matches[pickAt];
        closePicker();
        if (s)
            openSurah(s.n);
    }

    function movePick(by) {
        pickAt = Math.max(0, Math.min(matches.length - 1, pickAt + by));
        pickList.positionViewAtIndex(pickAt, ListView.Contain);
    }

    function state() {
        const row = surah ? ayahList.itemAtIndex(cursor.a - 1) : null;
        const ayah = row ? row.drawn() : null;
        const boxed = ayah ? ayah.words.filter(w => w.boxed)[0] ?? null : null;
        const shown = [];
        for (let k = 0; k < Math.min(5, pickList.count); k++) {
            const r = pickList.itemAtIndex(k);
            if (r)
                shown.push(r.drawn());
        }
        return {
            failed: failedText.visible ? failedText.text : "",
            heading: headingText.text,
            arabic: arabicName.text,
            arabicFamily: arabicName.fontInfo.family,
            meta: metaText.text,
            headingFont: headingText.font.family,
            headingFamily: headingText.fontInfo.family,
            listHeight: ayahList.height,
            hints: hintList.drawn(),
            ayat: ayahList.count,
            ayah: ayah,
            box: boxed ? boxed.look : null,
            bar: {
                word: barWord.text,
                pron: barPron.text,
                pronFamily: barPron.fontInfo.family,
                bn: barBn.text,
                bnFamily: barBn.fontInfo.family,
                line: barLine.text,
                hint: barHint.text,
                fill: bar.color.a > 0 ? String(bar.color) : "",
                border: bar.border.width,
                borderColor: String(bar.border.color),
                radius: bar.radius
            },
            picker: {
                open: picker.visible,
                text: field.text,
                focused: field.activeFocus,
                rows: shown,
                count: pickList.count
            },
            playing: playing,
            keys: keyStrip.drawn()
        };
    }

    Component.onCompleted: {
        deen.api(["api", "surahs"], answer => {
            if (answer && Array.isArray(answer.surahs) && answer.surahs.length > 0)
                page.surahs = answer.surahs;
            else if (D.noData(answer))
                page.noData = true;
            else
                page.failed = true;
        });
        openSurah(1);
    }

    // One player at a time, a child of the page's process, so the frame's Esc ends it with the window.
    Component {
        id: playerKind

        Process {
            id: proc
            onExited: {
                if (page.playerProc === proc) {
                    page.playerProc = null;
                    page.playing = "";
                }
                proc.destroy();
            }
        }
    }

    // Tab and Esc are left for the frame, which moves sections and closes.
    Item {
        id: wordKeys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const t = event.text;
            const k = event.key;
            if (t === "h")
                page.moveTo(R.stepWord(page.lengths, page.cursor, 1));
            else if (t === "l")
                page.moveTo(R.stepWord(page.lengths, page.cursor, -1));
            else if (t === "j")
                page.moveTo(R.stepAyah(page.lengths, page.cursor, 1));
            else if (t === "k")
                page.moveTo(R.stepAyah(page.lengths, page.cursor, -1));
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                page.hearWord();
            else if (t === "p")
                page.playSurah();
            else if (t === "s" || t === "/")
                page.openPicker();
            else if (t === "m")
                page.memorise();
            else
                return;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The surah's name in Bangla and Arabic, its count, kind and juz, and the two keys that change what plays or shows.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.topMargin: 14
            Layout.bottomMargin: 10
            spacing: 14
            visible: !!page.surah && !page.noData

            Text {
                id: headingText
                textFormat: Text.PlainText
                text: page.surah ? D.oneLine(R.headingText(page.surah.surah)) : ""
                color: page.c.ink ?? "black"
                font.family: page.deen.bengali
                font.pixelSize: page.caps ? 25 : page.plain ? 20 : 18
                font.weight: page.caps ? Font.Normal : Font.Bold
            }
            Text {
                id: arabicName
                textFormat: Text.PlainText
                text: page.surah ? D.oneLine(page.surah.surah.ar) : ""
                color: page.c.ink ?? "black"
                font.family: page.deen.arabic
                font.pixelSize: 24
            }
            Text {
                id: metaText
                textFormat: Text.PlainText
                text: page.surah ? R.metaText(page.voice, page.surah.surah, page.surah.ayahs[0].juz ?? null) : ""
                color: page.c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: 12
                font.letterSpacing: page.bracket ? 0.7 : 0
            }
            Item {
                Layout.fillWidth: true
            }
            Row {
                spacing: 8

                Repeater {
                    id: hintList
                    model: page.look.keys([["s", "surah"], ["p", "play surah"]])

                    function drawn() {
                        const out = [];
                        for (let k = 0; k < count; k++)
                            out.push(itemAt(k).drawn());
                        return out;
                    }

                    Rectangle {
                        required property var modelData
                        function drawn() {
                            return hintKey.text + " " + hintWord.text;
                        }
                        implicitWidth: hintPair.implicitWidth + (page.bracket ? 0 : 14)
                        implicitHeight: hintPair.implicitHeight + (page.bracket ? 0 : 6)
                        radius: page.plain ? 6 : 0
                        color: page.plain ? page.look.tile.fill : "transparent"
                        border.width: page.caps ? 1 : 0
                        border.color: page.c.ink ?? "black"

                        Row {
                            id: hintPair
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                id: hintKey
                                textFormat: Text.PlainText
                                text: modelData.key
                                color: (page.bracket ? page.c.accent : page.c.ink) ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: page.plain ? 11 : 10
                                font.weight: page.plain ? Font.Medium : page.bracket ? Font.Bold : Font.Normal
                                font.letterSpacing: page.plain ? 0 : 1.2
                            }
                            Text {
                                id: hintWord
                                textFormat: Text.PlainText
                                text: modelData.word
                                color: (page.plain ? page.c.muted : page.bracket ? page.c.accent : page.c.ink) ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: page.plain ? 11 : 10
                                font.weight: page.bracket ? Font.Bold : Font.Normal
                                font.letterSpacing: page.plain ? 0 : 1.2
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                id: failedText
                anchors.centerIn: parent
                visible: page.failed || page.noData
                textFormat: Text.PlainText
                text: page.noData ? D.NO_DATA : "The Quran text is not on this machine yet"
                color: page.c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: 13
            }

            // A ListView makes only the ayat in sight, so a 286-ayah surah opens as fast as a short one.
            ListView {
                id: ayahList
                anchors.fill: parent
                clip: true
                visible: !page.failed && !page.noData
                model: page.surah ? page.surah.words : []
                boundsBehavior: Flickable.StopAtBounds
                // The bar under the list grows a line for a word with a root, after the list has followed the word.
                onHeightChanged: keepTimer.restart()

                delegate: Item {
                    id: ayahRow
                    required property var modelData
                    required property int index

                    // Word i's box, made on demand, never bound to (a binding does not track Repeater.itemAt).
                    function boxAt(i) {
                        return wordList.itemAt(i - 1);
                    }

                    function drawn() {
                        const words = [];
                        for (let k = 0; k < wordList.count; k++)
                            words.push(wordList.itemAt(k).drawn());
                        // The meaning's ink, from the tallest glyph it holds, on its first and last lines, so a check sees a conjunct the row would cut.
                        const lineHeight = ayahBn.lineCount > 0 ? ayahBn.contentHeight / ayahBn.lineCount : 0;
                        const ink = bnInk.tightBoundingRect;
                        const baseline = ayahBn.y + ayahBn.baselineOffset;
                        return {
                            number: ayahNumber.text,
                            words: words,
                            pron: ayahPron.visible ? ayahPron.text : "",
                            pronFamily: ayahPron.fontInfo.family,
                            pronLines: ayahPron.lineCount,
                            pronTruncated: ayahPron.truncated,
                            pronOverflow: ayahPron.contentWidth > ayahPron.width + 1,
                            bn: ayahBn.visible ? ayahBn.text : "",
                            bnFamily: ayahBn.fontInfo.family,
                            bnLines: ayahBn.lineCount,
                            bnTruncated: ayahBn.truncated,
                            height: ayahRow.height,
                            top: ayahRow.mapToItem(ayahList, 0, 0).y,
                            wordsBottom: wordFlow.y + wordFlow.height,
                            pronBottom: ayahPron.y + ayahPron.height,
                            inkTop: baseline + ink.y,
                            inkBottom: baseline + (ayahBn.lineCount - 1) * lineHeight + ink.y + ink.height,
                            ruleDashed: ayahDash.visible,
                            ruleColor: String(ayahDash.visible ? ayahDash.color : ayahRule.color)
                        };
                    }

                    width: ayahList.width
                    height: Math.max(26, wordFlow.implicitHeight) + 9 + (ayahPron.visible ? ayahPron.anchors.topMargin + ayahPron.height : 0) + (ayahBn.visible ? ayahBn.anchors.topMargin + ayahBn.height : 0)

                    // Paper squares the number in grey, Artboard rounds it on a tile, Blueprint squares it in its rule colour.
                    Rectangle {
                        id: numberBox
                        x: 14
                        anchors.verticalCenter: wordFlow.verticalCenter
                        width: 26
                        height: 26
                        radius: page.plain ? 13 : 0
                        color: page.plain ? page.look.tile.fill : "transparent"
                        border.width: page.plain ? 0 : 1
                        border.color: (page.bracket ? page.c.line : page.c.muted) ?? "gray"

                        Text {
                            id: ayahNumber
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: String(ayahRow.index + 1)
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: page.bracket ? 10 : 11
                        }
                    }

                    Flow {
                        id: wordFlow
                        anchors.left: numberBox.right
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        y: 4
                        spacing: 4
                        // Arabic reads right to left: word 1 sits at the right edge and the next word to its left.
                        layoutDirection: Qt.RightToLeft

                        Repeater {
                            id: wordList
                            model: ayahRow.modelData

                            Rectangle {
                                id: wordBox
                                required property var modelData
                                required property int index
                                readonly property bool current: page.cursor.a === ayahRow.index + 1 && page.cursor.i === index + 1

                                function drawn() {
                                    return {
                                        ar: wordArabic.text,
                                        pron: wordPron.text,
                                        pronFamily: wordPron.fontInfo.family,
                                        pronLines: wordPron.lineCount,
                                        pronTruncated: wordPron.truncated,
                                        bn: wordBn.text,
                                        x: wordBox.mapToItem(page, 0, 0).x,
                                        top: wordBox.mapToItem(ayahList, 0, 0).y,
                                        bottom: wordBox.mapToItem(ayahList, 0, 0).y + wordBox.height,
                                        boxed: current,
                                        family: wordArabic.fontInfo.family,
                                        bnFamily: wordBn.fontInfo.family,
                                        truncated: wordBn.truncated,
                                        lines: wordBn.lineCount,
                                        look: {
                                            fill: wordBox.color.a > 0 ? String(wordBox.color) : "",
                                            border: wordBox.border.width,
                                            borderColor: String(wordBox.border.color),
                                            radius: wordBox.radius,
                                            bnColor: String(wordBn.color)
                                        }
                                    };
                                }

                                width: Math.max(wordArabic.implicitWidth, wordPron.width, wordBn.width) + 24
                                height: wordColumn.implicitHeight + 16
                                radius: page.plain ? 10 : 0
                                color: current ? page.boxFill : "transparent"
                                border.width: current ? page.boxBorder : 0
                                border.color: page.c.accent ?? "red"

                                Column {
                                    id: wordColumn
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        id: wordArabic
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        textFormat: Text.PlainText
                                        text: D.oneLine(wordBox.modelData.text)
                                        color: page.c.ink ?? "black"
                                        font.family: page.deen.arabic
                                        font.pixelSize: 34
                                    }
                                    Text {
                                        id: wordPron
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(implicitWidth, 220)
                                        horizontalAlignment: Text.AlignHCenter
                                        textFormat: Text.PlainText
                                        text: D.oneLine(wordBox.modelData.bn_pron)
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: (wordBox.current && page.plain ? page.look.cursor.text : page.c.muted) ?? "gray"
                                        font.family: page.deen.bengali
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        id: wordBn
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(implicitWidth, 220)
                                        horizontalAlignment: Text.AlignHCenter
                                        textFormat: Text.PlainText
                                        text: D.oneLine(wordBox.modelData.bn)
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: (wordBox.current && page.plain ? page.look.cursor.text : page.c.muted) ?? "gray"
                                        font.family: page.deen.bengali
                                        font.pixelSize: 13
                                    }
                                }
                            }
                        }
                    }

                    // The ayah's pronunciation, then its meaning, under its words, each wrapping so the row grows with it.
                    Text {
                        id: ayahPron
                        anchors.left: wordFlow.left
                        anchors.right: wordFlow.right
                        anchors.top: wordFlow.bottom
                        anchors.topMargin: 6
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: D.oneLine(page.surah && page.surah.ayahs[ayahRow.index] ? page.surah.ayahs[ayahRow.index].bn_pron : "")
                        wrapMode: Text.WordWrap
                        color: page.c.muted ?? "gray"
                        font.family: page.deen.bengali
                        font.pixelSize: page.caps ? 16 : 15
                    }
                    Text {
                        id: ayahBn
                        anchors.left: wordFlow.left
                        anchors.right: wordFlow.right
                        anchors.top: ayahPron.visible ? ayahPron.bottom : wordFlow.bottom
                        anchors.topMargin: 6
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: D.oneLine(page.surah && page.surah.ayahs[ayahRow.index] ? page.surah.ayahs[ayahRow.index].bn : "")
                        wrapMode: Text.WordWrap
                        color: page.c.ink ?? "black"
                        font.family: page.deen.bengali
                        font.pixelSize: page.caps ? 16 : 15
                    }
                    TextMetrics {
                        id: bnInk
                        font: ayahBn.font
                        text: ayahBn.text
                    }

                    Rectangle {
                        id: ayahRule
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        visible: !page.bracket
                        color: page.plain ? "#E3E6EB" : "#D8CDB6"
                    }
                    Dashed {
                        id: ayahDash
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        visible: page.bracket
                        color: page.c.line ?? "gray"
                    }
                }
            }
        }

        // The boxed word, its pronunciation and meaning, and where it stands; Paper rules it in ink, Artboard fills it grey, Blueprint rules it in its accent.
        Rectangle {
            id: bar
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 14
            visible: !!page.focused && !page.noData
            implicitHeight: barRow.implicitHeight + 24
            radius: page.plain ? 12 : 0
            color: page.plain ? "#F6F7F9" : "transparent"
            border.width: page.plain ? 0 : 1
            border.color: (page.bracket ? page.c.accent : page.c.ink) ?? "black"

            RowLayout {
                id: barRow
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 18

                Text {
                    id: barWord
                    textFormat: Text.PlainText
                    text: page.focused ? D.oneLine(page.focused.text) : ""
                    color: page.c.ink ?? "black"
                    font.family: page.deen.arabic
                    font.pixelSize: 30
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        id: barPron
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: page.focused ? D.oneLine(page.focused.bn_pron) : ""
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: page.c.ink ?? "black"
                        font.family: page.deen.bengali
                        font.pixelSize: page.plain ? 15 : 14
                    }
                    Text {
                        id: barBn
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: page.focused ? D.oneLine(page.focused.bn) : ""
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: page.c.ink ?? "black"
                        font.family: page.deen.bengali
                        font.pixelSize: page.plain ? 15 : 14
                        font.weight: Font.Medium
                    }
                    Text {
                        id: barLine
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: page.focused ? D.oneLine(R.wordLine(page.voice, page.focused, page.cursor.a)) : ""
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: page.c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        font.letterSpacing: page.bracket ? 0.7 : 0
                    }
                }
                Text {
                    id: barHint
                    textFormat: Text.PlainText
                    text: page.note ? D.oneLine(page.note) : R.hearHint(page.voice)
                    color: page.c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: page.bracket ? 10 : 11
                    font.letterSpacing: page.bracket ? 1.4 : 0
                }
            }
        }

        DeenKeys {
            id: keyStrip
            Layout.fillWidth: true
            deen: page.deen
            pairs: [["h/l", "word"], ["j/k", "ayah"], ["↵", "hear word"], ["p", "play surah"], ["s", "surah"], ["/", "search"], ["m", "memorise"], ["tab", "section"], ["esc", "close"]]
        }
    }

    // The surah picker over the page, its rows drawn as the launcher draws them.
    Rectangle {
        id: picker
        visible: page.picking
        anchors.horizontalCenter: parent.horizontalCenter
        y: 40
        width: Math.min(640, parent.width - 36)
        height: Math.min(parent.height - 80, pickColumn.implicitHeight)
        radius: page.plain ? 14 : 0
        color: page.c.surface ?? "white"
        border.width: 1
        border.color: (page.plain ? page.c.line : page.bracket ? page.c.accent : page.c.ink) ?? "black"
        clip: true

        ColumnLayout {
            id: pickColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            TextInput {
                id: field
                Layout.fillWidth: true
                Layout.margins: 16
                clip: true
                color: page.c.ink ?? "black"
                selectionColor: page.c.accent ?? "red"
                selectedTextColor: page.c.surface ?? "white"
                font.family: page.look.query.font
                font.pixelSize: 20
                onTextChanged: page.pickAt = 0
                // Plain j and k are letters a name holds, so they type; arrows and Ctrl+J/K move, as in the launcher.
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J))
                        page.movePick(1);
                    else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K))
                        page.movePick(-1);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        page.pick();
                    else if (event.key === Qt.Key_Escape)
                        page.closePicker();
                    else
                        return;
                    event.accepted = true;
                }

                Text {
                    anchors.fill: parent
                    visible: field.text === ""
                    textFormat: Text.PlainText
                    text: page.plain ? "Surah number or name" : page.look.tabText("surah number or name")
                    color: page.c.muted ?? "gray"
                    font: field.font
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: (page.caps ? page.c.ink : page.c.line) ?? "gray"
            }
            ListView {
                id: pickList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 420)
                Layout.margins: 8
                clip: true
                model: page.matches
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: pickRow
                    required property var modelData
                    required property int index
                    readonly property bool current: index === page.pickAt

                    function drawn() {
                        return {
                            n: pickNumber.text,
                            name: pickName.text,
                            current: current,
                            fill: pickRow.color.a > 0 ? String(pickRow.color) : ""
                        };
                    }

                    width: pickList.width
                    implicitHeight: pickLine.implicitHeight + 14
                    radius: page.look.cursor.radius
                    color: current ? page.look.cursor.fill : "transparent"

                    RowLayout {
                        id: pickLine
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 14

                        Text {
                            id: pickNumber
                            Layout.preferredWidth: 30
                            textFormat: Text.PlainText
                            text: String(pickRow.modelData.n)
                            color: (pickRow.current ? page.look.cursor.text : page.c.muted) ?? "gray"
                            font.family: page.look.name.font
                            font.pixelSize: 13
                        }
                        Text {
                            id: pickName
                            textFormat: Text.PlainText
                            text: page.look.title(D.oneLine(pickRow.modelData.bn))
                            color: (pickRow.current ? page.look.cursor.text : page.look.name.color) ?? "black"
                            font.family: page.deen.bengali
                            font.pixelSize: page.look.name.size
                            font.weight: pickRow.current ? page.look.cursor.weight : page.look.name.weight
                        }
                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: page.look.detailText(D.oneLine(pickRow.modelData.tr))
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: (pickRow.current ? page.look.cursor.detail : page.look.detail.color) ?? "gray"
                            font.family: page.look.detail.font
                            font.pixelSize: page.look.detail.size
                            font.italic: page.look.detail.italic
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: D.oneLine(pickRow.modelData.ar)
                            color: (pickRow.current ? page.look.cursor.text : page.c.ink) ?? "black"
                            font.family: page.deen.arabic
                            font.pixelSize: 18
                        }
                    }
                }
            }
        }
    }
}

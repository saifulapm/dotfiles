import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "lib/deen.mjs" as D
import "lib/deen-memorise.mjs" as M

// Deen's Memorise section: today's due ayat one card at a time, the first words until space reveals the rest, then Saiful rates himself 1 to 4.
FocusScope {
    id: page

    required property var deen

    readonly property var c: deen.c
    readonly property var fonts: deen.fonts
    readonly property var look: deen.look
    readonly property string voice: deen.voice
    readonly property bool caps: voice === "caps"
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property var words: M.words(voice)
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""

    // The deck as M.openDeck shapes it, null before the first answer; failed is true when the last answer was no deck.
    property var session: null
    property bool failed: false
    // deen cannot read the Quran text, so the page says how to fetch it rather than that the deck failed.
    property bool noData: false
    property bool revealed: false
    // True from a rating's key until the backend answers, so a second key cannot rate the same card twice.
    property bool saving: false
    property bool unsaved: false
    property var surahs: null
    property bool surahsAsked: false
    // The number of the deck being asked for; an older answer is dropped.
    property int asked: 0
    // When the first card rated on this page comes back, in ms; the page asks for the deck again then.
    property var back: null

    readonly property var head: session ? M.current(session) : null
    readonly property string status: noData ? "nodata" : failed ? "failed" : !session ? "loading" : head ? "card" : session.rated > 0 ? "done" : "empty"
    readonly property var cue: head ? M.firstWords(D.oneLine(head.ayah.ar)) : ({
            shown: "",
            hidden: 0
        })

    function load() {
        const mine = ++asked;
        deen.api(["hifz", "due", "--limit", "40"], answer => {
            if (mine !== page.asked)
                return;
            const next = M.openDeck(answer);
            page.noData = D.noData(answer);
            page.failed = next === null;
            if (next)
                page.session = next;
            page.revealed = false;
            page.saving = false;
            page.unsaved = false;
        });
        if (!surahsAsked) {
            surahsAsked = true;
            deen.api(["api", "surahs"], answer => page.surahs = answer);
        }
    }

    function grade(which) {
        const card = head;
        if (!card || !revealed || saving)
            return;
        saving = true;
        const mine = asked;
        deen.api(["hifz", "grade", card.reference, ["again", "hard", "good", "easy"][which]], answer => {
            if (mine !== page.asked)
                return;
            page.saving = false;
            page.back = M.backAt(page.back, Date.now(), answer);
            const after = M.rate(page.session, answer);
            page.unsaved = after === null;
            if (after === null)
                return;
            page.session = after;
            page.revealed = false;
            // A deck longer than the 40 asked for is asked again once the first 40 are rated.
            if (after.cards.length === 0 && after.left > 0)
                page.load();
        });
    }

    function state() {
        return {
            status: status,
            revealed: revealed,
            count: countText.visible ? countText.text : "",
            countFont: countText.font.family,
            line: lineText.visible ? lineText.text : "",
            message: messageText.visible ? messageText.text : "",
            note: noteText.visible ? noteText.text : "",
            card: {
                shown: card.visible,
                badge: badgeText.text,
                badgeFill: String(badgeBox.color),
                heading: headingText.text,
                headingTruncated: headingText.truncated,
                arabic: arabicCue.visible ? arabicCue.text : arabicFull.visible ? arabicFull.text : "",
                arabicFont: arabicFull.visible ? arabicFull.font.family : arabicCue.font.family,
                blanks: blankList.visible ? blankList.count : 0,
                recite: reciteText.visible ? reciteText.text : "",
                hint: hintBox.visible ? hintKey.text + " " + hintWord.text : "",
                meaning: meaningText.visible ? meaningText.text : "",
                meaningFamily: meaningText.fontInfo.family,
                meaningLines: meaningText.visible ? meaningText.lineCount : 0,
                meaningTruncated: meaningText.visible ? meaningText.truncated : false,
                ask: askText.visible ? askText.text : "",
                askFont: askText.font.family,
                ratings: revealed ? rateList.drawn() : [],
                radius: card.radius,
                border: card.border.width,
                fill: String(card.color),
                borderColor: String(card.border.color)
            },
            keys: keyStrip.drawn()
        };
    }

    // A page left open on "done" shows an Again card again when it is due.
    Tick {
        interval: 15000
        repeat: true
        running: page.visible && page.status === "done" && page.back !== null
        onTriggered: {
            if (!M.reloadNow(page.status, page.back, Date.now()))
                return;
            page.back = null;
            page.load();
        }
    }

    Component.onCompleted: load()
    onVisibleChanged: {
        if (visible)
            load();
    }

    Keys.onPressed: event => {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;
        if (event.key === Qt.Key_Space && head) {
            revealed = true;
            event.accepted = true;
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4 && head) {
            grade(event.key - Qt.Key_1);
            event.accepted = true;
        } else if (event.key === Qt.Key_S && head) {
            session = M.skip(session);
            revealed = false;
            unsaved = false;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.topMargin: 16
            Layout.bottomMargin: 6
            spacing: 14
            visible: page.session !== null && !page.failed && !page.noData

            Text {
                id: countText
                textFormat: Text.PlainText
                text: page.session ? page.words.due(page.session.left) : ""
                color: c.ink ?? "black"
                font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                font.pixelSize: caps ? 25 : plain ? 20 : 18
                font.weight: caps ? Font.Normal : Font.Bold
            }
            Text {
                id: lineText
                textFormat: Text.PlainText
                text: !page.session ? "" : page.head ? page.words.line(page.session.fresh, 1, page.session.left) : page.words.quiet
                color: c.muted ?? "gray"
                font.family: (plain ? fonts.ui : fonts.mono) ?? ""
                font.pixelSize: 12
                font.letterSpacing: bracket ? 0.7 : 0
            }
            Item {
                Layout.fillWidth: true
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // One of the board's two states of the card; the card is the same item before and after space.
            Rectangle {
                id: card
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 20
                anchors.topMargin: 12
                anchors.bottomMargin: 20
                width: Math.min(571, parent.width - 40)
                visible: page.status === "card"
                radius: plain ? 14 : 0
                color: plain ? (page.revealed ? c.surface : look.tile.fill) ?? "white" : "transparent"
                border.width: plain ? (page.revealed ? 1.5 : 0) : caps && page.revealed ? 2 : 1
                border.color: (plain ? c.accent : bracket ? (page.revealed ? c.accent : c.line) : page.revealed ? c.ink : c.muted) ?? "gray"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: page.revealed ? 18 : 22

                    RowLayout {
                        Layout.fillWidth: true

                        Rectangle {
                            id: badgeBox
                            implicitWidth: badgeText.implicitWidth + (plain ? 18 : bracket ? 0 : 14)
                            implicitHeight: badgeText.implicitHeight + (plain ? 6 : bracket ? 0 : 4)
                            radius: plain ? 8 : 0
                            color: (plain ? look.label.fill : caps ? c.ink : "transparent") ?? "transparent"

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: page.words.badge(page.revealed)
                                color: (plain ? c.accent : bracket ? c.accent : c.surface) ?? "black"
                                font.family: (plain ? fonts.ui : fonts.mono) ?? ""
                                font.pixelSize: plain ? 12 : 10
                                font.weight: plain ? Font.Medium : bracket ? Font.Bold : Font.Normal
                                font.letterSpacing: plain ? 0 : bracket ? 1.2 : 1.4
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Text {
                            id: headingText
                            Layout.maximumWidth: card.width * 0.6
                            textFormat: Text.PlainText
                            text: page.head ? D.oneLine(page.words.heading(M.surahName(page.surahs, page.head.ayah.s), page.head.ayah.a)) : ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: c.muted ?? "gray"
                            font.family: (plain ? fonts.ui : fonts.mono) ?? ""
                            font.pixelSize: 12
                            font.letterSpacing: bracket ? 0.7 : 0
                        }
                    }

                    // Right to left: the cue sits at the right edge and a dashed blank stands for each word still to recite.
                    Flow {
                        Layout.fillWidth: true
                        visible: !page.revealed
                        layoutDirection: Qt.RightToLeft
                        spacing: 14

                        Text {
                            id: arabicCue
                            width: Math.min(implicitWidth, card.width - 44)
                            textFormat: Text.PlainText
                            text: page.cue.shown
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignRight
                            color: c.ink ?? "black"
                            font.family: deen.arabic
                            font.pixelSize: 44
                            lineHeight: 1.5
                        }
                        Repeater {
                            id: blankList
                            model: Math.min(page.cue.hidden, 6)

                            Blank {
                                required property int index
                                width: index % 2 === 0 ? 70 : 110
                                height: 30
                            }
                        }
                    }
                    Text {
                        id: arabicFull
                        Layout.fillWidth: true
                        visible: page.revealed
                        textFormat: Text.PlainText
                        text: page.head ? D.oneLine(page.head.ayah.ar) : ""
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignRight
                        color: c.ink ?? "black"
                        font.family: deen.arabic
                        font.pixelSize: 44
                        lineHeight: 1.5
                    }

                    Text {
                        id: reciteText
                        Layout.fillWidth: true
                        visible: !page.revealed
                        textFormat: Text.PlainText
                        text: page.words.recite
                        wrapMode: Text.WordWrap
                        color: c.ink ?? "black"
                        font.family: page.bodyFont
                        font.pixelSize: plain ? 14 : 13
                    }
                    Text {
                        id: meaningText
                        Layout.fillWidth: true
                        visible: page.revealed
                        textFormat: Text.PlainText
                        text: page.head ? D.oneLine(page.head.ayah.bn) : ""
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 4
                        color: c.ink ?? "black"
                        font.family: deen.bengali
                        font.pixelSize: 15
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                    Rectangle {
                        id: hintBox
                        visible: !page.revealed
                        implicitWidth: hintRow.implicitWidth + (plain ? 14 : 0)
                        implicitHeight: hintRow.implicitHeight + (plain ? 6 : 0)
                        radius: 6
                        color: plain ? look.tile.fill : "transparent"

                        Row {
                            id: hintRow
                            anchors.centerIn: parent
                            spacing: bracket ? 8 : 6

                            Text {
                                id: hintKey
                                textFormat: Text.PlainText
                                text: page.words.hintKey
                                color: (bracket ? c.accent : c.ink) ?? "black"
                                font.family: (plain ? fonts.ui : fonts.mono) ?? ""
                                font.pixelSize: 12
                                font.weight: plain ? Font.Medium : Font.Bold
                                font.letterSpacing: bracket ? 0.7 : 0
                            }
                            Text {
                                id: hintWord
                                textFormat: Text.PlainText
                                text: page.words.hintWord
                                color: c.ink ?? "black"
                                font.family: (plain ? fonts.ui : fonts.mono) ?? ""
                                font.pixelSize: 12
                                font.letterSpacing: bracket ? 0.7 : 0
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: page.revealed
                        spacing: 8

                        Text {
                            id: askText
                            textFormat: Text.PlainText
                            text: page.words.ask
                            color: c.muted ?? "gray"
                            font.family: (plain ? fonts.ui : fonts.mono) ?? ""
                            font.pixelSize: plain ? 11 : 10
                            font.letterSpacing: plain ? 0 : 1.4
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                id: rateList
                                model: 4

                                function drawn() {
                                    const out = [];
                                    for (let i = 0; i < count; i++) {
                                        const r = itemAt(i);
                                        if (r)
                                            out.push(r.drawn());
                                    }
                                    return out;
                                }

                                Rectangle {
                                    id: rateTile
                                    required property int index
                                    readonly property string gradeName: ["again", "hard", "good", "easy"][index]

                                    function drawn() {
                                        return {
                                            key: rateKey.text,
                                            word: rateWord.text,
                                            next: rateNext.text,
                                            radius: radius
                                        };
                                    }
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: rateColumn.implicitHeight + 20
                                    radius: plain ? 12 : 0
                                    color: plain ? look.tile.fill : "transparent"
                                    border.width: plain ? 0 : 1
                                    border.color: (bracket ? c.line : c.muted) ?? "gray"

                                    ColumnLayout {
                                        id: rateColumn
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            id: rateKey
                                            Layout.alignment: Qt.AlignHCenter
                                            textFormat: Text.PlainText
                                            text: String(rateTile.index + 1)
                                            color: c.ink ?? "black"
                                            font.family: (plain ? fonts.ui : fonts.mono) ?? ""
                                            font.pixelSize: 16
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            id: rateWord
                                            Layout.alignment: Qt.AlignHCenter
                                            textFormat: Text.PlainText
                                            text: page.words.grades[rateTile.index]
                                            color: c.ink ?? "black"
                                            font.family: page.bodyFont
                                            font.pixelSize: plain ? 13 : 12
                                        }
                                        Text {
                                            id: rateNext
                                            Layout.alignment: Qt.AlignHCenter
                                            textFormat: Text.PlainText
                                            text: page.head ? M.nextText(page.voice, page.head.next[rateTile.gradeName]) : ""
                                            color: c.muted ?? "gray"
                                            font.family: (plain ? fonts.ui : fonts.mono) ?? ""
                                            font.pixelSize: bracket ? 10 : 11
                                            font.letterSpacing: bracket ? 1.4 : 0
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                anchors.topMargin: 12
                visible: page.status !== "card"
                spacing: 8

                Text {
                    id: messageText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: page.status === "nodata" ? D.NO_DATA : page.status === "failed" ? page.words.failed : page.status === "empty" ? page.words.nothing : page.status === "done" ? page.words.done(page.session.nextIn) : ""
                    wrapMode: Text.WordWrap
                    color: c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: plain ? 14 : 13
                }
            }
            Text {
                id: noteText
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 20 + card.width + 18
                anchors.bottomMargin: 20
                visible: page.unsaved
                textFormat: Text.PlainText
                text: page.words.unsaved
                color: (bracket ? c.danger : c.accent) ?? "red"
                font.family: page.bodyFont
                font.pixelSize: 12
            }
        }

        DeenKeys {
            id: keyStrip
            Layout.fillWidth: true
            deen: page.deen
            pairs: [["space", "reveal"], ["1", "again"], ["2", "hard"], ["3", "good"], ["4", "easy"], ["s", "skip"], ["tab", "section"], ["esc", "close"]]
        }
    }

    // A dashed box for a word still to recite: Paper's square, Artboard's rounded, Blueprint's thinner.
    component Blank: Shape {
        id: blank

        preferredRendererType: Shape.GeometryRenderer

        ShapePath {
            strokeColor: (page.bracket ? page.c.muted : page.plain ? page.c.line : page.c.muted) ?? "gray"
            strokeWidth: page.bracket ? 1 : 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [4, 3]
            fillColor: "transparent"

            PathSvg {
                path: {
                    const r = page.plain ? 10 : 0;
                    const w = blank.width - 1;
                    const h = blank.height - 1;
                    return "M " + (r + 0.5) + " 0.5 L " + (w - r) + " 0.5 Q " + w + " 0.5 " + w + " " + (r + 0.5) + " L " + w + " " + (h - r) + " Q " + w + " " + h + " " + (w - r) + " " + h + " L " + (r + 0.5) + " " + h + " Q 0.5 " + h + " 0.5 " + (h - r) + " L 0.5 " + (r + 0.5) + " Q 0.5 0.5 " + (r + 0.5) + " 0.5 Z";
                }
            }
        }
    }
}

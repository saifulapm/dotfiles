import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "lib/dekho.mjs" as D
import "lib/dekho-home.mjs" as H

// Dekho's Home: the search field over three rows of titles, continue watching, trending series and trending movies; a search's results take the rows' place.
FocusScope {
    id: home

    required property var dekho

    readonly property var c: dekho.c
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property string voice: dekho.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property var words: H.homeText(voice)
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""

    property var continued: []
    property var series: []
    property var movies: []
    property var results: []
    // True from a search's Enter until Esc: the results row is drawn in place of the home rows.
    property bool searching: false
    // The words of the search whose answer is awaited; an older answer is dropped.
    property string asked: ""
    property string row: "continue"
    property int col: 0

    readonly property var rowNames: searching ? ["results"] : ["continue", "series", "movies"].filter(r => itemsOf(r).length > 0)

    function itemsOf(name) {
        return name === "continue" ? continued : name === "series" ? series : name === "movies" ? movies : results;
    }

    function stripOf(name) {
        return name === "continue" ? continueStrip : name === "series" ? seriesStrip : name === "movies" ? moviesStrip : resultsStrip;
    }

    function listOf(answer, n) {
        return answer && Array.isArray(answer.items) ? answer.items.slice(0, n) : [];
    }

    function moveRow(by) {
        const names = rowNames;
        if (names.length === 0)
            return;
        const at = names.indexOf(row);
        row = names[((at < 0 ? 0 : at + by) % names.length + names.length) % names.length];
        col = Math.max(0, Math.min(itemsOf(row).length - 1, col));
        stripOf(row).reveal(col);
    }

    function moveCol(by) {
        col = Math.max(0, Math.min(itemsOf(row).length - 1, col + by));
        stripOf(row).reveal(col);
    }

    function search() {
        const words = D.title(field.text);
        if (!words)
            return;
        searching = true;
        results = [];
        row = "results";
        col = 0;
        asked = words;
        rowKeys.forceActiveFocus();
        dekho.api(["api", "search"].concat(words.split(" ")), answer => {
            if (home.asked === words)
                home.results = home.listOf(answer, 20);
        });
    }

    function focusSearch() {
        field.forceActiveFocus();
    }

    function leaveSearch() {
        searching = false;
        asked = "";
        results = [];
        field.text = "";
        row = rowNames.length ? rowNames[0] : "continue";
        col = 0;
        rowKeys.forceActiveFocus();
    }

    function state() {
        return {
            focus: {
                row: field.activeFocus ? "search" : row,
                col: col
            },
            search: {
                text: field.text,
                focused: field.activeFocus,
                results: resultsStrip.drawn()
            },
            rows: {
                shown: rowsColumn.visible,
                continue: continueStrip.drawn(),
                series: seriesStrip.drawn(),
                movies: moviesStrip.drawn()
            },
            look: {
                homeFont: pageName.font.family,
                rowHead: continueStrip.headText,
                cardRadius: continueStrip.cardRadius,
                ruleDashed: headRule.dashed
            }
        };
    }

    Component.onCompleted: {
        dekho.api(["api", "history", "--limit", "20"], answer => home.continued = home.listOf(answer, 20));
        dekho.api(["api", "trending", "--kind", "tv"], answer => home.series = home.listOf(answer, 10));
        dekho.api(["api", "trending", "--kind", "movie"], answer => home.movies = home.listOf(answer, 10));
    }

    // The cursor lands on the first row that has titles, once one does.
    onRowNamesChanged: if (!searching && rowNames.indexOf(row) < 0 && rowNames.length)
        row = rowNames[0]

    Item {
        id: rowKeys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text;
            if (t === "/")
                field.forceActiveFocus();
            else if (t === "f")
                home.dekho.open("browse", {
                    from: "home"
                });
            else if (k === Qt.Key_Escape) {
                if (home.searching)
                    home.leaveSearch();
                else
                    home.dekho.back();
            } else if (k === Qt.Key_Tab)
                home.moveRow(1);
            else if (t === "j" || k === Qt.Key_Down)
                home.moveRow(1);
            else if (t === "k" || k === Qt.Key_Up)
                home.moveRow(-1);
            else if (t === "l" || k === Qt.Key_Right)
                home.moveCol(1);
            else if (t === "h" || k === Qt.Key_Left)
                home.moveCol(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                const item = home.itemsOf(home.row)[home.col];
                if (item)
                    home.dekho.openTitle(item);
            } else
                return;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The header: Dekho's label, the page's name, and how it opened; Artboard pills the label in its accent and the note in grey.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: plain ? 52 : -1
            Layout.leftMargin: plain ? 18 : 14
            Layout.rightMargin: plain ? 18 : 14
            Layout.topMargin: plain ? 0 : 12
            Layout.bottomMargin: plain ? 0 : 12
            spacing: plain ? 12 : 10

            Rectangle {
                implicitWidth: labelText.implicitWidth + (plain ? 18 : 0)
                implicitHeight: labelText.implicitHeight + (plain ? 6 : 0)
                radius: 8
                color: plain ? look.label.fill : "transparent"

                Text {
                    id: labelText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.label
                    color: plain ? c.accent ?? "blue" : c.muted ?? "gray"
                    font.family: home.bodyFont
                    font.pixelSize: plain ? 12 : 10
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.letterSpacing: plain ? 0 : 1.4
                }
            }
            Text {
                id: pageName
                textFormat: Text.PlainText
                text: words.page
                color: c.ink ?? "black"
                font.family: (voice === "caps" ? fonts.display : home.bodyFont) ?? ""
                font.pixelSize: voice === "caps" ? 18 : plain ? 14 : 12
                font.weight: voice === "caps" ? Font.Normal : Font.Bold
            }
            Item {
                Layout.fillWidth: true
            }
            Rectangle {
                implicitWidth: fromText.implicitWidth + (plain ? 18 : 0)
                implicitHeight: fromText.implicitHeight + (plain ? 6 : 0)
                radius: 8
                color: plain ? look.tile.fill : "transparent"

                Text {
                    id: fromText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.from
                    color: c.muted ?? "gray"
                    font.family: home.bodyFont
                    font.pixelSize: bracket ? 10 : 11
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.letterSpacing: bracket ? 1.4 : 0
                }
            }
        }

        Rule {
            id: headRule
            Layout.fillWidth: true
            dashed: bracket
            color: voice === "caps" ? c.ink ?? "black" : c.line ?? "gray"
        }

        // The search field: Paper's and Blueprint's ruled box, Artboard's filled pill.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 6
            implicitHeight: plain ? 48 : 46
            radius: plain ? 14 : 0
            color: plain ? "#F6F7F9" : "transparent"
            border.width: plain ? 0 : 1
            border.color: (bracket ? c.line : c.muted) ?? "gray"

            FilesIcon {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                path: "M11.5 7A4.5 4.5 0 1 1 2.5 7A4.5 4.5 0 1 1 11.5 7M10.5 10.5L14 14"
                size: plain ? 18 : 16
                stroke: plain ? 1.6 : 1.4
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
                font.family: home.bodyFont
                font.pixelSize: bracket ? 14 : 15
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        home.search();
                    else if (event.key === Qt.Key_Escape)
                        home.leaveSearch();
                    else
                        return;
                    event.accepted = true;
                }

                Text {
                    anchors.fill: parent
                    visible: field.text === ""
                    textFormat: Text.PlainText
                    text: words.search
                    color: c.muted ?? "gray"
                    font: field.font
                }
            }
            Rectangle {
                id: hint
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: hintText.implicitWidth + (plain ? 14 : 0)
                implicitHeight: hintText.implicitHeight + (plain ? 4 : 0)
                radius: 6
                color: plain ? c.surface ?? "white" : "transparent"

                Text {
                    id: hintText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.hint
                    color: c.muted ?? "gray"
                    font.family: home.bodyFont
                    font.pixelSize: bracket ? 10 : 11
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.letterSpacing: bracket ? 1.4 : 0
                }
            }
        }

        ColumnLayout {
            id: rowsColumn
            Layout.fillWidth: true
            Layout.margins: 18
            Layout.topMargin: 16
            visible: !home.searching
            spacing: 22

            Strip {
                id: continueStrip
                Layout.fillWidth: true
                page: home
                name: "continue"
                items: home.continued
                headText: words.continue
                tailText: String(home.continued.length)
            }
            Strip {
                id: seriesStrip
                Layout.fillWidth: true
                page: home
                name: "series"
                items: home.series
                headText: words.series
                tailText: words.week
            }
            Strip {
                id: moviesStrip
                Layout.fillWidth: true
                page: home
                name: "movies"
                items: home.movies
                headText: words.movies
                tailText: words.week
            }
        }

        Strip {
            id: resultsStrip
            Layout.fillWidth: true
            Layout.margins: 18
            Layout.topMargin: 16
            visible: home.searching
            page: home
            name: "results"
            items: home.results
            headText: words.results
            tailText: String(home.results.length)
        }

        Item {
            Layout.fillHeight: true
        }

        Rule {
            Layout.fillWidth: true
            dashed: bracket
            color: voice === "caps" ? c.ink ?? "black" : c.line ?? "gray"
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
                model: home.look.keys(home.words.keys)

                Rectangle {
                    required property var modelData
                    implicitWidth: keyPair.implicitWidth + (home.plain ? 14 : 0)
                    implicitHeight: keyPair.implicitHeight + (home.plain ? 6 : 0)
                    radius: 6
                    color: home.plain ? home.look.tile.fill : "transparent"

                    Row {
                        id: keyPair
                        anchors.centerIn: parent
                        spacing: home.bracket ? 8 : 6

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.key
                            color: (home.bracket ? home.c.accent : home.c.ink) ?? "black"
                            font.family: home.bodyFont
                            font.pixelSize: home.voice === "caps" ? 10 : 11
                            font.weight: home.plain ? Font.Medium : Font.Bold
                            font.letterSpacing: home.voice === "caps" ? 1 : home.bracket ? 1.5 : 0
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: modelData.word
                            color: home.c.muted ?? "gray"
                            font.family: home.bodyFont
                            font.pixelSize: home.voice === "caps" ? 10 : 11
                            font.letterSpacing: home.voice === "caps" ? 1 : home.bracket ? 1.5 : 0
                        }
                    }
                }
            }
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

    // One row of titles: its heading, then a strip of cards, as many shown as the board's five columns fit, scrolled without motion to keep the cursor's card in view.
    component Strip: ColumnLayout {
        id: strip

        required property var page
        required property string name
        required property var items
        property string headText: ""
        property string tailText: ""
        readonly property real cardWidth: Math.max(0, (width - 4 * 14) / 5)
        readonly property real cardRadius: page.plain ? 12 : 0

        function reveal(i) {
            const card = cards.itemAt(i);
            if (!card)
                return;
            if (card.x < view.contentX)
                view.contentX = card.x;
            else if (card.x + card.width > view.contentX + view.width)
                view.contentX = card.x + card.width - view.width;
        }

        function drawn() {
            const out = [];
            for (let i = 0; i < cards.count; i++)
                out.push(cards.itemAt(i).drawn());
            return out;
        }

        spacing: 8

        // Its items change when an answer lands, and the strip starts at its first card again.
        onItemsChanged: view.contentX = 0

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: strip.headText
                color: strip.page.c.muted ?? "gray"
                font.family: strip.page.bodyFont
                font.pixelSize: strip.page.voice === "caps" ? 10 : 11
                font.letterSpacing: strip.page.plain ? 0 : strip.page.bracket ? 1.54 : 1.4
            }
            Text {
                textFormat: Text.PlainText
                text: strip.tailText
                color: strip.page.c.muted ?? "gray"
                font.family: strip.page.bodyFont
                font.pixelSize: strip.page.voice === "caps" ? 10 : 11
                font.letterSpacing: strip.page.plain ? 0 : strip.page.bracket ? 1.54 : 1.4
            }
        }

        Flickable {
            id: view
            Layout.fillWidth: true
            implicitHeight: cardRow.implicitHeight
            contentWidth: cardRow.implicitWidth
            interactive: false
            clip: true

            Row {
                id: cardRow
                spacing: 14

                Repeater {
                    id: cards
                    model: strip.items

                    Card {
                        page: strip.page
                        viewport: view
                        width: strip.cardWidth
                        radius: strip.cardRadius
                        progressed: strip.name === "continue"
                        focused: strip.page.row === strip.name && strip.page.col === index
                    }
                }
            }
        }
    }

    // A title's card: a poster's place, the title on one elided line, its subtitle, and for a title being watched a thin progress bar.
    component Card: Rectangle {
        id: card

        required property var modelData
        required property int index
        required property var page
        required property Item viewport
        property bool progressed: false
        property bool focused: false
        readonly property var voiceText: progressed ? H.continueLine(page.voice, modelData) : H.hitLine(modelData)
        readonly property real played: Math.max(0, Math.min(1, Number(modelData.progress) || 0))

        function drawn() {
            const at = card.mapToItem(viewport, 0, 0);
            const d = {
                title: titleText.text,
                line: lineText.text,
                lines: titleText.lineCount,
                elided: titleText.truncated,
                shown: card.visible && viewport.visible && at.x >= -0.5 && at.x + card.width <= viewport.width + 0.5
            };
            if (progressed)
                d.progress = Math.round(bar.width / track.width * 100) / 100;
            return d;
        }

        implicitHeight: body.implicitHeight + 20
        color: page.plain ? (focused ? page.c.surface ?? "white" : "#F6F7F9") : page.bracket && focused ? Qt.alpha(page.c.accent ?? "cyan", 0.1) : "transparent"
        border.width: page.plain ? (focused ? 1.5 : 0) : 1
        border.color: (page.plain ? page.c.accent : page.bracket ? (focused ? page.c.accent : page.c.line) : page.c.ink) ?? "black"

        // Paper rings the cursor's card in its accent, two pixels inside its ink border.
        Rectangle {
            anchors.fill: parent
            visible: card.focused && card.page.voice === "caps"
            color: "transparent"
            border.width: 2
            border.color: card.page.c.accent ?? "red"
        }

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // The poster's place, as each board marks it: Paper's hatch, Artboard's grey tile, Blueprint's crossed box.
                Rectangle {
                    implicitWidth: card.page.plain ? 36 : 38
                    implicitHeight: card.page.plain ? 54 : 56
                    radius: card.page.plain ? 8 : 0
                    color: card.page.plain ? "#E9ECF1" : "transparent"
                    border.width: card.page.plain ? 0 : 1
                    border.color: (card.page.bracket ? card.page.c.line : card.page.c.muted) ?? "gray"
                    clip: true

                    Shape {
                        anchors.fill: parent
                        visible: !card.page.plain
                        preferredRendererType: Shape.GeometryRenderer

                        ShapePath {
                            strokeColor: card.page.c.line ?? "gray"
                            strokeWidth: 1
                            fillColor: "transparent"
                            PathSvg {
                                path: card.page.bracket ? "M0 0L38 56M38 0L0 56" : "M6 0L0 6M12 0L0 12M18 0L0 18M24 0L0 24M30 0L0 30M36 0L0 36M42 0L0 42M48 0L0 48M54 0L0 54M60 0L4 56M66 0L10 56M72 0L16 56M78 0L22 56M84 0L28 56M90 0L34 56M96 0L40 56"
                            }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        id: titleText
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: D.title(card.modelData.title)
                        color: card.page.c.ink ?? "black"
                        font.family: card.page.bodyFont
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        id: lineText
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: card.voiceText
                        color: card.page.c.muted ?? "gray"
                        font.family: card.page.bodyFont
                        font.pixelSize: card.page.bracket ? 10 : 11
                        font.letterSpacing: card.page.bracket ? 1.4 : 0
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
            Rectangle {
                id: track
                Layout.fillWidth: true
                visible: card.progressed
                implicitHeight: 4
                radius: card.page.plain ? 2 : 0
                color: card.page.c.line ?? "gray"

                Rectangle {
                    id: bar
                    width: parent.width * card.played
                    height: parent.height
                    radius: parent.radius
                    color: card.page.c.accent ?? "red"
                }
            }
        }
    }
}

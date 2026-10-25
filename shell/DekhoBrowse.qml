import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "lib/dekho.mjs" as D
import "lib/dekho-browse.mjs" as B
import "lib/dekho-toast.mjs" as Toast

// Dekho's Browse: the catalog under the filters each key sets, opened with the page it came from already chosen as chips.
FocusScope {
    id: page

    required property var dekho
    // The now-playing bar at its foot, for the state the checks read.
    property alias playingBar: nowBar

    readonly property var c: dekho.c
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property string voice: dekho.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property var words: B.browseText(voice)
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""
    // Paper's chip fill and the light text on its ink cursor, which no token carries.
    readonly property color chipFill: caps ? "#F3E6CF" : plain ? look.label.fill : Qt.alpha(c.accent ?? "cyan", 0.1)
    readonly property color onInk: caps ? "#D9CFBB" : c.surface ?? "white"

    property var filters: B.empty()
    property var tables: null
    property var results: []
    property int row: 0
    // Where Browse opened from, and whether that page's context chose the first chips.
    property string from: ""
    property bool prefilled: false
    // Each refresh counts up; an answer for an older count is dropped.
    property int asked: 0
    // The stack entry last loaded, so going back to Browse keeps its filters.
    property var loaded: null
    readonly property var entry: dekho.stack[dekho.stack.length - 1]

    property bool picking: false
    property var people: []
    property int pick: 0
    property string peopleAsked: ""

    onEntryChanged: if (entry.page === "browse" && entry.args !== loaded) {
        loaded = entry.args;
        load(entry.args || {});
    }

    // A title's context chooses its kind, genre and language once the tables can name them.
    function load(ctx) {
        from = D.title(ctx.from || "");
        prefilled = !!ctx.kind || !!ctx.person;
        picking = false;
        results = [];
        withTables(() => {
            const base = ctx.kind ? B.fromTitle(ctx, page.tables.languages) : B.empty();
            page.filters = ctx.person ? B.withPerson(base, ctx.person) : base;
            page.refresh();
        });
    }

    // The genres of both kinds and the languages, asked once.
    function withTables(then) {
        if (tables)
            return then();
        const got = {};
        const landed = (name, answer) => {
            got[name] = answer && Array.isArray(answer.items) ? answer.items : [];
            if (Object.keys(got).length < 3)
                return;
            page.tables = {
                genres: {
                    movie: got.movie,
                    tv: got.tv
                },
                languages: got.languages
            };
            then();
        };
        dekho.api(["api", "genres", "--kind", "movie"], a => landed("movie", a));
        dekho.api(["api", "genres", "--kind", "tv"], a => landed("tv", a));
        dekho.api(["api", "languages"], a => landed("languages", a));
    }

    function refresh() {
        const n = ++asked;
        const list = B.calls(filters, tables.genres);
        const sort = filters.sort;
        const answers = [];
        let left = list.length;
        results = [];
        row = 0;
        resultView.contentY = 0;
        list.forEach((args, i) => {
            dekho.api(args, answer => {
                if (page.asked !== n)
                    return;
                answers[i] = answer && Array.isArray(answer.items) ? answer.items : [];
                if (--left > 0)
                    return;
                page.results = B.merge(answers, sort);
                page.dekho.prefetch("w342", page.results.map(h => h.poster));
            });
        });
    }

    function set(f) {
        filters = f;
        refresh();
    }

    function move(by) {
        row = Math.max(0, Math.min(results.length - 1, row + by));
        const r = resultRows.itemAt(row);
        if (!r)
            return;
        if (r.y < resultView.contentY)
            resultView.contentY = r.y;
        else if (r.y + r.height > resultView.contentY + resultView.height)
            resultView.contentY = r.y + r.height - resultView.height;
    }

    function openPicker() {
        picking = true;
        people = [];
        pick = 0;
        peopleAsked = "";
        personField.text = "";
        personField.forceActiveFocus();
    }

    function closePicker() {
        picking = false;
        resultKeys.forceActiveFocus();
    }

    function findPeople(text) {
        const words = D.title(text);
        peopleAsked = words;
        pick = 0;
        if (!words) {
            people = [];
            return;
        }
        dekho.api(["api", "people"].concat(words.split(" ")), answer => {
            if (page.peopleAsked === words)
                page.people = answer && Array.isArray(answer.items) ? answer.items.slice(0, 6) : [];
        });
    }

    // Enter on a person only adds the filter; their own page is a later key's.
    function choosePerson() {
        const p = people[pick];
        if (!p)
            return;
        closePicker();
        const f = B.withPerson(filters, p);
        set(f);
        dekho.toast(Toast.filterToast(f, "person"));
    }

    function drawnList(repeater) {
        const out = [];
        for (let i = 0; i < repeater.count; i++)
            out.push(repeater.itemAt(i).drawn());
        return out;
    }

    function state() {
        return {
            browse: {
                from: fromText.text,
                prefilled: prefilledText.visible ? prefilledText.text : "",
                kinds: drawnList(kindTabs),
                summary: summaryText.text,
                count: countText.text,
                facets: drawnList(facetBoxes),
                chips: drawnList(chipRow),
                rows: drawnList(resultRows),
                cursor: row,
                filters: filters,
                picker: {
                    open: picker.visible,
                    text: personField.text,
                    people: drawnList(personRows)
                },
                look: {
                    pageFont: pageName.font.family,
                    chipRadius: chipRow.count ? chipRow.itemAt(0).radius : -1,
                    chipFill: String(chipFill),
                    kindRadius: kindTabs.count ? kindTabs.itemAt(0).radius : -1,
                    ruleDashed: headRule.dashed
                }
            }
        };
    }

    Item {
        id: resultKeys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text;
            const facet = {
                t: "kind",
                s: "sort",
                g: "genre",
                l: "language",
                d: "decade",
                r: "rating"
            }[t];
            if (k === Qt.Key_Escape)
                page.dekho.back();
            else if (!page.tables)
                return;
            else if (facet) {
                const f = B.next(page.filters, facet, page.tables);
                page.set(f);
                page.dekho.toast(Toast.filterToast(f, facet));
            }
            else if (t === "p")
                page.openPicker();
            else if (t === "x") {
                page.prefilled = false;
                page.set(B.clear());
                page.dekho.toast(Toast.FILTERS_CLEARED);
            } else if (t === "j" || k === Qt.Key_Down)
                page.move(1);
            else if (t === "k" || k === Qt.Key_Up)
                page.move(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                const hit = page.results[page.row];
                if (hit)
                    page.dekho.openTitle(hit);
            } else
                return;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The header as Home draws it, with where Browse came from on the right.
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
                    font.family: page.bodyFont
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
                font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                font.pixelSize: caps ? 18 : plain ? 14 : 12
                font.weight: caps ? Font.Normal : Font.Bold
            }
            Item {
                Layout.fillWidth: true
            }
            Rectangle {
                Layout.maximumWidth: 400
                implicitWidth: fromText.implicitWidth + (plain ? 18 : 0)
                implicitHeight: fromText.implicitHeight + (plain ? 6 : 0)
                radius: 8
                color: plain ? look.tile.fill : "transparent"

                Text {
                    id: fromText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - (plain ? 18 : 0))
                    textFormat: Text.PlainText
                    text: page.from ? words.from(page.from) : ""
                    color: c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: bracket ? 10 : 11
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.letterSpacing: bracket ? 1.4 : 0
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Rule {
            id: headRule
            Layout.fillWidth: true
            dashed: bracket
            color: caps ? c.ink ?? "black" : c.line ?? "gray"
        }

        // t: the kind as three tabs, then the filters in a line and the count.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.topMargin: 14
            Layout.bottomMargin: 10
            spacing: 12

            KeyMark {
                key: "t"
            }
            Row {
                spacing: 6

                Repeater {
                    id: kindTabs
                    model: B.KINDS

                    Rectangle {
                        id: kindTab
                        required property var modelData
                        readonly property bool current: page.filters.kind === modelData
                        function drawn() {
                            return {
                                text: kindText.text,
                                current: current
                            };
                        }
                        implicitWidth: kindText.implicitWidth + (current && page.bracket ? 28 : 24)
                        implicitHeight: kindText.implicitHeight + (current && page.bracket ? 12 : 10)
                        radius: page.plain ? 10 : 0
                        color: page.plain ? (current ? page.look.label.fill : page.look.tile.fill) : current ? (page.bracket ? page.c.accent : page.c.ink) ?? "black" : "transparent"
                        border.width: page.plain || current ? 0 : 1
                        border.color: (page.bracket ? page.c.line : page.c.ink) ?? "black"

                        Text {
                            id: kindText
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: kindTab.current && page.caps ? B.kindName(kindTab.modelData).toUpperCase() : page.words.kind(kindTab.modelData)
                            color: (kindTab.current ? (page.plain ? "#2638C9" : page.c.surface) : page.c.muted) ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: kindTab.current && page.caps ? 10 : kindTab.current && page.bracket ? 11 : 12
                            font.weight: kindTab.current && !page.caps ? (page.plain ? Font.Medium : Font.Bold) : Font.Normal
                            font.letterSpacing: kindTab.current && !page.plain ? 1.4 : page.bracket ? 0.7 : 0
                        }
                    }
                }
            }
            Text {
                id: summaryText
                Layout.leftMargin: 8
                Layout.maximumWidth: 640
                textFormat: Text.PlainText
                text: B.summary(page.filters)
                color: c.ink ?? "black"
                font.family: page.bodyFont
                font.pixelSize: plain ? 13 : 12
                font.weight: Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                id: countText
                textFormat: Text.PlainText
                text: words.count(page.results.length)
                color: c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: 12
                font.letterSpacing: bracket ? 0.7 : 0
            }
            Item {
                Layout.fillWidth: true
            }
        }

        // The facets, each with its key and what it is set to; p's box marks the picker while it is open.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 10
            spacing: 8

            Repeater {
                id: facetBoxes
                model: B.facets(page.filters)

                Rectangle {
                    id: facetBox
                    required property var modelData
                    readonly property bool open: modelData[0] === "p" && page.picking
                    function drawn() {
                        return {
                            key: facetKey.text,
                            name: facetName.text,
                            value: facetValue.text,
                            open: open
                        };
                    }
                    implicitWidth: facetRow.implicitWidth + 20
                    implicitHeight: facetRow.implicitHeight + (page.plain ? 12 : 14)
                    Layout.maximumWidth: 220
                    clip: true
                    radius: page.plain ? 10 : 0
                    color: open ? (page.plain ? page.look.label.fill : page.bracket ? page.c.accent : page.c.ink) ?? "black" : page.plain ? "#F6F7F9" : "transparent"
                    border.width: page.plain ? (open ? 1.5 : 0) : 1
                    border.color: (page.plain ? page.c.accent : page.bracket ? (open ? page.c.surface : page.c.line) : open ? page.c.ink : page.c.muted) ?? "gray"

                    Row {
                        id: facetRow
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        KeyMark {
                            id: facetKey
                            key: facetBox.modelData[0]
                            inverse: facetBox.open && !page.plain
                        }
                        Text {
                            id: facetName
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: facetBox.modelData[1]
                            color: facetBox.open && !page.plain ? (page.caps ? page.onInk : page.c.surface) : page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                        }
                        Text {
                            id: facetValue
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 120)
                            textFormat: Text.PlainText
                            text: facetBox.open ? page.words.typing : facetBox.modelData[2]
                            color: facetBox.open ? (page.plain ? "#2638C9" : page.c.surface) ?? "white" : page.c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
            Text {
                textFormat: Text.PlainText
                text: words.clear
                color: c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: bracket ? 10 : 11
                font.letterSpacing: bracket ? 1.4 : 0
            }
        }

        // The active filters as chips, and the page that chose them.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 12
            Layout.preferredHeight: 26
            spacing: 8

            Text {
                textFormat: Text.PlainText
                text: words.active
                color: c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: plain ? 11 : 10
                font.letterSpacing: plain ? 0 : 1.4
            }
            Repeater {
                id: chipRow
                model: B.chips(page.filters)

                Rectangle {
                    required property var modelData
                    function drawn() {
                        return {
                            text: chipText.text,
                            lines: chipText.lineCount,
                            elided: chipText.truncated
                        };
                    }
                    implicitWidth: chipText.width + 12 + 8 + 18 + 6
                    implicitHeight: 26
                    radius: page.plain ? 13 : 0
                    color: page.chipFill

                    Text {
                        id: chipText
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 200)
                        textFormat: Text.PlainText
                        text: modelData
                        color: (page.plain ? "#2638C9" : page.c.ink) ?? "black"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: page.plain ? 9 : 0
                        color: page.c.surface ?? "white"

                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: "×"
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: page.bracket ? 10 : 11
                        }
                    }
                }
            }
            Rectangle {
                Layout.leftMargin: 8
                Layout.maximumWidth: 360
                visible: page.prefilled && page.from !== ""
                implicitWidth: prefilledText.implicitWidth + (page.bracket ? 0 : page.plain ? 18 : 12)
                implicitHeight: prefilledText.implicitHeight + (page.bracket ? 0 : page.plain ? 6 : 2)
                radius: plain ? 8 : 0
                color: plain ? look.tile.fill : "transparent"
                border.width: caps ? 1 : 0
                border.color: c.ink ?? "black"

                Text {
                    id: prefilledText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - (page.bracket ? 0 : page.plain ? 18 : 12))
                    visible: parent.visible
                    textFormat: Text.PlainText
                    text: page.caps ? page.words.prefilled(page.from).toUpperCase() : page.words.prefilled(page.from)
                    color: (bracket ? c.accent : c.ink) ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: plain ? 11 : 10
                    font.weight: plain ? Font.Medium : bracket ? Font.Bold : Font.Normal
                    font.letterSpacing: plain ? 0 : 1.2
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }

        Rule {
            Layout.fillWidth: true
            dashed: bracket
            color: caps ? c.ink ?? "black" : c.line ?? "gray"
        }

        // The results under their column heads.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 0

            Columns {
                Layout.fillWidth: true
                implicitHeight: 30
                head: true
                cells: page.words.columns
            }
            Rule {
                Layout.fillWidth: true
                visible: !plain
                dashed: bracket
                color: (bracket ? c.line : "#D8CDB6") ?? "gray"
            }

            Flickable {
                id: resultView
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: resultColumn.implicitHeight
                interactive: false
                clip: true

                Column {
                    id: resultColumn
                    width: resultView.width

                    Repeater {
                        id: resultRows
                        model: page.results

                        Rectangle {
                            id: resultRow
                            required property var modelData
                            required property int index
                            readonly property bool cursor: page.row === index
                            function drawn() {
                                const at = resultRow.mapToItem(resultView, 0, 0);
                                return {
                                    title: rowCells.text(1),
                                    year: rowCells.text(2),
                                    rating: rowCells.text(3),
                                    language: rowCells.text(4),
                                    genres: rowCells.text(5),
                                    lines: rowCells.lines(1),
                                    elided: rowCells.elided(1),
                                    cursor: cursor,
                                    poster: rowCells.picture(),
                                    shown: at.y >= -0.5 && at.y + resultRow.height <= resultView.height + 0.5
                                };
                            }
                            width: resultColumn.width
                            implicitHeight: page.plain ? 44 : 46
                            radius: page.plain ? 10 : 0
                            color: cursor ? (page.plain ? page.look.label.fill : page.bracket ? page.c.accent : page.c.ink) ?? "black" : "transparent"
                            border.width: cursor && page.plain ? 1.5 : 0
                            border.color: page.c.accent ?? "blue"

                            Columns {
                                id: rowCells
                                anchors.fill: parent
                                path: resultRow.modelData.poster
                                inverse: resultRow.cursor && !page.plain
                                lit: resultRow.cursor && page.plain
                                cells: [D.title(resultRow.modelData.title), String(resultRow.modelData.year || ""), D.stars(resultRow.modelData.vote)].concat(page.words.hitCells(resultRow.modelData))
                            }
                        }
                    }
                }
            }
        }

        Rule {
            Layout.fillWidth: true
            dashed: bracket
            color: caps ? c.ink ?? "black" : c.line ?? "gray"
        }

        // While a film plays, the now-playing bar takes the keys' place.
        DekhoBar {
            id: nowBar
            Layout.fillWidth: true
            dekho: page.dekho
        }

        // The keys, as Home strips them.
        Flow {
            Layout.fillWidth: true
            visible: page.dekho.nowPlaying === null
            Layout.leftMargin: plain ? 14 : 16
            Layout.rightMargin: plain ? 14 : 16
            Layout.topMargin: plain ? 10 : 11
            Layout.bottomMargin: plain ? 10 : 11
            spacing: plain ? 8 : 16

            Repeater {
                model: page.look.keys(page.words.keys)

                KeyPair {}
            }
        }
    }

    // p's picker: a person found by name as it is typed, j and k by the arrows, Enter adds them as a filter.
    Rectangle {
        id: picker
        x: parent.width - width - 20
        y: 140
        width: 300
        height: pickerColumn.implicitHeight
        visible: page.picking
        radius: page.plain ? 14 : 0
        color: page.c.surface ?? "white"
        border.width: page.plain ? 1.5 : page.caps ? 1.5 : 1
        border.color: (page.plain || page.bracket ? page.c.accent : page.c.ink) ?? "black"
        clip: true

        ColumnLayout {
            id: pickerColumn
            width: parent.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 12
                spacing: 8

                Rectangle {
                    implicitWidth: personLabel.implicitWidth + (page.bracket ? 0 : page.plain ? 18 : 14)
                    implicitHeight: personLabel.implicitHeight + (page.bracket ? 0 : 4)
                    radius: page.plain ? 8 : 0
                    color: page.plain ? page.look.label.fill : page.caps ? page.c.ink ?? "black" : "transparent"

                    Text {
                        id: personLabel
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: page.caps ? "PERSON" : page.words.person
                        color: (page.plain || page.bracket ? page.c.accent : page.c.surface) ?? "white"
                        font.family: page.bodyFont
                        font.pixelSize: page.plain ? 12 : 10
                        font.weight: page.plain ? Font.Medium : page.bracket ? Font.Bold : Font.Normal
                        font.letterSpacing: page.plain ? 0 : 1.4
                    }
                }
                TextInput {
                    id: personField
                    Layout.fillWidth: true
                    clip: true
                    color: page.c.ink ?? "black"
                    selectionColor: page.c.accent ?? "red"
                    selectedTextColor: page.c.surface ?? "white"
                    font.family: page.bodyFont
                    font.pixelSize: page.plain ? 14 : 13
                    onTextChanged: if (page.picking)
                        page.findPeople(text)
                    Keys.onPressed: event => {
                        const k = event.key;
                        if (k === Qt.Key_Escape)
                            page.closePicker();
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                            page.choosePerson();
                        else if (k === Qt.Key_Down)
                            page.pick = Math.min(page.people.length - 1, page.pick + 1);
                        else if (k === Qt.Key_Up)
                            page.pick = Math.max(0, page.pick - 1);
                        else
                            return;
                        event.accepted = true;
                    }
                }
            }
            Rule {
                Layout.fillWidth: true
                dashed: page.bracket
                color: (page.plain ? "#E3E6EB" : page.bracket ? page.c.line : "#D8CDB6") ?? "gray"
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 6
                spacing: 2

                Repeater {
                    id: personRows
                    model: page.people

                    Rectangle {
                        id: personRow
                        required property var modelData
                        required property int index
                        readonly property bool cursor: page.pick === index
                        readonly property bool inverse: cursor && !page.plain
                        function drawn() {
                            return {
                                name: personName.text,
                                role: personRole.text,
                                lines: personName.lineCount,
                                cursor: cursor
                            };
                        }
                        Layout.fillWidth: true
                        implicitHeight: personText.implicitHeight + 16
                        radius: page.plain ? 10 : 0
                        color: cursor ? (page.plain ? page.look.label.fill : page.bracket ? page.c.accent : page.c.ink) ?? "black" : "transparent"

                        ColumnLayout {
                            id: personText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                id: personName
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: D.title(personRow.modelData.name)
                                color: (personRow.inverse ? page.c.surface : page.plain && personRow.cursor ? "#2638C9" : page.c.ink) ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: page.plain ? 14 : 13
                                font.weight: personRow.inverse && page.bracket ? Font.Bold : Font.Medium
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Text {
                                id: personRole
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.bracket ? B.roleText(personRow.modelData.known_for_department).toUpperCase() : B.roleText(personRow.modelData.known_for_department)
                                color: personRow.inverse ? (page.caps ? page.onInk : page.c.surface) : page.c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: page.bracket ? 10 : 11
                                font.letterSpacing: page.bracket ? 1.4 : 0
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }
                }
            }
            Rule {
                Layout.fillWidth: true
                dashed: page.bracket
                color: (page.plain ? "#E3E6EB" : page.bracket ? page.c.line : "#D8CDB6") ?? "gray"
            }
            Flow {
                Layout.fillWidth: true
                Layout.margins: 10
                spacing: page.plain ? 8 : 12

                Repeater {
                    model: page.look.keys(page.words.pick)

                    KeyPair {}
                }
            }
        }
    }

    // A key's letter in its small box, as each board marks a facet's key.
    component KeyMark: Rectangle {
        property string key: ""
        property bool inverse: false
        readonly property string text: keyText.text
        implicitWidth: keyText.implicitWidth + (page.plain ? 12 : 8)
        implicitHeight: keyText.implicitHeight + (page.plain ? 2 : 0)
        radius: page.plain ? 6 : 0
        color: page.plain ? (inverse ? page.c.surface : page.look.tile.fill) ?? "white" : "transparent"
        border.width: page.plain ? 0 : 1
        border.color: (inverse ? (page.caps ? page.onInk : page.c.surface) : page.c.muted) ?? "gray"

        Text {
            id: keyText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: page.plain ? parent.key : parent.key.toUpperCase()
            color: (parent.inverse ? (page.caps ? page.onInk : page.c.surface) : page.c.muted) ?? "gray"
            font.family: page.bodyFont
            font.pixelSize: page.plain ? 11 : 10
            font.weight: page.plain ? Font.Medium : Font.Normal
            font.letterSpacing: page.plain ? 0 : 1.2
        }
    }

    // A row's cells: the poster's place, the title, its year, rating, language and genres, as the board's grid lays them.
    component Columns: Item {
        id: columns
        property var cells: []
        // The poster's path in the hit this row draws; the column heads have none.
        property var path: null
        property bool head: false
        property bool inverse: false
        property bool lit: false
        readonly property color soft: inverse ? page.onInk : page.c.muted ?? "gray"

        function picture() {
            return poster.drawn();
        }
        function text(i) {
            return [null, titleCell, yearCell, ratingCell, languageCell, genresCell][i].text;
        }
        function lines(i) {
            return [null, titleCell, yearCell, ratingCell, languageCell, genresCell][i].lineCount;
        }
        function elided(i) {
            return [null, titleCell, yearCell, ratingCell, languageCell, genresCell][i].truncated;
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            Item {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 34

                Rectangle {
                    visible: !columns.head
                    width: 24
                    height: 34
                    radius: page.plain ? 6 : 0
                    color: page.plain ? (columns.lit ? page.c.surface : "#E9ECF1") ?? "white" : page.bracket ? page.c.surface ?? "black" : "transparent"
                    border.width: page.plain ? 0 : 1
                    border.color: (page.bracket ? (columns.inverse ? page.c.surface : page.c.line) : page.c.muted) ?? "gray"
                    clip: true

                    Shape {
                        anchors.fill: parent
                        visible: page.caps
                        preferredRendererType: Shape.GeometryRenderer

                        ShapePath {
                            strokeColor: "#D8CDB6"
                            strokeWidth: 1
                            fillColor: "transparent"
                            PathSvg {
                                path: "M6 0L0 6M12 0L0 12M18 0L0 18M24 0L0 24M24 6L0 30M24 12L0 36M24 18L4 38M24 24L10 38M24 30L16 38"
                            }
                        }
                    }
                    DekhoPicture {
                        id: poster
                        anchors.fill: parent
                        dekho: page.dekho
                        size: "w342"
                        path: columns.path
                        radius: parent.radius
                    }
                }
            }
            Text {
                id: titleCell
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: columns.cells[0] ?? ""
                color: columns.head ? page.c.muted ?? "gray" : columns.inverse ? page.c.surface ?? "white" : columns.lit ? "#2638C9" : page.c.ink ?? "black"
                font.family: page.bodyFont
                font.pixelSize: columns.head ? (page.caps ? 10 : 11) : page.plain ? 14 : 13
                font.weight: columns.head ? Font.Normal : columns.inverse && page.bracket ? Font.Bold : Font.Medium
                font.letterSpacing: columns.head && !page.plain ? 1.4 : 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                id: yearCell
                Layout.preferredWidth: 70
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: columns.cells[1] ?? ""
                color: columns.soft
                font.family: page.bodyFont
                font.pixelSize: columns.head ? (page.caps ? 10 : 11) : 12
                font.letterSpacing: columns.head && !page.plain ? 1.4 : page.bracket ? 0.7 : 0
            }
            Text {
                id: ratingCell
                Layout.preferredWidth: 70
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: columns.cells[2] ?? ""
                color: columns.soft
                font.family: page.bodyFont
                font.pixelSize: columns.head ? (page.caps ? 10 : 11) : 12
                font.letterSpacing: columns.head && !page.plain ? 1.4 : page.bracket ? 0.7 : 0
            }
            Text {
                id: languageCell
                Layout.preferredWidth: 110
                textFormat: Text.PlainText
                text: columns.cells[3] ?? ""
                color: columns.soft
                font.family: page.bodyFont
                font.pixelSize: columns.head ? (page.caps ? 10 : 11) : 12
                font.letterSpacing: columns.head && !page.plain ? 1.4 : page.bracket ? 0.7 : 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                id: genresCell
                Layout.preferredWidth: 180
                textFormat: Text.PlainText
                text: columns.cells[4] ?? ""
                color: columns.soft
                font.family: page.bodyFont
                font.pixelSize: columns.head ? (page.caps ? 10 : 11) : 12
                font.letterSpacing: columns.head && !page.plain ? 1.4 : page.bracket ? 0.7 : 0
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    // One key and its word in the strip at the foot.
    component KeyPair: Rectangle {
        required property var modelData
        implicitWidth: keyPair.implicitWidth + (page.plain ? 14 : 0)
        implicitHeight: keyPair.implicitHeight + (page.plain ? 6 : 0)
        radius: 6
        color: page.plain ? page.look.tile.fill : "transparent"

        Row {
            id: keyPair
            anchors.centerIn: parent
            spacing: page.bracket ? 8 : 6

            Text {
                textFormat: Text.PlainText
                text: modelData.key
                color: (page.bracket ? page.c.accent : page.c.ink) ?? "black"
                font.family: page.bodyFont
                font.pixelSize: page.caps ? 10 : 11
                font.weight: page.plain ? Font.Medium : Font.Bold
                font.letterSpacing: page.caps ? 1 : page.bracket ? 1.5 : 0
            }
            Text {
                textFormat: Text.PlainText
                text: modelData.word
                color: page.c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: page.caps ? 10 : 11
                font.letterSpacing: page.caps ? 1 : page.bracket ? 1.5 : 0
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
}

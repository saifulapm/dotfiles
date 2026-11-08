import QtQuick
import QtQuick.Layouts
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
    readonly property var tones: dekho.tones
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property var words: B.browseText()
    readonly property string bodyFont: fonts.ui ?? ""
    readonly property color chipFill: look.label.fill

    property var filters: B.empty()
    property var tables: null
    property var results: []
    property int row: 0
    // Where Browse opened from, and whether that page's context chose the first chips.
    property string from: ""
    property bool prefilled: false
    // Each refresh counts up; an answer for an older count is dropped.
    property int asked: 0
    // Each kind's page and total_pages as its last answer gave them, and whether the next page is on its way.
    property var pages: ({})
    property bool loading: false
    readonly property bool moreShown: !B.done(pages)
    readonly property var moreKey: look.keys([words.more])[0]
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
        pages = {};
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
        pages = {};
        loading = false;
        row = 0;
        resultView.contentY = 0;
        list.forEach((args, i) => {
            dekho.api(args, answer => {
                if (page.asked !== n)
                    return;
                answers[i] = answer;
                if (--left > 0)
                    return;
                page.results = B.merge(answers.map(a => a && Array.isArray(a.items) ? a.items : []), sort);
                page.pages = list.reduce((p, a, j) => B.landed(p, a[3], answers[j]), {});
                page.dekho.prefetch("w342", page.results.map(h => h.poster));
            });
        });
    }

    // The next page of each kind that has one, merged as page 1 is and put under the rows; one at a time, and dropped once a refresh has come since.
    function more() {
        if (loading || B.done(pages))
            return;
        const n = asked;
        const list = B.nextCalls(filters, tables.genres, pages);
        const sort = filters.sort;
        const answers = [];
        let left = list.length;
        loading = true;
        list.forEach((args, i) => {
            dekho.api(args, answer => {
                if (page.asked !== n)
                    return;
                answers[i] = answer;
                if (--left > 0)
                    return;
                const hits = B.merge(answers.map(a => a && Array.isArray(a.items) ? a.items : []), sort);
                page.pages = list.reduce((p, a, j) => B.landed(p, a[3], answers[j]), page.pages);
                page.results = B.appended(page.results, hits);
                page.loading = false;
                page.dekho.prefetch("w342", hits.map(h => h.poster));
            });
        });
    }

    function set(f) {
        filters = f;
        refresh();
    }

    // The cursor can stand on load more, one past the last row; reaching the last row asks the next page.
    function move(by) {
        row = Math.max(0, Math.min(results.length - (moreShown ? 0 : 1), row + by));
        if (row === results.length - 1)
            more();
        const r = row < results.length ? resultRows.itemAt(row) : moreRow;
        if (!r)
            return;
        if (r.y < resultView.contentY)
            resultView.contentY = r.y;
        else if (r.y + r.height > resultView.contentY + resultView.height)
            resultView.contentY = r.y + r.height - resultView.height;
    }

    // Enter on the cursor's row opens its title, and on load more asks the next page.
    function enter() {
        if (row === results.length)
            return more();
        const hit = results[row];
        if (hit)
            dekho.openTitle(hit);
    }

    // A click on a row moves the cursor there and does what Enter does; the picker, if open beside it, closes, as a facet's click closes it.
    function pickRow(at) {
        picking = false;
        row = at;
        move(0);
        resultKeys.forceActiveFocus();
        enter();
    }

    // A facet's key: its next value, with the toast that names it.
    function cycle(facet) {
        const f = B.next(filters, facet, tables);
        set(f);
        dekho.toast(Toast.filterToast(f, facet));
    }

    // A click on a facet does what its key does, the person facet opening the picker. Like the keys, it waits for the tables.
    function tapFacet(facet) {
        if (!tables)
            return;
        picking = false;
        resultKeys.forceActiveFocus();
        if (facet === "person")
            openPicker();
        else
            cycle(facet);
    }

    // A click on a kind tab picks that kind, where t reaches it by cycling.
    function tapKind(kind) {
        if (!tables || filters.kind === kind)
            return;
        picking = false;
        resultKeys.forceActiveFocus();
        const f = B.withKind(filters, kind, tables);
        set(f);
        dekho.toast(Toast.filterToast(f, "kind"));
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

    // A click on a person picks them as Enter does.
    function pickPerson(at) {
        pick = at;
        choosePerson();
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
                more: moreRow.drawn(),
                loading: loading,
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
                    kindRadius: kindTabs.count ? kindTabs.itemAt(0).radius : -1
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
            else if (facet)
                page.cycle(facet);
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
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                page.enter();
            else
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
            Layout.preferredHeight: 52
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            spacing: 12

            Rectangle {
                implicitWidth: labelText.implicitWidth + 18
                implicitHeight: labelText.implicitHeight + 6
                radius: 8
                color: look.label.fill

                Text {
                    id: labelText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.label
                    color: look.label.color ?? "blue"
                    font.family: page.bodyFont
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
            Text {
                id: pageName
                textFormat: Text.PlainText
                text: words.page
                color: c.ink ?? "black"
                font.family: page.bodyFont
                font.pixelSize: 14
                font.weight: Font.Bold
            }
            Item {
                Layout.fillWidth: true
            }
            Rectangle {
                Layout.maximumWidth: 400
                implicitWidth: fromText.implicitWidth + 18
                implicitHeight: fromText.implicitHeight + 6
                radius: 8
                color: look.tile.fill

                Text {
                    id: fromText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 18)
                    textFormat: Text.PlainText
                    text: page.from ? words.from(page.from) : ""
                    color: c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Rule {
            Layout.fillWidth: true
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
                        implicitWidth: kindText.implicitWidth + 24
                        implicitHeight: kindText.implicitHeight + 10
                        radius: 10
                        color: current ? page.look.label.fill : page.look.tile.fill

                        Text {
                            id: kindText
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: page.words.kind(kindTab.modelData)
                            color: (kindTab.current ? page.tones.deep : page.c.muted) ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.weight: kindTab.current ? Font.Medium : Font.Normal
                        }
                        Click {
                            name: "browse-kind:" + kindTab.modelData
                            onTapped: page.tapKind(kindTab.modelData)
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
                font.pixelSize: 13
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
                    implicitHeight: facetRow.implicitHeight + 12
                    Layout.maximumWidth: 220
                    clip: true
                    radius: 10
                    color: open ? page.look.label.fill : page.tones.field
                    border.width: open ? 1.5 : 0
                    border.color: page.c.accent ?? "gray"

                    Row {
                        id: facetRow
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        KeyMark {
                            id: facetKey
                            key: facetBox.modelData[0]
                        }
                        Text {
                            id: facetName
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: facetBox.modelData[1]
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                        }
                        Text {
                            id: facetValue
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 120)
                            textFormat: Text.PlainText
                            text: facetBox.open ? page.words.typing : facetBox.modelData[2]
                            color: facetBox.open ? page.tones.deep : page.c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                    // Named by the facet's own word, the one the toast and the key's cycle go by.
                    Click {
                        name: "browse-facet:" + facetBox.modelData[1].toLowerCase()
                        onTapped: page.tapFacet(facetBox.modelData[1].toLowerCase())
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
                font.pixelSize: 11
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
                font.pixelSize: 11
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
                    radius: 13
                    color: page.chipFill

                    Text {
                        id: chipText
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 200)
                        textFormat: Text.PlainText
                        text: modelData
                        color: page.tones.deep
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
                        radius: 9
                        color: page.c.surface ?? "white"

                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: "×"
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 11
                        }
                    }
                }
            }
            Rectangle {
                Layout.leftMargin: 8
                Layout.maximumWidth: 360
                visible: page.prefilled && page.from !== ""
                implicitWidth: prefilledText.implicitWidth + 18
                implicitHeight: prefilledText.implicitHeight + 6
                radius: 8
                color: look.tile.fill

                Text {
                    id: prefilledText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 18)
                    visible: parent.visible
                    textFormat: Text.PlainText
                    text: page.words.prefilled(page.from)
                    color: c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
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

            Flickable {
                id: resultView
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: resultColumn.implicitHeight
                interactive: false
                clip: true

                // Under the rows, the wheel scrolls the results and leaves the cursor where it is.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: event => resultView.contentY = D.wheeled(resultView.contentY, event.angleDelta.y, resultView.contentHeight, resultView.height)
                }

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
                            implicitHeight: 44
                            radius: 10
                            color: cursor ? page.look.label.fill : "transparent"
                            border.width: cursor ? 1.5 : 0
                            border.color: page.c.accent ?? "blue"

                            Columns {
                                id: rowCells
                                anchors.fill: parent
                                path: resultRow.modelData.poster
                                lit: resultRow.cursor
                                cells: [D.title(resultRow.modelData.title), String(resultRow.modelData.year || ""), D.stars(resultRow.modelData.vote)].concat(page.words.hitCells(resultRow.modelData))
                            }
                            Click {
                                name: "browse-row:" + resultRow.index
                                onTapped: page.pickRow(resultRow.index)
                            }
                        }
                    }

                    // Under the rows while a page is left: load more, a row the cursor stands on, written as the keys strip writes ↵ and its word.
                    Rectangle {
                        id: moreRow
                        readonly property bool cursor: page.row === page.results.length
                        function drawn() {
                            const at = moreRow.mapToItem(resultView, 0, 0);
                            return {
                                shown: moreRow.visible,
                                text: moreKeyText.text + " " + moreWordText.text,
                                cursor: cursor,
                                inView: moreRow.visible && at.y >= -0.5 && at.y + moreRow.height <= resultView.height + 0.5
                            };
                        }
                        visible: page.moreShown
                        width: resultColumn.width
                        implicitHeight: 44
                        radius: 10
                        color: cursor ? page.look.label.fill : "transparent"
                        border.width: cursor ? 1.5 : 0
                        border.color: page.c.accent ?? "blue"

                        // Lined up with the titles, past the poster's place, in a grey key chip.
                        Rectangle {
                            x: 12 + 36 + 12
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: moreText.implicitWidth + 14
                            implicitHeight: moreText.implicitHeight + 6
                            radius: 6
                            color: page.look.tile.fill

                            Row {
                                id: moreText
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    id: moreKeyText
                                    textFormat: Text.PlainText
                                    text: page.moreKey.key
                                    color: page.c.ink ?? "black"
                                    font.family: page.bodyFont
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                                Text {
                                    id: moreWordText
                                    textFormat: Text.PlainText
                                    text: page.moreKey.word
                                    color: page.c.muted ?? "gray"
                                    font.family: page.bodyFont
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Click {
                            name: "browse-more"
                            onTapped: page.pickRow(page.results.length)
                        }
                    }
                }
            }
        }

        Rule {
            Layout.fillWidth: true
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
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 8

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
        radius: 14
        color: page.c.surface ?? "white"
        border.width: 1.5
        border.color: page.c.accent ?? "black"
        clip: true

        // The picker lies over rows with click areas of their own; neither a click nor the wheel on it goes on to them.
        MouseArea {
            anchors.fill: parent
            onWheel: event => event.accepted = true
        }

        ColumnLayout {
            id: pickerColumn
            width: parent.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 12
                spacing: 8

                Rectangle {
                    implicitWidth: personLabel.implicitWidth + 18
                    implicitHeight: personLabel.implicitHeight + 4
                    radius: 8
                    color: page.look.label.fill

                    Text {
                        id: personLabel
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: page.words.person
                        color: page.look.label.color ?? "white"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        font.weight: Font.Medium
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
                    font.pixelSize: 14
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
                color: page.tones.rule
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
                        radius: 10
                        color: cursor ? page.look.label.fill : "transparent"

                        Click {
                            name: "browse-person:" + personRow.index
                            onTapped: page.pickPerson(personRow.index)
                        }
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
                                color: (personRow.cursor ? page.tones.deep : page.c.ink) ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Text {
                                id: personRole
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: B.roleText(personRow.modelData.known_for_department)
                                color: page.c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }
                }
            }
            Rule {
                Layout.fillWidth: true
                color: page.tones.rule
            }
            Flow {
                Layout.fillWidth: true
                Layout.margins: 10
                spacing: 8

                Repeater {
                    model: page.look.keys(page.words.pick)

                    KeyPair {}
                }
            }
        }
    }

    // A key's letter in its small grey box, as a facet's key is marked.
    component KeyMark: Rectangle {
        property string key: ""
        readonly property string text: keyText.text
        implicitWidth: keyText.implicitWidth + 12
        implicitHeight: keyText.implicitHeight + 2
        radius: 6
        color: "transparent"

        Text {
            id: keyText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: parent.key
            color: page.c.muted ?? "gray"
            font.family: page.bodyFont
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }

    // A row's cells: the poster's place, the title, its year, rating, language and genres, as the board's grid lays them.
    component Columns: Item {
        id: columns
        property var cells: []
        // The poster's path in the hit this row draws; the column heads have none.
        property var path: null
        property bool head: false
        property bool lit: false
        readonly property color soft: page.c.muted ?? "gray"

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
                    radius: 6
                    color: (columns.lit ? page.c.surface : page.tones.thumb) ?? "white"
                    clip: true

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
                color: columns.head ? page.c.muted ?? "gray" : columns.lit ? page.tones.deep : page.c.ink ?? "black"
                font.family: page.bodyFont
                font.pixelSize: columns.head ? 11 : 14
                font.weight: columns.head ? Font.Normal : Font.Medium
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
                font.pixelSize: columns.head ? 11 : 12
            }
            Text {
                id: ratingCell
                Layout.preferredWidth: 70
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: columns.cells[2] ?? ""
                color: columns.soft
                font.family: page.bodyFont
                font.pixelSize: columns.head ? 11 : 12
            }
            Text {
                id: languageCell
                Layout.preferredWidth: 110
                textFormat: Text.PlainText
                text: columns.cells[3] ?? ""
                color: columns.soft
                font.family: page.bodyFont
                font.pixelSize: columns.head ? 11 : 12
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
                font.pixelSize: columns.head ? 11 : 12
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    // One key and its word in the strip at the foot.
    component KeyPair: Rectangle {
        required property var modelData
        implicitWidth: keyPair.implicitWidth + 14
        implicitHeight: keyPair.implicitHeight + 6
        radius: 6
        color: "transparent"

        Row {
            id: keyPair
            anchors.centerIn: parent
            spacing: 6

            Text {
                textFormat: Text.PlainText
                text: modelData.key
                color: page.c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            Text {
                textFormat: Text.PlainText
                text: modelData.word
                color: page.c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: 11
            }
        }
    }

    // A one-pixel rule, in the line colour unless told another.
    component Rule: Rectangle {
        implicitHeight: 1
        color: page.c.line ?? "gray"
    }
}

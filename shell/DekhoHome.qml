import QtQuick
import QtQuick.Layouts
import "lib/dekho.mjs" as D
import "lib/dekho-home.mjs" as H

// Dekho's Home: the search field over three rows of titles, continue watching, trending series and trending movies; a search's results take the rows' place.
FocusScope {
    id: home

    required property var dekho
    // The now-playing bar at its foot, for the state the checks read.
    property alias playingBar: nowBar

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
    // Set by the first key that moves the cursor; until then it follows the first row with titles.
    property bool moved: false
    // How each trending answer came: fresh, a stale copy the backend saved (dated by seriesSaved and moviesSaved), or an error with nothing to show.
    property string seriesKind: "fresh"
    property string moviesKind: "fresh"
    property var seriesSaved: null
    property var moviesSaved: null
    readonly property bool offline: seriesKind !== "fresh" || moviesKind !== "fresh"
    // The older of the saved rows' dates, for the notice.
    readonly property var savedFrom: seriesSaved && moviesSaved ? (seriesSaved < moviesSaved ? seriesSaved : moviesSaved) : seriesSaved || moviesSaved

    // Enter on a title to continue plays it from where it stopped, with no release list.
    signal resume(var item)

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
        moved = true;
        const names = rowNames;
        if (names.length === 0)
            return;
        const at = names.indexOf(row);
        row = names[((at < 0 ? 0 : at + by) % names.length + names.length) % names.length];
        col = Math.max(0, Math.min(itemsOf(row).length - 1, col));
        stripOf(row).reveal(col);
    }

    function moveCol(by) {
        moved = true;
        col = Math.max(0, Math.min(itemsOf(row).length - 1, col + by));
        stripOf(row).reveal(col);
    }

    // Enter on the cursor's card: a title to continue plays on, any other opens its title.
    function enter() {
        const item = itemsOf(row)[col];
        if (item && row === "continue")
            resume(item);
        else if (item)
            dekho.openTitle(item);
    }

    // A click on a card moves the cursor there and does what Enter does.
    function pick(name, at) {
        moved = true;
        row = name;
        col = at;
        stripOf(name).reveal(at);
        rowKeys.forceActiveFocus();
        enter();
    }

    // A trending answer: a stale copy is drawn marked with its date; an error leaves the rows as they are.
    function take(kind, answer) {
        const k = H.kindOfAnswer(answer);
        const saved = k === "stale" ? H.savedAt(answer, Date.now()) : null;
        if (kind === "tv") {
            seriesKind = k;
            seriesSaved = saved;
            if (k !== "error") {
                series = listOf(answer, 10);
                dekho.prefetch("w342", series.map(t => t.poster));
            }
        } else {
            moviesKind = k;
            moviesSaved = saved;
            if (k !== "error") {
                movies = listOf(answer, 10);
                dekho.prefetch("w342", movies.map(t => t.poster));
            }
        }
    }

    // Every home row is asked for again; r runs it, and a fresh answer replaces a saved one.
    function reload() {
        reloadHistory();
        dekho.api(["api", "trending", "--kind", "tv"], answer => home.take("tv", answer));
        dekho.api(["api", "trending", "--kind", "movie"], answer => home.take("movie", answer));
    }

    // Continue watching alone, as when a play ends.
    function reloadHistory() {
        dekho.api(["api", "history", "--limit", "20"], answer => {
            home.continued = home.listOf(answer, 20);
            home.dekho.prefetch("w342", home.continued.map(t => t.poster));
        });
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
            if (home.asked !== words)
                return;
            home.results = home.listOf(answer, 20);
            home.dekho.prefetch("w342", home.results.map(t => t.poster));
        });
    }

    function focusSearch() {
        if (!offline)
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
            marks: {
                continue: continueStrip.tailDrawn,
                series: seriesStrip.tailDrawn,
                movies: moviesStrip.tailDrawn
            },
            offline: {
                shown: notice.visible,
                notice: [noticeLead.text, noticeRest.text].filter(t => t).join(" "),
                retry: retryKey.text + " " + retryWord.text,
                keys: Array.from({
                    length: keyList.count
                }, (_, i) => keyList.itemAt(i).drawn()),
                search: {
                    text: searchOff.visible ? searchOff.text : "",
                    field: field.visible
                },
                look: {
                    noticeFill: notice.color.a > 0 ? String(notice.color) : "",
                    noticeRadius: notice.radius,
                    markFill: String(noticeMark.color),
                    markRadius: noticeMark.radius
                }
            },
            look: {
                homeFont: pageName.font.family,
                rowHead: continueStrip.headText,
                cardRadius: continueStrip.cardRadius,
                ruleDashed: headRule.dashed
            }
        };
    }

    Component.onCompleted: reload()

    // The trending rows land in either order, so the cursor follows the first row with titles until a key moves it.
    onRowNamesChanged: if (!searching)
        row = H.cursorRow(rowNames, row, moved)

    Item {
        id: rowKeys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text;
            if (t === "/")
                home.focusSearch();
            else if (t === "r" && home.offline)
                home.reload();
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
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                home.enter();
            else
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

        // With TMDB unreachable: Paper's ruled box with an ink mark, Artboard's peach block, Blueprint's accent-ruled box with an amber mark.
        Rectangle {
            id: notice
            Layout.fillWidth: true
            Layout.topMargin: 14
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            visible: home.offline
            implicitHeight: noticeRow.implicitHeight + 20
            radius: plain ? 12 : 0
            color: plain ? "#FFF1E8" : "transparent"
            border.width: plain ? 0 : 1
            border.color: (bracket ? c.accent : c.ink) ?? "black"

            RowLayout {
                id: noticeRow
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                Rectangle {
                    id: noticeMark
                    implicitWidth: 18
                    implicitHeight: 18
                    radius: plain ? 9 : 0
                    color: (plain ? "#B4380B" : bracket ? c.danger : c.ink) ?? "black"

                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "!"
                        color: (plain ? "white" : c.surface) ?? "white"
                        font.family: home.bodyFont
                        font.pixelSize: bracket ? 10 : 11
                        font.weight: Font.Bold
                    }
                }
                Text {
                    id: noticeLead
                    textFormat: Text.PlainText
                    text: words.unreachable
                    color: (plain ? "#B4380B" : c.ink) ?? "black"
                    font.family: home.bodyFont
                    font.pixelSize: plain ? 13 : 12
                    font.weight: Font.Bold
                }
                Text {
                    id: noticeRest
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: words.showing(home.savedFrom)
                    color: (plain ? "#B4380B" : c.ink) ?? "black"
                    font.family: home.bodyFont
                    font.pixelSize: plain ? 13 : 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Row {
                    spacing: 5

                    Text {
                        id: retryKey
                        textFormat: Text.PlainText
                        text: words.retry[0]
                        color: (bracket ? c.accent : plain ? "#B4380B" : c.ink) ?? "black"
                        font.family: home.bodyFont
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: bracket ? 0.72 : 0
                    }
                    Text {
                        id: retryWord
                        textFormat: Text.PlainText
                        text: words.retry[1]
                        color: (plain ? "#B4380B" : c.ink) ?? "black"
                        font.family: home.bodyFont
                        font.pixelSize: 12
                        font.letterSpacing: bracket ? 0.72 : 0
                    }
                }
            }
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
            border.color: (bracket ? c.line : home.offline && voice === "caps" ? c.ink : c.muted) ?? "gray"

            // Search is off while TMDB is unreachable: the box says so in the field's place.
            Text {
                id: searchOff
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: home.offline
                textFormat: Text.PlainText
                text: words.searchOff
                color: c.muted ?? "gray"
                font.family: home.bodyFont
                font.pixelSize: plain ? 14 : 13
            }
            FilesIcon {
                id: searchIcon
                visible: !home.offline
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
                // A click focuses the field as / does; the name is for the checks' `dekho box`.
                objectName: "click:search"
                visible: !home.offline
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
                visible: !home.offline
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

            DekhoStrip {
                id: continueStrip
                Layout.fillWidth: true
                page: home
                name: "continue"
                cursor: home.row === name ? home.col : -1
                progressed: true
                onPicked: at => home.pick(name, at)
                items: home.continued
                headText: words.continue
                tailText: home.offline ? words.machine : String(home.continued.length)
            }
            DekhoStrip {
                id: seriesStrip
                Layout.fillWidth: true
                page: home
                name: "series"
                cursor: home.row === name ? home.col : -1
                onPicked: at => home.pick(name, at)
                items: home.series
                headText: words.series
                tailText: home.seriesSaved ? words.saved(home.seriesSaved) : words.week
            }
            DekhoStrip {
                id: moviesStrip
                Layout.fillWidth: true
                page: home
                name: "movies"
                cursor: home.row === name ? home.col : -1
                onPicked: at => home.pick(name, at)
                items: home.movies
                headText: words.movies
                tailText: home.moviesSaved ? words.saved(home.moviesSaved) : words.week
            }
        }

        DekhoStrip {
            id: resultsStrip
            Layout.fillWidth: true
            Layout.margins: 18
            Layout.topMargin: 16
            visible: home.searching
            page: home
            name: "results"
            cursor: home.row === name ? home.col : -1
            onPicked: at => home.pick(name, at)
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

        // While a film plays, the now-playing bar takes the keys' place.
        DekhoBar {
            id: nowBar
            Layout.fillWidth: true
            dekho: home.dekho
        }

        // The keys, as each board strips them: Paper's tracked caps, Artboard's grey chips, Blueprint's bracketed accent keys.
        Flow {
            Layout.fillWidth: true
            visible: home.dekho.nowPlaying === null
            Layout.leftMargin: plain ? 14 : 16
            Layout.rightMargin: plain ? 14 : 16
            Layout.topMargin: plain ? 10 : 11
            Layout.bottomMargin: plain ? 10 : 11
            spacing: plain ? 8 : 16

            Repeater {
                id: keyList
                model: home.look.keys(home.offline ? home.words.offlineKeys : home.words.keys)

                Rectangle {
                    required property var modelData

                    function drawn() {
                        return [keyName.text, keyWord.text];
                    }
                    implicitWidth: keyPair.implicitWidth + (home.plain ? 14 : 0)
                    implicitHeight: keyPair.implicitHeight + (home.plain ? 6 : 0)
                    radius: 6
                    color: home.plain ? home.look.tile.fill : "transparent"

                    Row {
                        id: keyPair
                        anchors.centerIn: parent
                        spacing: home.bracket ? 8 : 6

                        Text {
                            id: keyName
                            textFormat: Text.PlainText
                            text: modelData.key
                            color: (home.bracket ? home.c.accent : home.c.ink) ?? "black"
                            font.family: home.bodyFont
                            font.pixelSize: home.voice === "caps" ? 10 : 11
                            font.weight: home.plain ? Font.Medium : Font.Bold
                            font.letterSpacing: home.voice === "caps" ? 1 : home.bracket ? 1.5 : 0
                        }
                        Text {
                            id: keyWord
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

}

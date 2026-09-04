import QtQuick
import QtQuick.Layouts
import "../components"
import "../DekhoModel.js" as Model

// omakade's qml/Main.qml, row for row, with its vocabulary swapped for this
// module's:
//
//   wordmark + theme name          →  󰎁 DEKHO + the mode you are in
//   ALL / FAVORITES / RECENT       →  ALL / CONTINUE / TRENDING
//   Search games (Ctrl+F)          →  Search films and series
//   ALL SOURCES / STEAM / LUTRIS…  →  ALL / MOVIES / SERIES
//   YOUR LIBRARY · 842 GAMES       →  the mode's caption · a result count
//   SORT: TITLE (cycling)          →  SORT: POPULAR → TOP RATED → NEWEST
//   ORGANIZE: STATUS/COLLECTION…   →  FILTER: GENRE / YEAR / RATING / LANGUAGE
//   LibraryView                    →  PosterGrid
//
// WHAT THIS REPLACES, and it is most of the module's old surface area: the
// backdrop hero that followed the cursor, the horizontal rails, and the whole
// separate Browse screen with its accordion sidebar. The user was shown that
// and chose it — "I like omakade design so our design should be exactly same to
// same." The filters that lived in Browse are the FILTER row here, over the
// same `dekho api discover` call, so nothing they could do is gone; it is one
// screen instead of two.
//
// GENRE IS DISABLED WHILE THE KIND IS ALL, and says so rather than going quiet.
// TMDB's genres are per-kind ("Action" for films, "Action & Adventure" for
// series — doc §9 and §11), so there is no id that means Action for a mixed
// list. Encoding that in a greyed control with a label that explains it beats
// offering a chip that would silently empty half the results.
Item {
    id: library

    required property var style

    // "all" | "continue" | "trending"
    property string mode: "all"
    // "all" | "movie" | "tv"
    property string kind: "all"
    property alias query: search.text

    property var items: []
    // The w342 cache directory and the set of files known to be in it — see
    // PosterGrid, and Dekho.qml's art-path section for why it is a set.
    property string posterDir: ""
    property var posterDone: ({})
    property bool loading: false
    property string errorText: ""
    property bool canLoadMore: false

    property string sortKey: "popular"
    property string genre: ""
    property string year: ""
    property string minRating: ""
    property string language: ""
    // The person scope, when a filmography arrived from a person page. Not a
    // facet — it has no chip, it leads the caption, and CLEAR is how you leave
    // it (doc §11 says the same of the Browse screen it replaces).
    property string castName: ""
    property var genres: []
    property var languages: []

    readonly property bool searching: query.trim() !== ""
    readonly property bool filtered: genre !== "" || year !== "" || minRating !== "" || language !== "" || castName !== ""
    readonly property alias grid: resultGrid
    readonly property alias searchField: search
    readonly property bool gridFocused: resultGrid.gridFocused

    signal modePicked(string mode)
    signal kindPicked(string kind)
    signal queryEdited(string text)
    signal sortCycled
    signal facetCycled(string facet)
    signal filtersCleared
    signal activated(int index)
    signal loadMoreRequested

    function focusGrid() {
        resultGrid.focusGrid();
    }

    // omakade's `filterLabel`, unchanged: a chip says what it is currently set
    // to, truncated at sixteen characters so a long genre cannot push the row
    // off the screen. Cycling the value is the module's job, not the screen's —
    // the values live with the state that sends them to `dekho api discover`.
    function facetLabel(prefix, value) {
        if (!value || value.length === 0)
            return prefix;
        const shortened = value.length > 16 ? value.substring(0, 15) + "…" : value;
        return prefix + ": " + shortened.toUpperCase();
    }

    readonly property string modeCaption: library.searching ? "SEARCH" : library.mode === "continue" ? "CONTINUE WATCHING" : library.mode === "trending" ? "TRENDING THIS WEEK" : "EVERYTHING"

    // The flat page. Every poster on it covers its own corners with a stroke in
    // this colour, so it must not become artwork — see AmbientBackground.
    Rectangle {
        anchors.fill: parent
        color: library.style.bg
    }

    // The header band is the one place on this screen where omakade's discs can
    // show, because it is the one place with no poster corner in it.
    AmbientBackground {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: layout.y + resultGrid.y
        style: library.style
        pageWidth: library.width
        pageHeight: library.height
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.leftMargin: library.style.pagePad
        anchors.rightMargin: library.style.pagePad
        anchors.topMargin: library.style.ui(24)
        anchors.bottomMargin: library.style.ui(16)
        spacing: library.style.ui(20)

        RowLayout {
            Layout.fillWidth: true
            spacing: library.style.ui(18)

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: library.style.ui(11)

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰎁"
                    color: library.style.accent
                    font.family: library.style.fontFamily
                    font.pixelSize: library.style.type(26)
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: library.style.ui(1)

                    Text {
                        textFormat: Text.PlainText
                        text: "DEKHO"
                        color: library.style.brightFg
                        font.family: library.style.fontFamily
                        font.pixelSize: library.style.type(15)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                    // omakade puts the active theme's name here. This shell has
                    // no theme NAME to put in it — `meta.preset` is the name of
                    // an appearance bundle ("flat"), which would read as noise —
                    // and the mode already has its own caption two rows down, so
                    // repeating it here would be the same word twice.
                    Text {
                        textFormat: Text.PlainText
                        text: "MOVIES & TV"
                        color: library.style.muted
                        font.family: library.style.fontFamily
                        font.pixelSize: library.style.type(8)
                        font.letterSpacing: 0.7
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Row {
                spacing: library.style.ui(5)
                visible: library.width >= library.style.ui(1040)

                Repeater {
                    model: [
                        {
                            key: "all",
                            label: "ALL"
                        },
                        {
                            key: "continue",
                            label: "CONTINUE"
                        },
                        {
                            key: "trending",
                            label: "TRENDING"
                        }
                    ]

                    GlassButton {
                        required property var modelData

                        style: library.style
                        text: modelData.label
                        compact: true
                        selected: library.mode === modelData.key
                        onClicked: library.modePicked(modelData.key)
                    }
                }
            }

            SearchField {
                id: search

                Layout.preferredWidth: Math.min(library.style.ui(300), library.width * 0.26)
                Layout.minimumWidth: library.style.ui(190)
                Layout.preferredHeight: library.style.ui(38)
                style: library.style
                onTextChanged: library.queryEdited(text)
                onEscaped: library.focusGrid()
                onSteppedDown: library.focusGrid()
            }
        }

        // omakade's narrow fallback: the mode chips move to their own row when
        // there is no longer space for them beside the search field.
        RowLayout {
            Layout.fillWidth: true
            visible: library.width < library.style.ui(1040)
            spacing: library.style.ui(6)

            Repeater {
                model: [
                    {
                        key: "all",
                        label: "ALL"
                    },
                    {
                        key: "continue",
                        label: "CONTINUE"
                    },
                    {
                        key: "trending",
                        label: "TRENDING"
                    }
                ]

                GlassButton {
                    required property var modelData

                    style: library.style
                    text: modelData.label
                    compact: true
                    selected: library.mode === modelData.key
                    onClicked: library.modePicked(modelData.key)
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: library.style.ui(12)

            Row {
                spacing: library.style.ui(5)

                Repeater {
                    model: [
                        {
                            key: "all",
                            label: "ALL"
                        },
                        {
                            key: "movie",
                            label: "MOVIES"
                        },
                        {
                            key: "tv",
                            label: "SERIES"
                        }
                    ]

                    GlassButton {
                        required property var modelData

                        style: library.style
                        text: modelData.label
                        compact: true
                        selected: library.kind === modelData.key
                        onClicked: library.kindPicked(modelData.key)
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                visible: library.width >= library.style.ui(1100)
                text: library.castName !== "" ? library.castName.toUpperCase() : library.modeCaption
                color: library.style.fg
                font.family: library.style.fontFamily
                font.pixelSize: library.style.type(11)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.7
            }
            Text {
                textFormat: Text.PlainText
                visible: library.width >= library.style.ui(1100)
                text: library.items.length + (library.items.length === 1 ? " TITLE" : " TITLES")
                color: library.style.muted
                font.family: library.style.fontFamily
                font.pixelSize: library.style.type(9)
            }
            Text {
                textFormat: Text.PlainText
                visible: library.width >= library.style.ui(1100) && library.loading
                text: "LOADING"
                color: library.style.accent
                font.family: library.style.fontFamily
                font.pixelSize: library.style.type(9)
                font.weight: Font.DemiBold
            }

            Item {
                Layout.fillWidth: true
            }

            GlassButton {
                style: library.style
                compact: true
                // Sort is a property of `discover`, so it says nothing about a
                // history list or a search — omakade hides its own controls the
                // same way rather than leaving them inert.
                visible: library.mode === "all" && !library.searching
                text: "SORT: " + Model.choiceLabel(Model.SORT_CHOICES, library.sortKey).toUpperCase()
                onClicked: library.sortCycled()
            }

            Text {
                textFormat: Text.PlainText
                visible: library.width > library.style.ui(930)
                text: "ENTER  OPEN   ·   ^F  SEARCH   ·   ESC  BACK"
                color: library.style.alpha(library.style.fg, 0.42)
                font.family: library.style.fontFamily
                font.pixelSize: library.style.type(8)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: library.mode === "all" && !library.searching
            spacing: library.style.ui(6)

            Text {
                textFormat: Text.PlainText
                text: "FILTER"
                color: library.style.muted
                font.family: library.style.fontFamily
                font.pixelSize: library.style.type(9)
                font.weight: Font.DemiBold
            }
            GlassButton {
                style: library.style
                compact: true
                // The constraint, said out loud. See the header.
                enabled: library.kind !== "all"
                text: library.kind === "all" ? "GENRE: KIND FIRST" : library.facetLabel("GENRE", Model.genreLabel(library.genres, library.genre))
                selected: library.genre !== ""
                onClicked: library.facetCycled("genre")
            }
            GlassButton {
                style: library.style
                compact: true
                text: library.facetLabel("YEAR", Model.choiceLabel(Model.YEAR_CHOICES, library.year))
                selected: library.year !== ""
                onClicked: library.facetCycled("year")
            }
            GlassButton {
                style: library.style
                compact: true
                text: library.facetLabel("RATING", library.minRating === "" ? "" : "★ " + library.minRating + "+")
                selected: library.minRating !== ""
                onClicked: library.facetCycled("rating")
            }
            GlassButton {
                style: library.style
                compact: true
                text: library.facetLabel("LANGUAGE", Model.languageLabel(library.languages, library.language))
                selected: library.language !== ""
                onClicked: library.facetCycled("language")
            }
            GlassButton {
                style: library.style
                compact: true
                visible: library.filtered
                text: "CLEAR"
                onClicked: library.filtersCleared()
            }
            Item {
                Layout.fillWidth: true
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: library.errorText !== ""
            text: library.errorText
            color: library.style.red
            font.family: library.style.fontFamily
            font.pixelSize: library.style.type(10)
            wrapMode: Text.Wrap
        }

        PosterGrid {
            id: resultGrid

            Layout.fillWidth: true
            Layout.fillHeight: true

            style: library.style
            items: library.items
            pageColor: library.style.bg
            posterDir: library.posterDir
            posterDone: library.posterDone
            canLoadMore: library.canLoadMore

            emptyTitle: library.loading ? "Asking TMDB" : library.searching ? "Nothing matched" : library.mode === "continue" ? "Nothing to continue" : "Nothing came back"
            emptyMessage: library.loading ? "One `dekho api` call, on its way." : library.searching ? "Nothing on TMDB matched “" + library.query + "”." : library.mode === "continue" ? "Play something and it will be waiting here." : library.filtered ? "Clear or change the filters to see more." : "Check the network, or the TMDB key in ~/.config/dekho/config.toml."
            emptyAction: library.filtered && !library.loading ? "CLEAR FILTERS" : ""

            onActivated: index => library.activated(index)
            onLoadMoreRequested: library.loadMoreRequested()
            onEmptyActionRequested: library.filtersCleared()
        }
    }
}

import QtQuick
import "../../components"
import "DekhoModel.js" as Model

// Browse: the catalog with the filters turned on. The hub's rails are two
// fixed `dekho api discover` calls with a shared sort chip; this is the same
// verb with every flag it has exposed, a grid instead of a shelf, and paging.
// It is also where a genre click from a detail page lands, which is why the
// filter state lives in the hub and arrives here as properties — a genre chip
// has to be able to open this screen already filtered.
//
// THE FILTERS ARE AN ACCORDION, NOT A DIALOG. Six facets with up to twenty
// values each is four hundred pixels of chips if they are all laid out at
// once, and a modal picker per facet is three clicks to change one thing. A
// list of facet rows that opens one at a time is one flat index for the
// keyboard, an obvious click target for the mouse, and it always shows what
// each facet is currently set to.
Item {
    id: browse

    required property var theme
    // The hub's module-local type scale (Dekho.qml `fonts`).
    required property var fonts
    property int edgePad: theme.space(10)
    property int posterWidth: theme.space(38)

    // The live filter, owned by the hub (it builds the argv and holds the back
    // stack's copy of it).
    property string kind: "movie"
    property string sort: "popular"
    property string genre: ""
    property string lang: ""
    property string minRating: ""
    property string year: ""
    // A person scope, set from a person page rather than from the sidebar —
    // there is no facet row for it, so it shows in the caption and Escape is
    // how you leave it.
    property string castName: ""
    property int page: 1
    property int totalPages: 1

    // The facet vocabularies. Genres are kind-specific and languages are
    // dekho's own shortlist, so both are fetched rather than hardcoded.
    property var genres: []
    property var languages: []

    property var items: []
    property bool loading: false
    property string error: ""
    property string posterDir: ""
    property bool postersReady: false

    // Cursors. Owned here — the movers assign them — and read back by the hub
    // when this screen is pushed under another one.
    property int gridIndex: 0
    property int rowIndex: 0
    // Which facet is open, "" for none.
    property string expanded: ""
    // "filters" or "results": which pane the keyboard is in.
    property string pane: "results"

    signal facetChosen(string facet, string value)
    signal pageStepped(int delta)
    signal titlePicked(var item)
    signal dismissed

    readonly property string genreName: Model.genreLabel(genres, genre)
    readonly property string langName: Model.languageLabel(languages, lang)

    onItemsChanged: {
        gridIndex = 0;
        grid.positionViewAtBeginning();
    }

    // --------------------------------------------------------------- facets
    readonly property var kindChoices: [
        {
            key: "movie",
            label: "Movies"
        },
        {
            key: "tv",
            label: "Series"
        }
    ]

    function genreChoices() {
        const out = [
            {
                key: "",
                label: "Any"
            }
        ];
        for (let i = 0; i < genres.length; i++)
            out.push({
                key: String(genres[i].id),
                label: String(genres[i].name)
            });
        return out;
    }

    function langChoices() {
        const out = [
            {
                key: "",
                label: "Any"
            }
        ];
        for (let i = 0; i < languages.length; i++)
            out.push({
                key: String(languages[i].code),
                label: String(languages[i].name)
            });
        return out;
    }

    readonly property var facets: [
        {
            key: "kind",
            label: "Kind",
            value: browse.kind,
            shown: Model.choiceLabel(browse.kindChoices, browse.kind),
            options: browse.kindChoices
        },
        {
            key: "sort",
            label: "Sort",
            value: browse.sort,
            shown: Model.choiceLabel(Model.SORT_CHOICES, browse.sort),
            options: Model.SORT_CHOICES
        },
        {
            key: "genre",
            label: "Genre",
            value: browse.genre,
            shown: browse.genreName || "Any",
            options: browse.genreChoices()
        },
        {
            key: "lang",
            label: "Language",
            value: browse.lang,
            shown: browse.langName || "Any",
            options: browse.langChoices()
        },
        {
            key: "rating",
            label: "Rating",
            value: browse.minRating,
            shown: Model.choiceLabel(Model.RATING_CHOICES, browse.minRating),
            options: Model.RATING_CHOICES
        },
        {
            key: "year",
            label: "Year",
            value: browse.year,
            shown: Model.choiceLabel(Model.YEAR_CHOICES, browse.year),
            options: Model.YEAR_CHOICES
        }
    ]

    // The sidebar flattened to rows: every facet, plus the open one's values
    // right under it. One array means one index for the keyboard and one
    // delegate for the mouse, instead of a nested list with two cursors.
    readonly property var rows: {
        const out = [];
        for (let i = 0; i < facets.length; i++) {
            const f = facets[i];
            out.push({
                kindOf: "facet",
                facet: f.key,
                label: f.label,
                shown: f.shown,
                chosen: false
            });
            if (browse.expanded !== f.key)
                continue;
            for (let j = 0; j < f.options.length; j++)
                out.push({
                    kindOf: "option",
                    facet: f.key,
                    label: f.options[j].label,
                    shown: "",
                    value: f.options[j].key,
                    chosen: String(f.options[j].key) === String(f.value)
                });
        }
        return out;
    }

    function activateRow(i) {
        const row = rows[i];
        if (!row)
            return;
        rowIndex = i;
        if (row.kindOf === "facet") {
            expanded = expanded === row.facet ? "" : row.facet;
            return;
        }
        expanded = "";
        // Collapsing moves every row below this facet, so the cursor is put
        // back on the facet header it just answered rather than left pointing
        // at whatever slid into its place.
        for (let j = 0; j < rows.length; j++) {
            if (rows[j].kindOf === "facet" && rows[j].facet === row.facet) {
                rowIndex = j;
                break;
            }
        }
        browse.facetChosen(row.facet, String(row.value));
    }

    // --------------------------------------------------------------- cursor
    // The grid decides its own column count now (it divides the row by it), so
    // the cursor reads that rather than re-deriving it and risking a different
    // answer on a rounding boundary.
    readonly property int gridColumns: grid.columns

    function handleKey(event) {
        if (event.key === Qt.Key_PageDown) {
            browse.pageStepped(1);
            return true;
        }
        if (event.key === Qt.Key_PageUp) {
            browse.pageStepped(-1);
            return true;
        }
        // Tab walks the pane you are in, and stays in it. Left and Right
        // already cross between the sidebar and the results — the sidebar is
        // literally to the left — so making Tab a third way to change pane
        // would mean the key that means "next" sometimes meant "elsewhere",
        // which on a screen with two hundred results is the one place that
        // would be hard to undo.
        const tab = Model.tabDelta(event);
        if (tab !== 0) {
            if (pane === "filters")
                moveRow(tab);
            else
                moveGrid(tab);
            return true;
        }
        return pane === "filters" ? filterKey(event) : gridKey(event);
    }

    function moveRow(delta) {
        rowIndex = Model.clampIndex(rowIndex + delta, rows.length);
        filterList.positionViewAtIndex(rowIndex, ListView.Contain);
    }

    function moveGrid(delta) {
        gridIndex = Model.clampIndex(gridIndex + delta, items.length);
        grid.positionViewAtIndex(gridIndex, GridView.Contain);
    }

    function filterKey(event) {
        switch (event.key) {
        case Qt.Key_Up:
            moveRow(-1);
            return true;
        case Qt.Key_Down:
            moveRow(1);
            return true;
        case Qt.Key_Right:
            pane = "results";
            return true;
        case Qt.Key_Left:
            // Left inside an open facet closes it; on a closed one it is the
            // way back out of the sidebar, which is nowhere — so it stays.
            if (expanded !== "")
                expanded = "";
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateRow(rowIndex);
            return true;
        }
        return false;
    }

    function gridKey(event) {
        const count = items.length;
        switch (event.key) {
        case Qt.Key_Left:
            // The left edge of the grid is the way into the filters — the
            // sidebar is literally there, so the key that points at it works.
            if (count === 0 || gridIndex % gridColumns === 0) {
                pane = "filters";
                return true;
            }
            moveGrid(-1);
            return true;
        case Qt.Key_Right:
            moveGrid(1);
            return true;
        case Qt.Key_Up:
            gridIndex = Model.gridStep(gridIndex, -1, count, gridColumns);
            grid.positionViewAtIndex(gridIndex, GridView.Contain);
            return true;
        case Qt.Key_Down:
            gridIndex = Model.gridStep(gridIndex, 1, count, gridColumns);
            grid.positionViewAtIndex(gridIndex, GridView.Contain);
            return true;
        case Qt.Key_Home:
            gridIndex = 0;
            grid.positionViewAtBeginning();
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (gridIndex >= 0 && gridIndex < count)
                browse.titlePicked(items[gridIndex]);
            return true;
        }
        return false;
    }

    // Follow the pointer, not the scroll (FilePicker's guard).
    property real hoverSceneX: -1
    property real hoverSceneY: -1

    function pointerMoved(sx, sy) {
        if (sx === hoverSceneX && sy === hoverSceneY)
            return false;
        hoverSceneX = sx;
        hoverSceneY = sy;
        return true;
    }

    Rectangle {
        anchors.fill: parent
        color: browse.theme.surface0
    }

    // --------------------------------------------------------------- header
    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: browse.edgePad
        anchors.rightMargin: browse.edgePad
        anchors.topMargin: browse.theme.space(6)
        height: browse.theme.space(10)

        GlyphButton {
            id: backButton

            anchors.verticalCenter: parent.verticalCenter
            width: browse.theme.space(11)
            height: browse.theme.space(10)
            theme: browse.theme
            glyph: "󰁍"
            glyphSize: browse.fonts.heroMeta
            hint: "Back (Esc)"
            onActivated: browse.dismissed()
        }

        StyledText {
            anchors.left: backButton.right
            anchors.right: pager.left
            anchors.leftMargin: browse.theme.space(5)
            anchors.rightMargin: browse.theme.space(5)
            anchors.verticalCenter: parent.verticalCenter
            theme: browse.theme
            font.pixelSize: browse.fonts.railTitle
            font.weight: Font.Bold
            elide: Text.ElideRight
            text: Model.browseCaption({
                kind: browse.kind,
                sort: browse.sort,
                minRating: browse.minRating,
                year: browse.year
            }, browse.genreName, browse.langName, browse.castName) + (browse.loading ? "  ·  loading…" : "")
        }

        Row {
            id: pager

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: browse.theme.space(3)

            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                width: browse.theme.space(10)
                height: browse.theme.space(9)
                theme: browse.theme
                glyph: "󰅁"
                glyphSize: browse.fonts.meta
                hint: "Previous page (PgUp)"
                enabled: browse.page > 1
                onActivated: browse.pageStepped(-1)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                theme: browse.theme
                font.pixelSize: browse.fonts.meta
                mono: true
                muted: true
                text: browse.page + " / " + Math.max(1, browse.totalPages)
            }

            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                width: browse.theme.space(10)
                height: browse.theme.space(9)
                theme: browse.theme
                glyph: "󰅂"
                glyphSize: browse.fonts.meta
                hint: "Next page (PgDn)"
                enabled: browse.page < browse.totalPages
                onActivated: browse.pageStepped(1)
            }
        }
    }

    // -------------------------------------------------------------- filters
    Item {
        id: sidebar

        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: browse.edgePad
        anchors.topMargin: browse.theme.space(6)
        anchors.bottomMargin: browse.theme.space(6)
        width: Math.max(browse.theme.space(48), Math.round(browse.width * 0.2))

        ListView {
            id: filterList

            anchors.fill: parent
            model: browse.rows
            clip: true
            spacing: browse.theme.space(1)
            boundsBehavior: Flickable.StopAtBounds

            delegate: CursorSurface {
                id: filterRow

                required property var modelData
                required property int index

                readonly property bool isFacet: filterRow.modelData.kindOf === "facet"

                width: filterList.width
                height: Math.round(browse.fonts.cardTitle * 2.4)
                theme: browse.theme
                current: browse.pane === "filters" && browse.rowIndex === filterRow.index
                bordered: false

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: filterRow.isFacet ? browse.theme.space(3) : browse.theme.space(8)
                    anchors.rightMargin: browse.theme.space(3)
                    spacing: browse.theme.space(2)

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - valueLabel.width - browse.theme.space(2)
                        theme: browse.theme
                        font.pixelSize: browse.fonts.cardTitle
                        font.weight: filterRow.isFacet ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        color: filterRow.modelData.chosen ? browse.theme.accent : browse.theme.textPrimary
                        text: (filterRow.isFacet ? "" : (filterRow.modelData.chosen ? "󰄬  " : "    ")) + filterRow.modelData.label
                    }

                    // The facet's current value, right-aligned — the row says
                    // what it is set to without being opened.
                    StyledText {
                        id: valueLabel

                        anchors.verticalCenter: parent.verticalCenter
                        visible: filterRow.isFacet
                        theme: browse.theme
                        font.pixelSize: browse.fonts.meta
                        mono: true
                        color: browse.theme.accent
                        text: filterRow.isFacet ? filterRow.modelData.shown : ""
                    }
                }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onPointChanged: {
                        if (hovered && browse.pointerMoved(point.scenePosition.x, point.scenePosition.y)) {
                            browse.pane = "filters";
                            browse.rowIndex = filterRow.index;
                        }
                    }
                }

                TapHandler {
                    onTapped: {
                        browse.pane = "filters";
                        browse.activateRow(filterRow.index);
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------- results
    Item {
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: browse.theme.space(10)
        // Short by one gutter, so the LAST column's poster ends on the edge
        // pad rather than a gutter inside it (the hub's search grid does the
        // same). Each cell carries its gutter on the right; without this the
        // grid would sit visibly further from the right edge than the left.
        anchors.rightMargin: browse.edgePad - grid.cellSpacing
        anchors.topMargin: browse.theme.space(6)
        anchors.bottomMargin: browse.theme.space(4)

        GridView {
            id: grid

            readonly property int cellSpacing: Math.max(browse.theme.space(4), Math.round(browse.width * 0.008))
            // A ROW FILLS THE ROW. `posterWidth` is a TARGET, not the answer:
            // it decides how many columns fit, and then the width is divided
            // by that count so six cards span the whole row. Sizing the cell
            // from the target instead left the remainder as dead space at the
            // right edge — enough for most of a seventh card, so the grid
            // ended in a cut-off sliver and the row looked unfinished.
            readonly property int columns: Math.max(1, Math.floor(width / (browse.posterWidth + cellSpacing)))
            readonly property int tileWidth: cellWidth - cellSpacing

            anchors.fill: parent
            model: browse.items
            clip: true
            cellWidth: Math.floor(width / columns)
            cellHeight: Math.round(tileWidth * 1.5) + browse.fonts.labelZone + browse.theme.space(4)
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: cellHeight * 2

            delegate: Item {
                id: cell

                required property var modelData
                required property int index

                width: grid.cellWidth
                height: grid.cellHeight

                PosterTile {
                    theme: browse.theme
                    fonts: browse.fonts
                    width: grid.tileWidth
                    title: cell.modelData.title || ""
                    subtitle: (cell.modelData.year ? cell.modelData.year + " · " : "") + Model.kindLabel(cell.modelData.kind || browse.kind)
                    posterPath: browse.postersReady && browse.posterDir && cell.modelData.poster ? browse.posterDir + "/" + String(cell.modelData.poster).replace(/^\/+/, "") : ""
                    current: browse.pane === "results" && browse.gridIndex === cell.index

                    onEntered: (sx, sy) => {
                        if (browse.pointerMoved(sx, sy)) {
                            browse.pane = "results";
                            browse.gridIndex = cell.index;
                        }
                    }
                    onActivated: {
                        browse.pane = "results";
                        browse.gridIndex = cell.index;
                        browse.titlePicked(cell.modelData);
                    }
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: browse.theme.space(16)
            width: Math.round(parent.width * 0.7)
            visible: browse.items.length === 0
            theme: browse.theme
            font.pixelSize: browse.fonts.cardTitle
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            muted: browse.error === ""
            color: browse.error !== "" ? browse.theme.error : browse.theme.textMuted
            text: browse.error !== "" ? browse.error : (browse.loading ? "Loading…" : "Nothing on TMDB matches these filters")
        }
    }

    StyledText {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: browse.edgePad
        anchors.bottomMargin: browse.theme.space(3)
        theme: browse.theme
        font.pixelSize: browse.fonts.hint
        mono: true
        muted: true
        text: "↵ open    ←/→ pane    pgup/pgdn page    esc back"
    }
}

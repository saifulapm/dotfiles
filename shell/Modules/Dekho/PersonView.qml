import QtQuick
import "../../components"
import "DekhoModel.js" as Model

// One person, opened by clicking a face or a crew chip: who they are on the
// left, everything they are in on the right. This is the other half of the
// click-through — a cast member is a question ("what else have they done?")
// and until now the hub could only answer it by making you type the name.
//
// No backdrop art here, deliberately. TMDB has no still for a person, and a
// borrowed one from their best-known film would be a claim the page is not
// making. The page is the hub's opaque surface, which is also what lets the
// portrait be a real circle and the posters keep their corner cover — both are
// painted in the page colour (see FaceTile's header).
Item {
    id: personView

    required property var theme
    // The hub's module-local type scale (Dekho.qml `fonts`).
    required property var fonts
    property int edgePad: theme.space(10)
    // The hub's poster width; the filmography is sized off it.
    property int posterWidth: theme.space(38)
    // The `dekho api person` object, or null while it is being fetched.
    property var person: null
    property bool loading: false
    property string error: ""
    // w185 profile and w342 credit posters: two prefetches landing
    // independently, each guarded on its OWN directory (doc §6).
    property string photoDir: ""
    property bool photoReady: false
    property string creditsDir: ""
    property bool creditsReady: false

    // The keyboard cursor into the filmography. Owned here; the movers assign
    // it and an assignment would destroy an incoming binding.
    property int gridIndex: 0

    signal titlePicked(var item)
    signal browseRequested
    signal dismissed

    readonly property var credits: person && person.credits ? person.credits : []
    readonly property string photoPath: photoReady && photoDir && person && person.profile ? photoDir + "/" + String(person.profile).replace(/^\/+/, "") : ""
    readonly property int portraitWidth: Math.max(theme.space(30), Math.min(Math.round(posterWidth * 0.62), theme.space(52)))
    readonly property int creditWidth: Math.round(posterWidth * 0.62)
    readonly property int columnWidth: Math.max(portraitWidth, Math.round(width * 0.26))

    onPersonChanged: {
        gridIndex = 0;
        grid.positionViewAtBeginning();
    }

    // The grid divides the row by its own column count, so read that rather
    // than re-deriving it and disagreeing on a rounding boundary.
    readonly property int gridColumns: grid.columns

    function moveGrid(delta) {
        gridIndex = Model.clampIndex(gridIndex + delta, credits.length);
        grid.positionViewAtIndex(gridIndex, GridView.Contain);
    }

    function handleKey(event) {
        const count = credits.length;
        // Ctrl+B means Browse everywhere in this module; here it means Browse
        // scoped to this person (`dekho api discover --cast`), which is the
        // filmography with the whole facet sidebar over it.
        if ((event.modifiers & Qt.ControlModifier) !== 0 && event.key === Qt.Key_B) {
            personView.browseRequested();
            return true;
        }
        // The filmography is already one linear order — Left and Right cross
        // row boundaries — so Tab is that step without having to be aimed.
        const tab = Model.tabDelta(event);
        if (tab !== 0) {
            moveGrid(tab);
            return true;
        }
        switch (event.key) {
        case Qt.Key_Left:
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
                personView.titlePicked(credits[gridIndex]);
            return true;
        }
        return false;
    }

    // Follow the pointer, not the scroll (FilePicker's guard): a card sliding
    // under a stationary mouse re-fires hover with the same scene position.
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
        color: personView.theme.surface0
    }

    GlyphButton {
        id: backButton

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: personView.theme.space(6)
        anchors.leftMargin: personView.edgePad
        width: personView.theme.space(11)
        height: personView.theme.space(10)
        theme: personView.theme
        glyph: "󰁍"
        glyphSize: personView.fonts.heroMeta
        hint: "Back (Esc)"
        onActivated: personView.dismissed()
    }

    // ------------------------------------------------------------ who it is
    Flickable {
        id: bioPane

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: personView.edgePad
        anchors.topMargin: personView.theme.space(20)
        anchors.bottomMargin: personView.theme.space(8)
        width: personView.columnWidth
        contentWidth: width
        contentHeight: bioColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: bioColumn

            width: bioPane.width
            spacing: personView.theme.space(4)

            // The portrait, a circle by the same one-rectangle-node trick the
            // cast shelf uses — outer radius 2r, border r, painted in the page
            // colour. See FaceTile's header for why this is not a clip.
            Rectangle {
                id: portrait

                width: personView.portraitWidth
                height: personView.portraitWidth
                radius: width / 2
                color: personView.theme.surface2

                Image {
                    anchors.fill: parent
                    source: personView.photoPath ? "file://" + personView.photoPath.split("/").map(encodeURIComponent).join("/") : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: parent.width
                    asynchronous: true
                    visible: status === Image.Ready
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: personView.photoPath === ""
                    theme: personView.theme
                    font.pixelSize: Math.round(parent.width * 0.32)
                    font.weight: Font.DemiBold
                    muted: true
                    text: Model.initials(personView.person ? personView.person.name : "")
                }

                // Overhang 0.22w, not the radius: a ring that reaches half a
                // portrait past the portrait would paint over the name under
                // it. See FaceTile's header for the geometry.
                Rectangle {
                    readonly property int overhang: Math.max(1, Math.round(portrait.width * 0.22))

                    anchors.fill: parent
                    anchors.margins: -overhang
                    radius: width / 2
                    color: "transparent"
                    border.width: overhang + personView.theme.borderWidth
                    border.color: personView.theme.surface0
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: portrait.radius
                    border.width: personView.theme.borderWidth
                    border.color: personView.theme.alpha(personView.theme.surface3, 0.7)
                }
            }

            StyledText {
                width: parent.width
                theme: personView.theme
                // Not `fonts.hero`: a name is not a film title, and hero type
                // on a two-word name across a narrow column wraps to three
                // lines and leaves no room for the life it belongs to.
                font.pixelSize: personView.fonts.railTitle
                font.weight: Font.Bold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: personView.person ? personView.person.name : (personView.loading ? "…" : "")
            }

            StyledText {
                width: parent.width
                visible: text !== ""
                theme: personView.theme
                font.pixelSize: personView.fonts.meta
                font.weight: Font.DemiBold
                color: personView.theme.accent
                wrapMode: Text.Wrap
                text: {
                    if (!personView.person)
                        return "";
                    const bits = [];
                    if (personView.person.known_for)
                        bits.push(String(personView.person.known_for));
                    const life = Model.lifeLabel(personView.person);
                    if (life)
                        bits.push(life);
                    if (personView.person.place_of_birth)
                        bits.push(String(personView.person.place_of_birth));
                    return bits.join("  ·  ");
                }
            }

            StyledText {
                width: parent.width
                visible: personView.error !== ""
                theme: personView.theme
                font.pixelSize: personView.fonts.meta
                color: personView.theme.error
                wrapMode: Text.Wrap
                text: personView.error
            }

            // The filmography on the right is TMDB's own popularity order and
            // nothing else. This is the same list handed to the Browse screen,
            // where it can be sorted, narrowed to a genre or cut to a decade.
            ActionChip {
                theme: personView.theme
                fonts: personView.fonts
                visible: personView.person !== null
                label: "󰀻  Browse their titles"

                onActivated: personView.browseRequested()
            }

            // The whole biography, not an elided paragraph — this pane scrolls
            // on its own precisely so a long one can be read without the
            // filmography beside it moving.
            StyledText {
                width: parent.width
                visible: text !== ""
                theme: personView.theme
                font.pixelSize: personView.fonts.heroBody
                color: personView.theme.alpha(personView.theme.textPrimary, 0.85)
                wrapMode: Text.Wrap
                text: personView.person && personView.person.biography ? String(personView.person.biography) : ""
            }
        }
    }

    // -------------------------------------------------------- what they are in
    Column {
        anchors.left: bioPane.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: personView.theme.space(10)
        anchors.rightMargin: personView.edgePad
        anchors.topMargin: personView.theme.space(20)
        anchors.bottomMargin: personView.theme.space(4)
        spacing: personView.theme.space(3)

        StyledText {
            theme: personView.theme
            font.pixelSize: personView.fonts.railTitle
            font.weight: Font.DemiBold
            text: "Filmography" + (personView.loading ? "  ·  loading…" : "") + (personView.credits.length > 0 ? "  ·  " + personView.credits.length : "")
        }

        Item {
            width: parent.width
            height: Math.max(0, parent.height - y)

            GridView {
                id: grid

                readonly property int cellSpacing: Math.max(personView.theme.space(4), Math.round(personView.width * 0.008))
                // A row fills the row — `creditWidth` picks the column count
                // and the width is then divided by it, so a filmography never
                // ends in the sliver of a cut card. Same rule as the Browse
                // and search grids.
                readonly property int columns: Math.max(1, Math.floor(width / (personView.creditWidth + cellSpacing)))
                readonly property int tileWidth: cellWidth - cellSpacing

                anchors.fill: parent
                model: personView.credits
                clip: true
                cellWidth: Math.floor(width / columns)
                cellHeight: Math.round(tileWidth * 1.5) + personView.fonts.labelZone + personView.theme.space(4)
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: cellHeight * 2

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index

                    width: grid.cellWidth
                    height: grid.cellHeight

                    PosterTile {
                        theme: personView.theme
                        fonts: personView.fonts
                        width: grid.tileWidth
                        title: cell.modelData.title || ""
                        // The character is the reason this grid is on this
                        // page: "Walter White" under Breaking Bad says what
                        // "2008 · Series" cannot.
                        subtitle: cell.modelData.character ? String(cell.modelData.character) : (cell.modelData.year ? cell.modelData.year + " · " + Model.kindLabel(cell.modelData.kind) : Model.kindLabel(cell.modelData.kind))
                        posterPath: personView.creditsReady && personView.creditsDir && cell.modelData.poster ? personView.creditsDir + "/" + String(cell.modelData.poster).replace(/^\/+/, "") : ""
                        current: personView.gridIndex === cell.index

                        onEntered: (sx, sy) => {
                            if (personView.pointerMoved(sx, sy))
                                personView.gridIndex = cell.index;
                        }
                        onActivated: {
                            personView.gridIndex = cell.index;
                            personView.titlePicked(cell.modelData);
                        }
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: !personView.loading && personView.credits.length === 0
                theme: personView.theme
                font.pixelSize: personView.fonts.cardTitle
                muted: true
                text: "TMDB lists no credits for this person"
            }
        }
    }

    StyledText {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: personView.edgePad
        anchors.bottomMargin: personView.theme.space(3)
        theme: personView.theme
        font.pixelSize: personView.fonts.hint
        mono: true
        muted: true
        text: "↵ open    ^b browse their titles    esc back"
    }
}

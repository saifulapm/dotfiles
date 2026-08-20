import QtQuick
import "../../components"

// A captioned horizontal shelf of posters — "Continue watching", "Trending
// this week", and so on. The hub owns the data and the cursor; a rail owns
// only its scroll position and the geometry of a tile.
//
// The caption and the first card sit at the hub's edge padding, but the strip
// itself runs the full width and bleeds off the right edge of the screen — a
// card cut by the bezel is what says "this shelf continues", where a strip
// that ends at a margin says "this is all of it".
Column {
    id: rail

    required property var theme
    // The hub's module-local type scale (see Dekho.qml `fonts`).
    required property var fonts
    property string title: ""
    // Plain JS array of `dekho api` items. ListView takes one directly, which
    // keeps a refresh a single assignment instead of a ListModel diff.
    property var items: []
    // Withheld until this rail's `dekho api prefetch` has finished, so no tile
    // ever points an Image at a file that is not on disk yet.
    property bool postersReady: false
    property string posterDir: ""
    // -1 when the keyboard cursor is in another rail.
    property int currentIndex: -1
    property bool loading: false
    property string emptyText: ""
    property int edgePad: theme.space(10)
    property int gutter: theme.space(4)

    signal activated(int index)
    signal entered(int index, real sceneX, real sceneY)

    // Set by the hub from the space it actually has (see Dekho.qml tileSize) —
    // a rail on a 3490 px desk and a rail on a laptop panel are not the same
    // rail. The default is only what a Rail used on its own would get.
    property int tileWidth: theme.space(36)
    readonly property bool empty: !loading && items.length === 0
    readonly property int labelZone: fonts.labelZone

    // A rail with nothing in it and nothing to say about that takes no room —
    // "Continue watching" simply is not there before anything is watched.
    visible: !empty || emptyText !== ""
    height: visible ? implicitHeight : 0
    spacing: theme.space(3)

    function ensureVisible(index) {
        if (index >= 0 && index < items.length)
            strip.positionViewAtIndex(index, ListView.Contain);
    }

    onCurrentIndexChanged: ensureVisible(currentIndex)

    StyledText {
        x: rail.edgePad
        width: rail.width - rail.edgePad * 2
        theme: rail.theme
        font.pixelSize: rail.fonts.railTitle
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        text: rail.title + (rail.loading ? "  ·  loading…" : "")
    }

    Item {
        width: rail.width
        height: Math.round(rail.tileWidth * 1.5) + rail.labelZone

        ListView {
            id: strip

            anchors.fill: parent
            orientation: ListView.Horizontal
            spacing: rail.gutter
            leftMargin: rail.edgePad
            model: rail.items
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // A rail is twenty items; caching a screen either side keeps a
            // fling from decoding posters in the visible frame.
            cacheBuffer: rail.tileWidth * 4
            visible: !rail.empty

            delegate: PosterTile {
                required property var modelData
                required property int index

                theme: rail.theme
                fonts: rail.fonts
                width: rail.tileWidth
                title: modelData.title || ""
                subtitle: rail.subtitleFor(modelData)
                posterPath: rail.postersReady && modelData.poster ? rail.posterDir + "/" + String(modelData.poster).replace(/^\/+/, "") : ""
                progress: Number(modelData.progress) || 0
                current: rail.currentIndex === index

                onActivated: rail.activated(index)
                onEntered: (sx, sy) => rail.entered(index, sx, sy)
            }
        }

        StyledText {
            x: rail.edgePad
            anchors.verticalCenter: parent.verticalCenter
            visible: rail.empty
            theme: rail.theme
            font.pixelSize: rail.fonts.cardTitle
            muted: true
            text: rail.emptyText
        }
    }

    // Second line under a focused poster. History rows say where you are;
    // catalog rows say what and when.
    function subtitleFor(item) {
        if (!item)
            return "";
        if (item.resume)
            return item.resume;
        const bits = [];
        if (item.year)
            bits.push(String(item.year));
        if (item.kind)
            bits.push(item.kind === "tv" ? "Series" : "Movie");
        return bits.join(" · ");
    }
}

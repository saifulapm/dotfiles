import QtQuick
import "../../components"

// One poster in a rail or the search grid. tvOS focus model: the art IS the
// label until the cursor arrives — the focused card lifts (a plain transform
// scale, no effect), takes the accent ring, and only then shows its title and
// meta line underneath. Unfocused cards sit back as pure artwork, which is
// what lets sixty of them share a screen without reading as a spreadsheet.
// Everything a tile knows arrives as plain properties — the rails hand it a
// row out of a ListModel, so nothing here reaches back into the hub.
//
// The art is NOT clipped to its radius, deliberately. Rounding a picture in Qt
// costs a framebuffer per instance whichever way it is done — ClippingRectangle
// is a `layer.enabled` Rectangle plus a ShaderEffectSource (read
// /usr/lib64/qt6/qml/Quickshell/Widgets/ClippingRectangle.qml), and
// layer.effect is the same trade — and a hub draws sixty of these at once.
// Instead the frame is a plain Rectangle stroked OVER the image on the rounded
// path: at this radius on these poster sizes the image nub left outside the
// stroke is a couple of dark-on-dark pixels at four corners, and it costs one
// more ordinary rectangle node.
Item {
    id: tile

    required property var theme
    // The hub's module-local type scale (Dekho.qml `fonts`). Injected rather
    // than read from a singleton for the same reason theme is.
    required property var fonts
    property string title: ""
    property string subtitle: ""
    // "" until the rail's prefetch has finished. An Image pointed at a file
    // that is not there yet caches the failure and never retries, which is why
    // the source is withheld rather than set optimistically (see Rail.qml).
    property string posterPath: ""
    property real progress: 0
    property bool current: false

    signal activated
    // Carries the pointer's scene position so the hub can tell a moved mouse
    // from a card that scrolled under a stationary one (FilePicker's guard).
    signal entered(real sceneX, real sceneY)

    readonly property int artHeight: Math.round(width * 1.5)

    implicitWidth: theme.space(38)
    implicitHeight: artHeight + fonts.labelZone

    Rectangle {
        id: art

        width: parent.width
        height: tile.artHeight
        radius: tile.theme.radius(1.25)
        color: tile.theme.surface2
        // Scissor clipping, only while the art is actually zoomed. The focus
        // effect scales the IMAGE inside a fixed frame — scaling the whole
        // card bulged the frame over its neighbours and the rail caption
        // (user verdict 2026-08-19). `clip` here is a rectangular scissor,
        // not a framebuffer, and the binding keeps it off for the ~59 cards
        // at rest so only the one zoomed card pays the batch break; it stays
        // on through the zoom-OUT animation, or the image would poke past
        // the corners for the exit's 150 ms.
        clip: poster.scale > 1.0

        Image {
            id: poster

            anchors.fill: parent
            source: tile.posterPath ? "file://" + tile.posterPath.split("/").map(encodeURIComponent).join("/") : ""
            fillMode: Image.PreserveAspectCrop
            // The cache holds TMDB's w342 (342x513). Decoding at tile width
            // instead keeps a sixty-poster hub near 10 MB of pixmaps rather
            // than 40 — and the surface is evictable, so this is what idle RSS
            // returns to after a browse.
            sourceSize.width: tile.width
            asynchronous: true
            visible: status === Image.Ready
            // The tvOS focus zoom, on the picture rather than the card: same
            // nodes, new matrix — free, where a glow effect on sixty cards
            // would be sixty framebuffers.
            scale: tile.current ? 1.07 : 1.0

            Behavior on scale {
                NumberAnimation {
                    duration: tile.theme.motion.standard
                    easing.type: tile.theme.motion.easing
                }
            }
        }

        // What a tile looks like before (or without) art: the title itself,
        // centered. A missing poster is common enough on TMDB stubs that a
        // broken-image mark would be the wrong default.
        StyledText {
            anchors.centerIn: parent
            width: parent.width - tile.theme.space(6)
            visible: poster.status !== Image.Ready
            text: tile.title
            theme: tile.theme
            font.pixelSize: tile.fonts.cardTitle
            muted: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        // Resume bar. Inside the art on purpose — it is a property of the
        // picture ("you are here"); under the title it would read as a
        // separator between tiles.
        Rectangle {
            visible: tile.progress > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: tile.theme.borderWidth
            height: tile.theme.space(1.5)
            color: tile.theme.alpha(tile.theme.surface0, 0.8)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(tile.theme.space(0.5), parent.width * Math.min(1, tile.progress))
                color: tile.theme.accent
            }
        }

        // What does the rounding. A stroke ALONG the path stopped being
        // enough at this size: the uncovered corner nub outside the arc grows
        // with the radius — ~1 px at the first design's radius 4 (invisible,
        // measured in the doc), ~4 px at this radius 10, and a bright poster
        // corner poking past the focus ring is what the user zoomed in on.
        // So the cover is an OVERSIZED stroke in the page colour: outer
        // radius 2r with width r+hairline puts its inner edge exactly on
        // (one hairline inside) the art's rounded path, so the square image
        // corners are painted over precisely — still one ordinary rectangle
        // node, no framebuffer. Only works because everything behind a tile
        // is the hub's opaque surface0 page.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -art.radius
            radius: art.radius * 2
            color: "transparent"
            border.width: art.radius + tile.theme.borderWidth
            border.color: tile.theme.surface0
        }

        // The ring, over the cover so the cover's inner hairline of overlap
        // never shows. Focus brightens it to the accent; at rest it is a
        // hairline the eye reads as the poster's own edge.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: art.radius
            border.width: tile.current ? Math.max(3, tile.theme.borderWidth * 3) : tile.theme.borderWidth
            border.color: tile.current ? tile.theme.accent : tile.theme.alpha(tile.theme.surface3, 0.6)

            Behavior on border.color {
                ColorAnimation {
                    duration: tile.theme.motion.standard
                    easing.type: tile.theme.motion.easing
                }
            }
        }
    }

    // The label, revealed by focus. Fading rather than appearing keeps the
    // reveal in the same motion vocabulary as the lift above it.
    Column {
        id: label

        anchors.top: art.bottom
        anchors.topMargin: tile.theme.space(2.5)
        width: parent.width
        spacing: 0
        opacity: tile.current ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: tile.theme.motion.standard
                easing.type: tile.theme.motion.easing
            }
        }

        StyledText {
            width: parent.width
            theme: tile.theme
            font.pixelSize: tile.fonts.cardTitle
            font.weight: Font.DemiBold
            text: tile.title
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        StyledText {
            width: parent.width
            visible: tile.subtitle !== ""
            theme: tile.theme
            font.pixelSize: tile.fonts.meta
            muted: true
            text: tile.subtitle
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
        onPointChanged: {
            if (hovered)
                tile.entered(point.scenePosition.x, point.scenePosition.y);
        }
    }

    TapHandler {
        onTapped: tile.activated()
    }
}

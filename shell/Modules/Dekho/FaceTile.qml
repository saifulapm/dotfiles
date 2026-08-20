import QtQuick
import "../../components"
import "DekhoModel.js" as Model

// One person in a cast shelf: a round face, a name, and what they played. The
// same focus model as PosterTile — the picture zooms inside a fixed frame, the
// ring goes accent — but the label is ALWAYS shown here, because a face without
// a name under it is not a control anyone can read. On a poster the art is the
// label; on a person it is not.
//
// THE CIRCLE COSTS NO FRAMEBUFFER. Clipping a picture to a shape in Qt is a
// layer.enabled/ShaderEffectSource pair per instance whichever way it is
// written (doc §5), and a cast shelf plus a crew row is a dozen of them at
// once. Instead PosterTile's stroke-over trick is used: a ring painted in the
// page colour over the square image, whose INNER edge lands exactly on the
// circle, so the four corners outside it are covered by one ordinary rectangle
// node. It only works where the colour behind the tile is flat and known,
// which is why the detail page's shelves live on the opaque sheet rather than
// on the backdrop, and why `coverColor` is a property rather than a constant.
//
// THE RING IS NOT PosterTile's 2r. Taking that formula literally at radius w/2
// gives a 2w by 2w cover — it reaches w/2 past the tile on every side, and on
// a shelf the next face is drawn after this one, so each cover painted a
// crescent out of its neighbour. The user caught it in the first build. A
// circle needs the ring to reach only past the SQUARE'S CORNER, which is at
// w/√2 ≈ 0.707w from the centre against the circle's 0.5w: an overhang of
// 0.22w puts the outer edge at 0.72w — past the corner, and small enough that
// the ring stays inside the tile with the label width below.
Item {
    id: face

    required property var theme
    // The hub's module-local type scale (Dekho.qml `fonts`).
    required property var fonts
    property string name: ""
    property string character: ""
    // "" until this shelf's `dekho api prefetch --size w185` has finished. An
    // Image pointed at a file that is not there yet caches the failure and
    // never retries, so the source is withheld rather than set optimistically.
    property string photoPath: ""
    property bool current: false
    // The flat page colour behind the tile — what the corner cover is painted
    // in. Wrong here means a visible square halo around every face.
    property color coverColor: theme.surface0

    signal activated
    // Carries the pointer's scene position so the owner can tell a moved mouse
    // from a card that scrolled under a stationary one (FilePicker's guard).
    signal entered(real sceneX, real sceneY)

    // THE CIRCLE IS NARROWER THAN THE TILE. A w185 profile wants to be drawn
    // near 185 px and no wider (past that the cache is being upscaled), but
    // "Helena Bonham Carter" does not fit in 185 px of this module's card type
    // — the first build elided half the shelf's names to "Helena Bonh…". The
    // extra third of the width goes to the label, not to the picture.
    readonly property int artSize: Math.round(width / 1.35)

    implicitWidth: theme.space(40)
    // The same reserved label strip a poster gets (fonts.labelZone, sized from
    // painted line heights rather than bare font sizes), so a face shelf and a
    // poster rail line up when they sit above each other.
    implicitHeight: artSize + theme.space(2) + fonts.labelZone

    Rectangle {
        id: art

        anchors.horizontalCenter: parent.horizontalCenter
        width: face.artSize
        height: face.artSize
        radius: width / 2
        color: face.theme.surface2
        // Scissor clipping only while the picture is actually zoomed, exactly
        // as PosterTile does it: a rectangular scissor, not a framebuffer, and
        // off for every face at rest so only the focused one pays the batch
        // break.
        clip: photo.scale > 1.0

        Image {
            id: photo

            anchors.fill: parent
            source: face.photoPath ? "file://" + face.photoPath.split("/").map(encodeURIComponent).join("/") : ""
            fillMode: Image.PreserveAspectCrop
            // The cache holds TMDB's w185 (185x278). Decoding at tile width
            // matters more here than on a poster, not less: a cast shelf and a
            // filmography grid are the two places this module can double its
            // pixmap bill without anything looking different.
            sourceSize.width: face.width
            asynchronous: true
            visible: status === Image.Ready
            scale: face.current ? 1.07 : 1.0

            Behavior on scale {
                NumberAnimation {
                    duration: face.theme.motion.standard
                    easing.type: face.theme.motion.easing
                }
            }
        }

        // TMDB has no photo for a large share of any cast list. Initials, the
        // way a contacts app answers the same gap — a broken-image mark would
        // read as a failure rather than as an absence.
        StyledText {
            anchors.centerIn: parent
            visible: photo.status !== Image.Ready
            theme: face.theme
            font.pixelSize: Math.round(face.width * 0.32)
            font.weight: Font.DemiBold
            muted: true
            text: Model.initials(face.name)
        }

        // The corner cover — see the header. Overhang 0.22w on every side, so
        // the ring's outer edge sits just past the square's corner and its
        // inner edge a hairline inside the circle.
        Rectangle {
            readonly property int overhang: Math.max(1, Math.round(art.width * 0.22))

            anchors.fill: parent
            anchors.margins: -overhang
            radius: width / 2
            color: "transparent"
            border.width: overhang + face.theme.borderWidth
            border.color: face.coverColor
        }

        // The ring, over the cover so the hairline of overlap never shows.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: art.radius
            border.width: face.current ? Math.max(3, face.theme.borderWidth * 3) : face.theme.borderWidth
            border.color: face.current ? face.theme.accent : face.theme.alpha(face.theme.surface3, 0.7)

            Behavior on border.color {
                ColorAnimation {
                    duration: face.theme.motion.standard
                    easing.type: face.theme.motion.easing
                }
            }
        }
    }

    Column {
        anchors.top: art.bottom
        anchors.topMargin: face.theme.space(2)
        width: parent.width
        spacing: 0

        StyledText {
            width: parent.width
            theme: face.theme
            font.pixelSize: face.fonts.cardTitle
            font.weight: Font.DemiBold
            color: face.current ? face.theme.accent : face.theme.textPrimary
            text: face.name
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter

            Behavior on color {
                ColorAnimation {
                    duration: face.theme.motion.standard
                    easing.type: face.theme.motion.easing
                }
            }
        }

        StyledText {
            width: parent.width
            visible: face.character !== ""
            theme: face.theme
            font.pixelSize: face.fonts.meta
            muted: true
            text: face.character
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
        onPointChanged: {
            if (hovered)
                face.entered(point.scenePosition.x, point.scenePosition.y);
        }
    }

    TapHandler {
        onTapped: face.activated()
    }
}

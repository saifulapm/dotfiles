import QtQuick
import QtQuick.Window

// omakade's qml/components/GameCard.qml, with ONE deliberate divergence.
//
// omakade rounds its cover the obvious way — `Rectangle { radius; clip: true }`
// with the Image filling it — and that is an axis-aligned scissor: the picture
// keeps its square corners and they poke past the rounded border. Ours cannot
// afford the alternatives either (rounding a picture in Qt is a framebuffer per
// instance whichever way it is done, and a grid draws sixty at once — doc §5),
// so the frame is a plain Rectangle stroked OVER the art on the rounded path:
// outer radius 2r, width r+hairline, painted in the PAGE COLOUR, so its inner
// edge lands exactly on the art's arc and the four square corners are covered
// by one ordinary rectangle node.
//
// That is why `pageColor` is a required property and not a constant, and why
// the library page behind the grid stays flat (doc §11 says the same of the
// detail sheet's faces). A card drawn over live artwork or over a gradient gets
// a visible page-coloured ring on all four corners instead.
//
// Everything else is omakade: the shadow plate offset down-right, the current
// halo, the gradient placeholder with its two circles and its mark, the bottom
// scrim with the title over it, the 2 px progress bar, the status pill, and the
// always-on caption underneath.
FocusScope {
    id: root

    required property var style
    // The flat colour behind this card — what the corner cover is painted in.
    // Wrong here means a square halo around every poster.
    required property color pageColor

    required property string title
    // "2019" and "Series" — omakade's `subtitle · hours h`, in this module's
    // vocabulary. Always shown, per the design: the art is not the label here.
    required property string subtitle
    required property string detail
    // 0..1. omakade counts percent; this module's history rows are already a
    // fraction (DekhoModel.progressOf).
    required property real progress
    // "" for no pill. The colour is the caller's because what a status MEANS
    // is the caller's — a resume point on the library page, a release state on
    // a title page.
    property string status: ""
    property color statusColor: root.style.accent
    // "" until this listing's `dekho api prefetch` has answered. An Image
    // pointed at a file that is not there yet caches the failure and never
    // retries, so the source is withheld rather than set optimistically.
    property string coverPath: ""
    property bool current: false

    signal activated

    activeFocusOnTab: true
    Accessible.name: root.title
    Accessible.description: root.subtitle + " " + root.detail
    Accessible.role: Accessible.ListItem

    Keys.onReturnPressed: event => {
        root.activated();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        root.activated();
        event.accepted = true;
    }
    Keys.onSpacePressed: event => {
        root.activated();
        event.accepted = true;
    }

    scale: root.current ? 1.018 : cardMouse.containsMouse ? 1.01 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: root.style.normal
            easing.type: root.style.easing
        }
    }

    // The current halo: a wider, softer accent frame behind the cover.
    Rectangle {
        anchors.fill: cover
        anchors.margins: root.current ? -root.style.ui(5) : 0
        radius: cover.radius + root.style.ui(4)
        color: root.current ? root.style.alpha(root.style.accent, 0.16) : "transparent"
        border.width: root.current ? root.style.ui(2) : 0
        border.color: root.style.accent
    }

    // The shadow, as a plate offset down and right rather than as a blur —
    // a DropShadow would be a framebuffer per card.
    Rectangle {
        anchors.fill: cover
        anchors.topMargin: root.style.ui(6)
        anchors.leftMargin: root.style.ui(5)
        anchors.rightMargin: -root.style.ui(5)
        anchors.bottomMargin: -root.style.ui(6)
        radius: cover.radius
        color: root.style.alpha(root.style.bg, 0.34)
    }

    Rectangle {
        id: cover

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.round(width * 1.5)
        radius: root.style.radiusSm
        // NO `clip: true` — see the header. The corner cover below does this
        // job for one rectangle node instead of a render pass.
        border.width: root.current ? root.style.ui(3) : root.style.hairline
        border.color: root.current ? root.style.accent : root.style.alpha(root.style.fg, 0.15)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: root.style.accent
            }
            GradientStop {
                position: 1.0
                color: root.style.blue
            }
        }

        Image {
            id: artwork

            anchors.fill: parent
            source: root.coverPath ? "file://" + root.coverPath.split("/").map(encodeURIComponent).join("/") : ""
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            // The cache holds TMDB's w342. Decoding at the width it is drawn
            // at is what keeps a sixty-poster grid near 10 MB of pixmaps
            // rather than 40 (doc §4).
            sourceSize.width: Math.ceil(width * Math.max(1, Screen.devicePixelRatio))
            sourceSize.height: Math.ceil(height * Math.max(1, Screen.devicePixelRatio))
            opacity: status === Image.Ready ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: root.style.normal
                    easing.type: root.style.easing
                }
            }
        }

        // The placeholder: two circles and a mark over the gradient. TMDB has
        // no poster for a great many stubs, and this is what those look like
        // rather than a broken-image glyph.
        Rectangle {
            visible: artwork.status !== Image.Ready
            width: cover.width * 0.9
            height: width
            radius: width / 2
            x: cover.width * 0.46
            y: -height * 0.22
            color: root.style.alpha(root.style.brightFg, 0.10)
            border.color: root.style.alpha(root.style.brightFg, 0.16)
        }

        Rectangle {
            visible: artwork.status !== Image.Ready
            width: cover.width * 0.7
            height: width
            radius: width / 2
            x: -width * 0.38
            y: cover.height * 0.38
            color: root.style.alpha(root.style.bg, 0.22)
        }

        Text {
            visible: artwork.status !== Image.Ready
            anchors.centerIn: parent
            text: root.title.substring(0, 1).toUpperCase()
            color: root.style.alpha(root.style.brightFg, 0.88)
            font.family: root.style.fontFamily
            font.pixelSize: Math.max(root.style.type(38), cover.width * 0.32)
            font.weight: Font.Light
        }

        // The scrim the in-art title sits on. A gradient, one node — a blur
        // would be a framebuffer.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.42
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: "transparent"
                }
                GradientStop {
                    position: 1.0
                    color: root.style.alpha(root.style.bg, 0.84)
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: root.style.ui(13)
            spacing: root.style.ui(5)

            Text {
                width: parent.width
                text: root.title.toUpperCase()
                color: root.style.brightFg
                font.family: root.style.fontFamily
                font.pixelSize: Math.max(root.style.type(12), cover.width * 0.078)
                font.weight: Font.Bold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            // Where you are in it. Inside the art on purpose — it is a
            // property of the picture; under the caption it would read as a
            // separator between cards.
            Rectangle {
                visible: root.progress > 0
                width: parent.width
                height: root.style.ui(2)
                radius: height / 2
                color: root.style.alpha(root.style.brightFg, 0.28)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.progress))
                    height: parent.height
                    radius: parent.radius
                    color: root.style.brightFg
                }
            }
        }

        Rectangle {
            visible: root.status.length > 0
            height: root.style.ui(25)
            width: statusText.implicitWidth + root.style.ui(18)
            radius: height / 2
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: root.style.ui(9)
            color: root.style.alpha(root.statusColor, 0.82)
            border.color: root.style.alpha(root.style.brightFg, 0.20)

            Text {
                id: statusText

                anchors.centerIn: parent
                text: root.status.toUpperCase()
                color: root.style.brightFg
                font.family: root.style.fontFamily
                font.pixelSize: root.style.type(8)
                font.weight: Font.Bold
            }
        }

        // WHAT DOES THE ROUNDING, and the reason this whole card is drawn on a
        // flat page. Declared last inside the cover so it paints over the
        // scrim's and the pill's own square corners as well as the art's.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -cover.radius
            radius: cover.radius * 2
            color: "transparent"
            border.width: cover.radius + root.style.hairline
            border.color: root.pageColor
        }

        // The border, over the cover so the cover's hairline of overlap never
        // shows. omakade draws it as the cover Rectangle's own border; here it
        // has to come after.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: cover.radius
            border.width: root.current ? root.style.ui(3) : root.style.hairline
            border.color: root.current ? root.style.accent : root.style.alpha(root.style.fg, 0.15)

            Behavior on border.color {
                ColorAnimation {
                    duration: root.style.normal
                    easing.type: root.style.easing
                }
            }
        }
    }

    // ALWAYS ON, which is the decision that separates this design from the one
    // it replaces. The old tile revealed its label only on focus and let the
    // art be the label at rest; omakade names every card, and the grid reserves
    // the room for it in `cellHeight` so nothing reflows.
    Column {
        anchors.top: cover.bottom
        anchors.topMargin: root.style.ui(10)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.style.ui(3)

        Text {
            width: parent.width
            text: root.title
            color: root.style.fg
            font.family: root.style.fontFamily
            font.pixelSize: root.style.type(13)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            spacing: root.style.ui(7)

            Text {
                visible: root.subtitle !== ""
                text: root.subtitle
                color: root.style.muted
                font.family: root.style.fontFamily
                font.pixelSize: root.style.type(10)
            }
            Text {
                visible: root.subtitle !== "" && root.detail !== ""
                text: "·"
                color: root.style.alpha(root.style.fg, 0.32)
                font.pixelSize: root.style.type(10)
            }
            Text {
                visible: root.detail !== ""
                text: root.detail
                color: root.style.muted
                font.family: root.style.fontFamily
                font.pixelSize: root.style.type(10)
            }
        }
    }

    MouseArea {
        id: cardMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.activated();
        }
    }
}

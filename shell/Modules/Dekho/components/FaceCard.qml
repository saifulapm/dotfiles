import QtQuick
import QtQuick.Window
import "../DekhoModel.js" as Model

// One person in a cast shelf, in omakade's card language — the same hover lift,
// the same focus ring, the same always-on label — over the ring maths the old
// FaceTile worked out and doc §11 explains.
//
// THE CIRCLE COSTS NO FRAMEBUFFER. Clipping a picture to a shape in Qt is a
// layer/ShaderEffectSource pair per instance whichever way it is written, and a
// cast shelf is a dozen at once. So the corners are covered by a ring painted
// in the page colour whose inner edge lands on the circle.
//
// AND THE RING IS NOT PosterCard's 2r. Taken literally at radius w/2 that gives
// a 2w by 2w cover reaching half a face past the tile, and on a shelf the next
// delegate is drawn after this one — every cover ate a crescent out of its
// neighbour, which the user caught in the first build. A circle only needs the
// ring to reach past the SQUARE'S CORNER, at w/√2 ≈ 0.707w against the circle's
// 0.5w: an overhang of 0.22w puts the outer edge at 0.72w, past the corner and
// still inside the tile.
//
// The circle is also narrower than the tile. w185 wants to be drawn near 185 px
// and no wider, but "Helena Bonham Carter" does not fit in 185 px of this type
// — the extra third goes to the label, not to the picture.
FocusScope {
    id: root

    required property var style
    required property color pageColor
    required property string name
    // What they played, or what they did. "" is fine.
    property string character: ""
    property string photoPath: ""
    property bool current: false

    signal activated

    readonly property int artSize: Math.round(width / 1.35)

    activeFocusOnTab: true
    Accessible.name: root.name
    Accessible.description: root.character
    Accessible.role: Accessible.Button

    implicitWidth: style.ui(150)
    implicitHeight: artSize + style.ui(10) + style.ui(54)

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

    scale: root.activeFocus ? 1.018 : faceMouse.containsMouse ? 1.01 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: root.style.normal
            easing.type: root.style.easing
        }
    }

    Rectangle {
        id: art

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.artSize
        height: root.artSize
        radius: width / 2
        color: root.style.raised

        Image {
            id: photo

            anchors.fill: parent
            source: root.photoPath ? "file://" + root.photoPath.split("/").map(encodeURIComponent).join("/") : ""
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Math.ceil(width * Math.max(1, Screen.devicePixelRatio))
            sourceSize.height: Math.ceil(height * Math.max(1, Screen.devicePixelRatio))
            visible: status === Image.Ready
        }

        // TMDB has no photo for a large share of any cast list. Initials, the
        // way a contacts app answers the same gap — a broken-image mark would
        // read as a failure rather than as an absence.
        Text {
            anchors.centerIn: parent
            visible: photo.status !== Image.Ready
            text: Model.initials(root.name)
            color: root.style.muted
            font.family: root.style.fontFamily
            font.pixelSize: Math.round(art.width * 0.32)
            font.weight: Font.DemiBold
        }

        // The corner cover — see the header for the 0.22 rather than PosterCard's r.
        Rectangle {
            readonly property int overhang: Math.max(1, Math.round(art.width * 0.22))

            anchors.fill: parent
            anchors.margins: -overhang
            radius: width / 2
            color: "transparent"
            border.width: overhang + root.style.hairline
            border.color: root.pageColor
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: art.radius
            border.width: root.activeFocus ? root.style.ui(2) : root.style.hairline
            border.color: root.activeFocus ? root.style.accent : root.style.alpha(root.style.fg, 0.15)

            Behavior on border.color {
                ColorAnimation {
                    duration: root.style.normal
                    easing.type: root.style.easing
                }
            }
        }
    }

    Column {
        anchors.top: art.bottom
        anchors.topMargin: root.style.ui(10)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.style.ui(3)

        Text {
            width: parent.width
            text: root.name
            color: root.activeFocus ? root.style.accent : root.style.fg
            font.family: root.style.fontFamily
            font.pixelSize: root.style.type(11)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: root.character !== ""
            text: root.character
            color: root.style.muted
            font.family: root.style.fontFamily
            font.pixelSize: root.style.type(9)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: faceMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.activated();
        }
    }
}

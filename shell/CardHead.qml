import QtQuick

// A card's header on board 2: an icon circle, a bold 15 px title over a muted detail, and the clock at the right.
Item {
    id: head

    // A Symbols Nerd Font glyph for the circle, or an app's icon with a letter behind it for when it fails.
    property string glyph: ""
    property string image: ""
    property string letter: ""
    property string title: ""
    property string detail: ""
    property string clock: ""
    property color ink: "white"
    property color muted: "gray"
    property color danger: "red"
    // The danger tone colours the circle's glyph, as a red alert or a stop does.
    property bool alarm: false
    property string font: ""
    readonly property alias circleItem: circle
    readonly property alias iconImage: picture
    readonly property alias letterItem: letterText
    readonly property alias titleItem: titleText
    readonly property alias detailItem: detailText
    readonly property alias clockItem: clockText
    implicitHeight: Math.max(circle.height, words.implicitHeight)

    Rectangle {
        id: circle
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        radius: 18
        color: Qt.alpha(head.ink, 0.11)

        Image {
            id: picture
            anchors.centerIn: parent
            visible: source != "" && status === Image.Ready
            source: head.glyph === "" ? head.image : ""
            sourceSize.width: 20
            sourceSize.height: 20
        }

        Text {
            id: letterText
            anchors.centerIn: parent
            visible: !picture.visible
            textFormat: Text.PlainText
            text: head.glyph !== "" ? head.glyph : head.letter
            color: head.alarm ? head.danger : head.ink
            font.family: head.glyph !== "" ? "Symbols Nerd Font Mono" : head.font
            font.pixelSize: head.glyph !== "" ? 18 : 15
            font.weight: Font.DemiBold
        }
    }

    Column {
        id: words
        x: circle.width + 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, head.width - x - clockText.implicitWidth - 12)
        spacing: 2

        Text {
            id: titleText
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            text: head.title
            color: head.ink
            font.family: head.font
            font.pixelSize: 15
            font.weight: Font.Bold
        }

        Text {
            id: detailText
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            text: head.detail
            color: head.muted
            font.family: head.font
            font.pixelSize: 12
        }
    }

    Text {
        id: clockText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: head.clock
        color: head.ink
        font.family: head.font
        font.pixelSize: 13
        font.weight: Font.Bold
        font.features: { "tnum": 1 }
    }
}

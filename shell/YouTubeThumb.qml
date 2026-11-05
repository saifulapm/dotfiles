import QtQuick
import QtQuick.Effects

// A row's 16:9 thumbnail over a grey tile: the picture draws once its file has decoded, at no more than twice its drawn size; until then, and for a row with no file, the tile shows.
Item {
    id: thumb

    property string source: ""
    property color fill: "transparent"
    property real radius: 0
    readonly property bool shown: image.visible

    function drawn() {
        return {
            shown: shown,
            file: shown ? String(image.source).split("/").pop() : "",
            placeholder: shown ? "" : "tile",
            width: width,
            height: height,
            decodedWidth: image.implicitWidth,
            decodedHeight: image.implicitHeight
        };
    }

    Rectangle {
        anchors.fill: parent
        radius: thumb.radius
        color: thumb.fill
    }
    Image {
        id: image
        anchors.fill: parent
        visible: status === Image.Ready
        source: thumb.width > 0 && thumb.height > 0 ? thumb.source : ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        // By height alone: a 16:9 picture covering its box by width can decode taller than twice its height.
        sourceSize.height: Math.ceil(thumb.height * 2)
        // The tile is rounded, so its picture is masked to the same radius.
        layer.enabled: thumb.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        radius: thumb.radius
        layer.enabled: true
    }
}

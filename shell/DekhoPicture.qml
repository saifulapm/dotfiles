import QtQuick
import QtQuick.Effects

// One TMDB picture over its place's empty mark: drawn once prefetch has its file on disk and it has decoded, at no more than twice its drawn size; until then, and for a path with no file, the mark beneath shows.
Item {
    id: picture

    required property var dekho
    required property string size
    property var path: null
    // Artboard's places are rounded, so its picture is masked to the same radius.
    property real radius: 0
    readonly property bool shown: image.visible

    function drawn() {
        return {
            shown: shown,
            file: shown ? String(image.source).split("/").pop() : "",
            width: width,
            height: height,
            radius: radius,
            decodedWidth: image.implicitWidth,
            decodedHeight: image.implicitHeight
        };
    }

    Image {
        id: image
        anchors.fill: parent
        visible: status === Image.Ready
        source: picture.width > 0 && picture.height > 0 ? picture.dekho.picture(picture.size, picture.path) : ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.ceil(picture.width * 2)
        sourceSize.height: Math.ceil(picture.height * 2)
        layer.enabled: picture.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        radius: picture.radius
        layer.enabled: true
    }
}

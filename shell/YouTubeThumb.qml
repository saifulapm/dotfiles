import QtQuick
import QtQuick.Effects

// A row's 16:9 thumbnail over its theme's placeholder, Paper's hatch, Artboard's grey tile or Blueprint's crossed box: the picture draws once its file has decoded, at no more than twice its drawn size; until then, and for a row with no file, the placeholder shows.
Item {
    id: thumb

    property string source: ""
    // hatched, tile or crossed, as each board draws a thumbnail with no picture.
    property string kind: "tile"
    property color fill: "transparent"
    // The placeholder's hatch or cross, and its 1 px edge.
    property color stroke: "gray"
    property color edge: "gray"
    property real radius: 0
    readonly property bool shown: image.visible

    function drawn() {
        return {
            shown: shown,
            file: shown ? String(image.source).split("/").pop() : "",
            placeholder: shown ? "" : kind,
            width: width,
            height: height,
            decodedWidth: image.implicitWidth,
            decodedHeight: image.implicitHeight
        };
    }

    onKindChanged: lines.requestPaint()
    onStrokeChanged: lines.requestPaint()

    Rectangle {
        anchors.fill: parent
        radius: thumb.radius
        color: thumb.fill
        border.width: thumb.kind === "tile" ? 0 : 1
        border.color: thumb.edge
    }
    // Paper's hatch runs bottom-left to top-right 6 px apart; Blueprint crosses its box corner to corner.
    Canvas {
        id: lines
        anchors.fill: parent
        anchors.margins: 1
        visible: thumb.kind !== "tile" && !thumb.shown
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = thumb.stroke;
            ctx.lineWidth = 1;
            ctx.beginPath();
            if (thumb.kind === "hatched") {
                for (let x = 5.5 - height; x < width; x += 8.5) {
                    ctx.moveTo(x, height);
                    ctx.lineTo(x + height, 0);
                }
            } else {
                ctx.moveTo(0, 0);
                ctx.lineTo(width, height);
                ctx.moveTo(0, height);
                ctx.lineTo(width, 0);
            }
            ctx.stroke();
        }
    }
    Image {
        id: image
        anchors.fill: parent
        visible: status === Image.Ready
        source: thumb.width > 0 && thumb.height > 0 ? thumb.source : ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        // By height alone: a 16:9 picture covering Paper's 72x40 by width would decode 81 px high, past twice 40.
        sourceSize.height: Math.ceil(thumb.height * 2)
        // Artboard's tile is rounded, so its picture is masked to the same radius.
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

import Quickshell.Io
import QtQuick

// One theme's paper, drawn to this item's own size.
Item {
    id: fill

    property var tokens: null
    // The dir that holds shaders/<name>.frag.qsb.
    property string dir: ""
    // Scales the dot spacing, the grid's cells and the crop marks; 1 is the desktop's paper.
    property real period: 1
    // Opaque at rest; a fill whose ancestor fades must blend, or qt_Opacity darkens it instead.
    property bool blending: opacity < 1
    // flat and gradient stay the plain fill below.
    readonly property string shader: ({ grain: "grain", dots: "dots", grid: "grid" })[tokens?.primitive.paper] ?? ""
    property string shaderUrl: ""
    property bool shaderFailed: false
    readonly property bool ready: shader === "" || shaderFailed || effect.item !== null

    // The shader paints the whole fill, so the fill only shows until it loads; both at once would fade twice.
    Rectangle {
        anchors.fill: parent
        visible: effect.item === null
        color: fill.tokens?.color.paper ?? "transparent"
    }

    // A missing .qsb crashes qs, so the effect gets a shader only once this read of it succeeds.
    FileView {
        path: fill.shader ? fill.dir + "/shaders/" + fill.shader + ".frag.qsb" : ""
        onPathChanged: {
            fill.shaderUrl = "";
            fill.shaderFailed = false;
        }
        onLoaded: fill.shaderUrl = "file://" + path
        onLoadFailed: fill.shaderFailed = true
    }

    // A ShaderEffect with no fragmentShader runs Qt's default one, which wants a source texture.
    Loader {
        id: effect
        anchors.fill: parent
        // Null tokens drop the effect before its uniforms read them, so a cleared fill holds no ShaderEffect.
        active: fill.shaderUrl !== "" && fill.tokens !== null

        sourceComponent: ShaderEffect {
            blending: fill.blending
            fragmentShader: fill.shaderUrl
            property size outputSize: Qt.size(width, height)
            property color base: fill.tokens.color.paper
            property color accent: fill.tokens.color.accent
            property color dotColor: fill.tokens.paper.dot ?? "transparent"
            property real grain: fill.tokens.paper.grain ?? 0
            property real spacing: (fill.tokens.paper.spacing ?? 16) * fill.period
            property real minor: (fill.tokens.paper.minor ?? 16) * fill.period
            property real major: (fill.tokens.paper.major ?? 80) * fill.period
            property real minorAlpha: fill.tokens.paper.minor_alpha ?? 0
            property real majorAlpha: fill.tokens.paper.major_alpha ?? 0
        }
    }

    // Blueprint's crop marks: a 14 px L in 1 px accent, 8 px in from each corner, on any grid paper, both scaled by period.
    Repeater {
        model: fill.tokens?.primitive.paper === "grid" ? 4 : 0

        Item {
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            readonly property real inset: 8 * fill.period
            readonly property real length: 14 * fill.period
            x: atRight ? fill.width - inset - length : inset
            y: atBottom ? fill.height - inset - length : inset
            width: length
            height: length

            Rectangle {
                x: parent.atRight ? parent.length - 1 : 0
                width: 1
                height: parent.length
                color: fill.tokens.color.accent
            }

            Rectangle {
                y: parent.atBottom ? parent.length - 1 : 0
                width: parent.length
                height: 1
                color: fill.tokens.color.accent
            }
        }
    }
}

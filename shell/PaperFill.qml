import Quickshell.Io
import QtQuick

// The paper, Artboard's dot grid in the scheme's line colour, drawn to this item's own size.
Item {
    id: fill

    property var tokens: null
    // The dir that holds shaders/dots.frag.qsb.
    property string dir: ""
    // Scales the dot spacing; 1 is the desktop's paper.
    property real period: 1
    // Opaque at rest; a fill whose ancestor fades must blend, or qt_Opacity darkens it instead.
    property bool blending: opacity < 1
    property string shaderUrl: ""
    property bool shaderFailed: false
    readonly property bool ready: tokens === null || shaderFailed || effect.item !== null

    // The shader paints the whole fill, so the fill only shows until it loads; both at once would fade twice.
    Rectangle {
        anchors.fill: parent
        visible: effect.item === null
        color: fill.tokens?.color.paper ?? "transparent"
    }

    // A missing .qsb crashes qs, so the effect gets a shader only once this read of it succeeds; a fill with no tokens reads none, so a new sheet builds its shader before it reports ready.
    FileView {
        path: fill.tokens ? fill.dir + "/shaders/dots.frag.qsb" : ""
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
            property color dotColor: fill.tokens.paper.dot ?? "transparent"
            property real spacing: (fill.tokens.paper.spacing ?? 16) * fill.period
            property color gradeFrom: fill.tokens.paper.grade?.from ?? "transparent"
            property color gradeTo: fill.tokens.paper.grade?.to ?? "transparent"
        }
    }
}

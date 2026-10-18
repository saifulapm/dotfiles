import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// The shader has no time uniform, so the paper never redraws unless the theme or the output changes.
PanelWindow {
    id: paper

    required property var theme
    property bool swapped: false
    readonly property var tokens: theme.tokens
    // flat and gradient stay the plain fill below.
    readonly property string shader: ({ grain: "grain", dots: "dots", grid: "grid" })[tokens?.primitive.paper] ?? ""
    property string shaderUrl: ""

    // Emitted once, when this window's first frame reaches the compositor.
    signal firstFrame

    Connections {
        target: paper.swapped ? null : paper.contentItem.Window.window
        function onFrameSwapped() {
            paper.swapped = true;
            paper.firstFrame();
        }
    }

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "dots-paper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: theme.color.paper ?? "transparent"
    }

    // A missing .qsb crashes qs, so the effect gets a shader only once this read of it succeeds.
    FileView {
        path: paper.shader ? paper.theme.dir + "/shaders/" + paper.shader + ".frag.qsb" : ""
        onPathChanged: paper.shaderUrl = ""
        onLoaded: paper.shaderUrl = "file://" + path
    }

    // A ShaderEffect with no fragmentShader runs Qt's default one, which wants a source texture.
    Loader {
        anchors.fill: parent
        active: paper.shaderUrl !== ""

        sourceComponent: ShaderEffect {
            blending: false
            fragmentShader: paper.shaderUrl
            property size outputSize: Qt.size(width, height)
            property color base: paper.theme.color.paper
            property color accent: paper.theme.color.accent
            property color dotColor: paper.tokens.paper.dot ?? "transparent"
            property real grain: paper.tokens.paper.grain ?? 0
            property real spacing: paper.tokens.paper.spacing ?? 16
            property real minor: paper.tokens.paper.minor ?? 16
            property real major: paper.tokens.paper.major ?? 80
            property real minorAlpha: paper.tokens.paper.minor_alpha ?? 0
            property real majorAlpha: paper.tokens.paper.major_alpha ?? 0
        }
    }

    // Blueprint's crop marks: a 14 px L in 1 px accent, 8 px in from each screen corner, on any grid paper.
    Repeater {
        model: paper.tokens?.primitive.paper === "grid" ? 4 : 0

        Item {
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            x: atRight ? paper.width - 8 - 14 : 8
            y: atBottom ? paper.height - 8 - 14 : 8
            width: 14
            height: 14

            Rectangle {
                x: parent.atRight ? 13 : 0
                width: 1
                height: 14
                color: paper.theme.color.accent
            }

            Rectangle {
                y: parent.atBottom ? 13 : 0
                width: 14
                height: 1
                color: paper.theme.color.accent
            }
        }
    }
}

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// The shader has no time uniform, so the paper never redraws unless the theme or the output changes.
PanelWindow {
    id: paper

    required property var theme
    property bool swapped: false

    // The back sheet takes each new theme, so the sheet on screen never rebuilds its shader.
    property Item front: sheetA
    readonly property Item back: front === sheetA ? sheetB : sheetA
    // The outgoing theme's motion picks the transition; "" while none runs.
    property string kind: ""
    property bool waiting: false

    // Emitted once, when this window's first frame reaches the compositor.
    signal firstFrame

    Connections {
        target: paper.swapped ? null : paper.contentItem.Window.window
        function onFrameSwapped() {
            paper.swapped = true;
            paper.firstFrame();
        }
    }

    Connections {
        target: paper.theme
        function onTokensChanged() {
            paper.take(paper.theme.tokens);
        }
    }

    Connections {
        target: paper.back
        function onReadyChanged() {
            paper.play();
        }
    }

    Component.onCompleted: take(theme.tokens)

    function take(t) {
        if (!t)
            return;
        // A switch during a transition ends it first, so the comparison below is with what is now on screen.
        if (kind) {
            slide.stop();
            zoom.stop();
            scan.stop();
            finish();
        }
        // The first tokens, or the same theme again, replace the paper with no transition.
        if (!front.tokens || front.tokens.name === t.name) {
            front.tokens = t;
            return;
        }
        kind = ({ snappy: "slide", spring: "zoom", linear: "scan" })[front.tokens.primitive.motion] ?? "cut";
        // The back sheet waits off screen or under the front one, so its shader rebuild never shows.
        back.offset = kind === "slide" ? height : 0;
        back.z = kind === "slide" ? 1 : 0;
        front.z = kind === "slide" ? 0 : 1;
        // ready can flicker true while the new tokens bind, so play() ignores it until they have.
        waiting = false;
        back.tokens = t;
        back.visible = true;
        waiting = true;
        play();
    }

    function play() {
        if (!waiting || !back.ready)
            return;
        waiting = false;
        if (kind === "cut")
            finish();
        else
            ({ slide: slide, zoom: zoom, scan: scan })[kind].start();
    }

    function finish() {
        const outgoing = front;
        front = back;
        front.offset = 0;
        outgoing.visible = false;
        outgoing.opacity = 1;
        outgoing.offset = 0;
        outgoing.cut = 0;
        // The hidden sheet drops its ShaderEffect, so idle holds one; the next switch rebuilds it unseen.
        outgoing.shaderUrl = "";
        outgoing.tokens = null;
        canvas.scale = 1;
        kind = "";
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

    // Fills the edges the zoom pulls the canvas away from.
    Rectangle {
        anchors.fill: parent
        visible: paper.kind === "zoom"
        color: paper.back.tokens?.color.paper ?? "transparent"
    }

    Item {
        id: canvas
        anchors.fill: parent

        Sheet {
            id: sheetA
        }

        Sheet {
            id: sheetB
            visible: false
        }

        Rectangle {
            visible: paper.kind === "scan"
            z: 2
            y: paper.front.cut - 1
            width: paper.width
            height: 2
            color: paper.front.tokens?.color.accent ?? "transparent"
        }
    }

    // Paper: the new sheet slides up from the bottom edge and the old one is pulled away beneath it.
    ParallelAnimation {
        id: slide
        onFinished: paper.finish()

        NumberAnimation {
            target: paper.back
            property: "offset"
            to: 0
            duration: 220
            easing.type: Easing.OutExpo
        }
        NumberAnimation {
            target: paper.front
            property: "offset"
            from: 0
            to: -paper.height / 4
            duration: 220
            easing.type: Easing.OutExpo
        }
    }

    // Artboard: the canvas zooms out 3% while the sheets cross-fade, then springs back, in a fixed 220 ms.
    ParallelAnimation {
        id: zoom
        onFinished: paper.finish()

        SequentialAnimation {
            NumberAnimation {
                target: canvas
                property: "scale"
                to: 0.97
                duration: 85
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: canvas
                property: "scale"
                to: 1
                duration: 135
                easing.type: Easing.OutBack
                easing.overshoot: 2.5
            }
        }
        // The old sheet fades out over the new one, so the new one loads its shader unseen.
        NumberAnimation {
            target: paper.front
            property: "opacity"
            from: 1
            to: 0
            duration: 220
        }
    }

    // Blueprint: a scan line sweeps down and the new sheet shows above it.
    NumberAnimation {
        id: scan
        target: paper.front
        property: "cut"
        from: 0
        to: paper.height
        duration: 220
        onFinished: paper.finish()
    }

    // One theme's paper. cut hides its top rows, for the scan line.
    component Sheet: Item {
        id: sheet

        property var tokens: null
        property real offset: 0
        property real cut: 0
        // flat and gradient stay the plain fill below.
        readonly property string shader: ({ grain: "grain", dots: "dots", grid: "grid" })[tokens?.primitive.paper] ?? ""
        property string shaderUrl: ""
        property bool shaderFailed: false
        readonly property bool ready: shader === "" || shaderFailed || effect.item !== null

        y: offset + cut
        width: paper.width
        height: paper.height - cut
        clip: cut > 0

        Item {
            y: -sheet.cut
            width: paper.width
            height: paper.height

            Rectangle {
                anchors.fill: parent
                color: sheet.tokens?.color.paper ?? "transparent"
            }

            // A missing .qsb crashes qs, so the effect gets a shader only once this read of it succeeds.
            FileView {
                path: sheet.shader ? paper.theme.dir + "/shaders/" + sheet.shader + ".frag.qsb" : ""
                onPathChanged: {
                    sheet.shaderUrl = "";
                    sheet.shaderFailed = false;
                }
                onLoaded: sheet.shaderUrl = "file://" + path
                onLoadFailed: sheet.shaderFailed = true
            }

            // A ShaderEffect with no fragmentShader runs Qt's default one, which wants a source texture.
            Loader {
                id: effect
                anchors.fill: parent
                active: sheet.shaderUrl !== ""

                sourceComponent: ShaderEffect {
                    // Opaque at rest; a fading sheet must blend, or qt_Opacity darkens it instead.
                    blending: sheet.opacity < 1
                    fragmentShader: sheet.shaderUrl
                    property size outputSize: Qt.size(width, height)
                    property color base: sheet.tokens.color.paper
                    property color accent: sheet.tokens.color.accent
                    property color dotColor: sheet.tokens.paper.dot ?? "transparent"
                    property real grain: sheet.tokens.paper.grain ?? 0
                    property real spacing: sheet.tokens.paper.spacing ?? 16
                    property real minor: sheet.tokens.paper.minor ?? 16
                    property real major: sheet.tokens.paper.major ?? 80
                    property real minorAlpha: sheet.tokens.paper.minor_alpha ?? 0
                    property real majorAlpha: sheet.tokens.paper.major_alpha ?? 0
                }
            }

            // Blueprint's crop marks: a 14 px L in 1 px accent, 8 px in from each screen corner, on any grid paper.
            Repeater {
                model: sheet.tokens?.primitive.paper === "grid" ? 4 : 0

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
                        color: sheet.tokens.color.accent
                    }

                    Rectangle {
                        y: parent.atBottom ? 13 : 0
                        width: 14
                        height: 1
                        color: sheet.tokens.color.accent
                    }
                }
            }
        }
    }
}

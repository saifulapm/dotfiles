import Quickshell
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
        // The hidden sheet drops its ShaderEffect with its tokens, so idle holds one; the next switch rebuilds it unseen.
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

    // Fills the edges the zoom pulls the canvas away from, blended like the sheets so the edge never runs ahead.
    Rectangle {
        anchors.fill: parent
        visible: paper.kind === "zoom"
        color: paper.back.tokens?.color.paper ?? "transparent"

        Rectangle {
            anchors.fill: parent
            opacity: paper.front.opacity
            color: paper.front.tokens?.color.paper ?? "transparent"
        }
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
        readonly property bool ready: fill.ready

        y: offset + cut
        width: paper.width
        height: paper.height - cut
        clip: cut > 0

        PaperFill {
            id: fill
            y: -sheet.cut
            width: paper.width
            height: paper.height
            tokens: sheet.tokens
            dir: paper.theme.dir
            // The zoom fades the sheet, not the fill, so the fill blends by the sheet's opacity.
            blending: sheet.opacity < 1
        }
    }
}

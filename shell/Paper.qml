import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import "." as Root
import "lib/hifi.mjs" as H

// The shader has no time uniform, so the paper never redraws unless the theme or the output changes.
PanelWindow {
    id: paper

    required property var theme
    // The day's passage, which shell.qml makes after the first frame; each sheet draws it.
    property var passage: null
    property bool swapped: false

    // The back sheet takes each new theme, so the sheet on screen never rebuilds its shader.
    property Item front: sheetA
    readonly property Item back: front === sheetA ? sheetB : sheetA
    // The outgoing theme's motion picks the transition, or Hi-Fi's sweep when Hi-Fi is either side; "" while none runs.
    property string kind: ""
    property bool waiting: false
    // How far through its 220 ms the sweep is, 0 to 1; the pointer and the lamps' warmth follow from it.
    property real sweepTime: 0
    readonly property var swept: H.sweepAt(sweepTime)
    // The sweep pointer's x as a fraction of the width; null while no sweep runs.
    readonly property var pointer: kind === "sweep" ? swept.pointer : null

    onSweptChanged: {
        if (kind === "sweep")
            Root.State.warmth = swept.warmth;
    }

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
            sweep.stop();
            finish();
        }
        // The first tokens, or the same theme again, replace the paper with no transition.
        if (!front.tokens || front.tokens.name === t.name) {
            front.tokens = t;
            return;
        }
        kind = H.switchKind(front.tokens, t);
        // The bar takes the new tokens in this same event, so its lamps draw unlit before the first frame of the sweep.
        if (kind === "sweep") {
            sweepTime = 0;
            Root.State.warmth = 0;
        }
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
            ({ slide: slide, zoom: zoom, scan: scan, sweep: sweep })[kind].start();
    }

    // What each sheet that shows a passage draws, the one on screen first.
    function passageDrawn() {
        return [front, back].filter(s => s.visible && s.words).map(s => s.words.drawn());
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
        Root.State.warmth = 1;
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

        // Hi-Fi's tuning pointer, in Hi-Fi's danger red whichever side of the switch Hi-Fi is on.
        Item {
            readonly property color red: [paper.front.tokens, paper.back.tokens].find(t => t?.primitive.motion === "dial")?.color.danger ?? "transparent"

            visible: paper.kind === "sweep"
            z: 2
            x: paper.front.cutLeft - 1
            width: 2
            height: paper.height

            RectangularShadow {
                anchors.fill: parent
                blur: 8
                color: Qt.alpha(parent.red, 0.7)
            }

            Rectangle {
                anchors.fill: parent
                color: parent.red
            }
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
            duration: 220 * Root.State.slowdown
            easing.type: Easing.OutExpo
        }
        NumberAnimation {
            target: paper.front
            property: "offset"
            from: 0
            to: -paper.height / 4
            duration: 220 * Root.State.slowdown
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
                duration: 85 * Root.State.slowdown
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: canvas
                property: "scale"
                to: 1
                duration: 135 * Root.State.slowdown
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
            duration: 220 * Root.State.slowdown
        }
    }

    // Blueprint: a scan line sweeps down and the new sheet shows above it.
    NumberAnimation {
        id: scan
        target: paper.front
        property: "cut"
        from: 0
        to: paper.height
        duration: 220 * Root.State.slowdown
        onFinished: paper.finish()
    }

    // Hi-Fi: a red tuning pointer crosses left to right, easing in and out, and the new sheet shows left of it.
    NumberAnimation {
        id: sweep
        target: paper
        property: "sweepTime"
        from: 0
        to: 1
        duration: 220 * Root.State.slowdown
        onFinished: paper.finish()
    }

    // One theme's paper. cut hides its top rows, for the scan line; cutLeft hides its left columns, for the sweep.
    component Sheet: Item {
        id: sheet

        property var tokens: null
        property real offset: 0
        property real cut: 0
        readonly property real cutLeft: paper.kind === "sweep" && sheet === paper.front ? paper.swept.pointer * paper.width : 0
        readonly property bool ready: fill.ready
        readonly property Item words: passageLoader.item

        x: cutLeft
        y: offset + cut
        width: paper.width - cutLeft
        height: paper.height - cut
        clip: cut > 0 || cutLeft > 0

        PaperFill {
            id: fill
            x: -sheet.cutLeft
            y: -sheet.cut
            width: paper.width
            height: paper.height
            tokens: sheet.tokens
            dir: paper.theme.dir
            // The zoom fades the sheet, not the fill, so the fill blends by the sheet's opacity.
            blending: sheet.opacity < 1
        }

        // Inside the sheet, so a theme switch carries the passage with the slide, zoom, scan or sweep; a sheet with no tokens draws none.
        Loader {
            id: passageLoader
            x: -sheet.cutLeft
            y: -sheet.cut
            width: paper.width
            height: paper.height
            active: sheet.tokens !== null && paper.passage !== null && paper.passage.text !== null

            sourceComponent: PaperPassage {
                tokens: sheet.tokens
                passage: paper.passage
            }
        }
    }
}

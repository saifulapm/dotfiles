import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/switch.mjs" as W

// The shader has no time uniform, so the paper never redraws unless the theme or the output changes.
PanelWindow {
    id: paper

    required property var theme
    // The day's passage, which shell.qml makes after the first frame; each sheet draws it.
    property var passage: null
    // Whether this output's shown workspace holds a window, which hides the passage.
    property bool covered: false
    property bool swapped: false

    // The back sheet takes each new theme, so the sheet on screen never rebuilds its shader.
    property Item front: sheetA
    readonly property Item back: front === sheetA ? sheetB : sheetA
    // The transition W.switchKind picks for the pair, always the crossfade; "" while none runs.
    property string kind: ""
    property bool waiting: false
    // When the last transition began to play and when it ended, in ms since the epoch, so a check can time a switch without polling.
    property real startedAt: 0
    property real endedAt: 0
    // How far through its time the crossfade is, 0 to 1; the old sheet's opacity follows W.fadeAt of it.
    property real fadeTime: 0

    onFadeTimeChanged: {
        if (kind)
            front.opacity = 1 - W.fadeAt(fadeTime);
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
            fade.stop();
            finish();
        }
        // The first tokens, or the same theme again, replace the paper with no transition.
        if (!front.tokens || front.tokens.name === t.name) {
            front.tokens = t;
            return;
        }
        kind = W.switchKind(front.tokens, t);
        // The back sheet waits under the front one, so its shader rebuild never shows.
        back.z = 0;
        front.z = 1;
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
        startedAt = Date.now();
        fade.start();
    }

    // What each sheet that shows a passage draws, the one on screen first.
    function passageDrawn() {
        return [front, back].filter(s => s.visible && s.words).map(s => s.words.drawn());
    }

    function finish() {
        const outgoing = front;
        front = back;
        outgoing.visible = false;
        outgoing.opacity = 1;
        // The hidden sheet drops its ShaderEffect with its tokens, so idle holds one; the next switch rebuilds it unseen.
        outgoing.tokens = null;
        kind = "";
        endedAt = Date.now();
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
    }

    // The old sheet fades out over the new one on the spring's ease, so the new one loads its shader unseen.
    NumberAnimation {
        id: fade
        target: paper
        property: "fadeTime"
        from: 0
        to: 1
        duration: W.SWITCH.ms * Root.State.slowdown
        onFinished: paper.finish()
    }

    // One theme's paper.
    component Sheet: Item {
        id: sheet

        property var tokens: null
        readonly property bool ready: fill.ready
        readonly property Item words: passageLoader.item

        width: paper.width
        height: paper.height

        PaperFill {
            id: fill
            anchors.fill: parent
            tokens: sheet.tokens
            dir: paper.theme.dir
            // The crossfade fades the sheet, not the fill, so the fill blends by the sheet's opacity.
            blending: sheet.opacity < 1
        }

        // Inside the sheet, so a switch fades the passage with its paper; a sheet with no tokens draws none.
        Loader {
            id: passageLoader
            anchors.fill: parent
            visible: !paper.covered
            active: sheet.tokens !== null && paper.passage !== null && paper.passage.text !== null

            sourceComponent: PaperPassage {
                tokens: sheet.tokens
                passage: paper.passage
            }
        }
    }
}

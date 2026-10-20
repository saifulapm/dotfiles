import QtQuick
import "." as Root
import "lib/motion.mjs" as M

// Plays a surface's open and close on its theme's motion token; the surface's card draws the pose (agent #PQC9EDND).
Item {
    id: motion

    required property bool shown
    required property var tokens
    // False while the surface's content is still loading; its open waits, so the whole drop plays from its first frame.
    property bool ready: true
    readonly property bool open: shown && ready
    readonly property var curves: M.surfaceMotion(tokens?.primitive.motion, Root.State.slowdown)
    // How far through its open the card is drawn: 0 draws nothing, 1 is at rest.
    property real progress: 0
    readonly property var pose: curves ? M.surfacePose(curves, progress) : ({ lift: 0, scale: 1, outline: 1, fill: 1 })
    // A closing surface still draws, though it gave the keyboard back when its close began.
    readonly property bool drawing: shown || progress > 0
    readonly property bool settled: open && progress === 1
    // The ms from the last open to its rest, or -1 while it is still moving.
    property real settleMs: -1
    property real startedAt: 0
    // How far through the open its first drawn frame was, or -1 until it is drawn; near 0 means the whole drop played.
    property real firstFrame: -1

    onOpenChanged: {
        if (open) {
            startedAt = Date.now();
            settleMs = -1;
            firstFrame = -1;
        }
        play();
    }
    // A theme switch mid-motion carries on at the new theme's pace.
    onCurvesChanged: if (playing.running)
        play()
    onSettledChanged: if (settled)
        settleMs = Date.now() - startedAt

    // Called on each of the host window's frames.
    function swapped() {
        if (open && firstFrame < 0 && progress > 0)
            firstFrame = progress;
    }

    // From wherever the card is, so an open pressed again mid-close turns back, and a close mid-open sinks from there.
    function play() {
        playing.stop();
        const to = open ? 1 : 0;
        const ms = !curves ? 0 : open ? curves.openMs * (1 - progress) : curves.closeMs * progress;
        if (ms <= 0) {
            progress = to;
            return;
        }
        playing.to = to;
        playing.duration = ms;
        playing.start();
    }

    // Another surface opening ends this one's close at once, so only the new one shows.
    function cut() {
        if (!shown) {
            playing.stop();
            progress = 0;
        }
    }

    NumberAnimation {
        id: playing
        target: motion
        property: "progress"
    }
}

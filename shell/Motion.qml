import QtQuick
import "." as Root
import "lib/motion.mjs" as M

// Plays a surface's open and close on its theme's motion token; the surface's card draws the pose (agent #PQC9EDND).
Item {
    id: motion

    required property bool shown
    required property var tokens
    readonly property var curves: M.surfaceMotion(tokens?.primitive.motion, Root.State.slowdown)
    // How far through its open the card is drawn: 0 draws nothing, 1 is at rest.
    property real progress: 0
    readonly property var pose: curves ? M.surfacePose(curves, progress) : ({ lift: 0, scale: 1, outline: 1, fill: 1 })
    // A closing surface still draws, though it gave the keyboard back when its close began.
    readonly property bool drawing: shown || progress > 0
    readonly property bool settled: shown && progress === 1
    // The ms from the last open to its rest, or -1 while it is still moving.
    property real settleMs: -1
    property real startedAt: 0

    // From wherever the card is, so an open pressed again mid-close turns back, and a close mid-open sinks from there.
    onShownChanged: {
        playing.stop();
        if (shown) {
            startedAt = Date.now();
            settleMs = -1;
        }
        const to = shown ? 1 : 0;
        const ms = !curves ? 0 : shown ? curves.openMs * (1 - progress) : curves.closeMs * progress;
        if (ms <= 0) {
            progress = to;
            return;
        }
        playing.to = to;
        playing.duration = ms;
        playing.start();
    }
    onSettledChanged: if (settled)
        settleMs = Date.now() - startedAt

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

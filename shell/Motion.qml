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
    // An open from rest waits for the window's next frame to start its clock, so a slow first frame cannot eat the start.
    property bool armed: false
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
    onCurvesChanged: if (clock.running)
        play()
    onSettledChanged: if (settled)
        settleMs = Date.now() - startedAt

    // Called on each of the host window's frames.
    function swapped() {
        if (armed) {
            armed = false;
            startedAt = clock.t0 = Date.now();
        } else if (open && firstFrame < 0 && progress > 0) {
            firstFrame = progress;
        }
    }

    // From wherever the card is, so an open pressed again mid-close turns back, and a close mid-open sinks from there.
    function play() {
        clock.stop();
        armed = open && progress === 0;
        const to = open ? 1 : 0;
        const ms = !curves ? 0 : open ? curves.openMs * (1 - progress) : curves.closeMs * progress;
        if (ms <= 0) {
            armed = false;
            progress = to;
            return;
        }
        clock.p0 = progress;
        clock.p1 = to;
        clock.ms = ms;
        clock.t0 = Date.now();
        clock.start();
    }

    // Another surface opening ends this one's close at once, so only the new one shows.
    function cut() {
        if (!shown) {
            clock.stop();
            progress = 0;
        }
    }

    // Each tick sets progress from the wall clock, so a stalled frame neither eats nor stretches the motion.
    FrameAnimation {
        id: clock
        property real p0: 0
        property real p1: 0
        property real ms: 0
        property real t0: 0
        onTriggered: {
            if (motion.armed) {
                // An open that changes nothing on screen gets no frame, so the clock starts 50 ms on regardless.
                if (Date.now() - t0 < 50)
                    return;
                motion.armed = false;
                motion.startedAt = t0 = Date.now();
            }
            const t = Math.min(1, (Date.now() - t0) / ms);
            motion.progress = p0 + (p1 - p0) * t;
            if (t === 1)
                stop();
        }
    }
}

import QtQuick
import QtQuick.Effects

// One block of the island's content, sized as its own card; it enters and leaves by the theme's swap while the box morphs.
Item {
    id: part

    property bool shown: false
    // A new key while shown swaps the content in place, as a notification that replaces the last one does.
    property string key: ""
    // islandMotion's swap: {kind: blur, drop or scan, inMs, outMs, delay, blur}; null shows and hides at once.
    property var swap: null
    default property alias content: inner.data
    readonly property bool busy: run.running
    readonly property string kind: swap?.kind ?? ""
    // The clock starts below 0 by the delay and runs to 1.
    property real clock: 1
    readonly property real step: Math.max(0, Math.min(1, clock))
    // 0 to 1 as the content comes in, eased out; then 0 to 1 again as it goes out, eased in.
    readonly property real progress: kind === "scan" ? step : leaving ? step * step * step : 1 - Math.pow(1 - step, 3)
    property bool leaving: false
    // The key and mode a part gets as it loads are not a swap; an enter played then made the first panel open 20 ms slower.
    property bool armed: false
    Component.onCompleted: Qt.callLater(() => armed = true)

    visible: shown || leaving
    opacity: leaving ? 1 - progress : kind === "scan" ? 1 : progress
    scale: kind !== "blur" ? 1 : leaving ? 1 + 0.06 * progress : 0.9 + 0.1 * progress
    transformOrigin: Item.Top
    transform: Translate {
        y: part.kind === "drop" && !part.leaving ? -4 * (1 - part.progress) : 0
    }
    // The blur needs a layer, so only a part that is moving pays for one.
    layer.enabled: kind === "blur" && busy
    layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 16
        blur: (part.leaving ? part.progress : 1 - part.progress) * (part.swap?.blur ?? 0) / 16
    }

    function come() {
        leaving = false;
        run.stop();
        if (!swap || !armed) {
            clock = 1;
            return;
        }
        run.from = -swap.delay / swap.inMs;
        run.duration = swap.delay + swap.inMs;
        run.restart();
    }

    function go() {
        run.stop();
        leaving = swap !== null && armed;
        if (!leaving)
            return;
        run.from = 0;
        run.duration = swap.outMs;
        run.restart();
    }

    onShownChanged: shown ? come() : go()
    onKeyChanged: if (shown)
        come()

    NumberAnimation {
        id: run
        target: part
        property: "clock"
        to: 1
        onFinished: part.leaving = false
    }

    // Blueprint's scan reveals the content left to right.
    Item {
        clip: part.kind === "scan" && !part.leaving
        width: clip ? part.width * part.progress : part.width
        height: part.height

        Item {
            id: inner
            width: part.width
            height: part.height
        }
    }
}

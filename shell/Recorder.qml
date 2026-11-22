import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/recorder.mjs" as R

// Mod+Shift+R: the region picker's dim, drawn over the whole Surfaces window, and the wf-recorder run it starts; its bar draws inside the island.
Item {
    id: recorder

    required property var theme
    // The output the Surfaces window covers, in global logical pixels.
    required property var screen
    // The island reports this as its surface while the picker is up, and grows to this size for the bar (board 9).
    readonly property string name: "record"
    readonly property int wantWidth: 400
    readonly property bool busy: false
    implicitHeight: 64
    // The bar drawn in the island; the surfaces' window sets it.
    property var bar: null
    // The picker is up; the host gives it the keyboard.
    property bool shown: false
    readonly property bool recording: proc.running
    readonly property var out: ({ x: screen?.x ?? 0, y: screen?.y ?? 0, width: screen?.width ?? width, height: screen?.height ?? height })
    property var region: R.start(out)
    property string file: ""
    // Set when Start hides the picker; the recording starts on the next frame, so the picker is never in it.
    property bool pending: false
    // Set when the stop timer kills wf-recorder, so its notice says so.
    property bool forced: false
    readonly property string dir: Quickshell.env("DOTS_RECORDINGS_DIR") || Quickshell.env("HOME") + "/Videos/Recordings"

    // Plays only the picker's open and close; a recording runs with the picker gone.
    readonly property Root.Motion motion: Root.Motion {
        shown: recorder.shown
        tokens: recorder.theme.tokens
    }

    function toggle() {
        if (recording)
            stop();
        else if (shown)
            close();
        else
            open();
    }

    function open() {
        region = R.start(out);
        shown = true;
        forceActiveFocus();
    }

    function close() {
        shown = false;
    }

    // A second Enter or click on Start before the first has started wf-recorder starts nothing more.
    function begin() {
        if (pending || recording)
            return;
        file = dir + "/" + R.fileName(new Date());
        pending = true;
        shown = false;
        // No close plays here: the recording starts on the next frame, and a sinking picker would be in it.
        motion.cut();
    }

    // SIGINT lets wf-recorder finish the file; one that has not exited 5 s later is killed.
    function stop() {
        proc.signal(2);
        forceStop.restart();
    }

    function swapped() {
        if (!pending)
            return;
        pending = false;
        // wf-recorder makes no folders; -y keeps an existing file from blocking on a prompt, and -D takes every frame, so a still screen still fills the recording to its end.
        proc.command = ["sh", "-c", 'mkdir -p "$1" && exec wf-recorder -y -D -g "$2" -f "$3"', "sh", dir, R.geometry(region, out), file];
        proc.running = true;
    }

    // An item's box in window coordinates, or null when the bar is not made.
    function box(item) {
        if (!item)
            return null;
        const p = item.mapToItem(null, 0, 0);
        return { x: p.x, y: p.y, w: item.width, h: item.height };
    }

    function state() {
        return JSON.stringify({ picking: shown, motion: motion.curves?.kind ?? null, settleMs: motion.settleMs, settled: motion.settled, drawing: recorder.visible, recording: recording, pid: Root.State.recordingPid, region: region, step: R.STEP, file: file, size: bar?.sizeText ?? null, cancel: box(bar?.cancelButton), start: box(bar?.startButton) });
    }

    Process {
        id: proc
        onRunningChanged: Root.State.recordingSince = running ? Date.now() : 0
        // sh execs wf-recorder, so this pid is the one niri reports for its cast.
        onProcessIdChanged: Root.State.recordingPid = processId ?? 0
        // The recording ends with a notice either way, so one that failed at the start or was killed does not just vanish.
        onExited: (code, status) => {
            forceStop.stop();
            const name = recorder.file.slice(recorder.file.lastIndexOf("/") + 1);
            if (recorder.forced)
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Recorder", "Recording stopped by force", name + " may be cut short"]);
            else if (code === 0 && status === 0)
                Quickshell.execDetached(["notify-send", "-a", "Recorder", "-h", "string:x-dots-files:" + recorder.file, "Recording saved", name]);
            else
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Recorder", "Recording failed", "wf-recorder exited " + code]);
            recorder.forced = false;
        }
    }

    Root.Tick {
        id: forceStop
        interval: 5000
        onTriggered: {
            recorder.forced = true;
            proc.signal(9);
        }
    }

    Component.onCompleted: Root.State.loaded.push("recorder")
    visible: motion.drawing

    Keys.onPressed: event => {
        const k = event.key;
        const shift = event.modifiers & Qt.ShiftModifier;
        const dx = k === Qt.Key_H || k === Qt.Key_Left ? -1 : k === Qt.Key_L || k === Qt.Key_Right ? 1 : 0;
        const dy = k === Qt.Key_K || k === Qt.Key_Up ? -1 : k === Qt.Key_J || k === Qt.Key_Down ? 1 : 0;
        if (dx || dy)
            region = shift ? R.resize(region, dx, dy, out) : R.move(region, dx, dy, out);
        else if (k === Qt.Key_F)
            region = R.full(out);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter)
            begin();
        else if (k === Qt.Key_Escape)
            close();
        else
            return;
        event.accepted = true;
    }

    // Everything outside the region is dimmed to 42% black, in four bands around it.
    Repeater {
        model: [[0, 0, recorder.width, recorder.region.y], [0, recorder.region.y + recorder.region.h, recorder.width, recorder.height - recorder.region.y - recorder.region.h], [0, recorder.region.y, recorder.region.x, recorder.region.h], [recorder.region.x + recorder.region.w, recorder.region.y, recorder.width - recorder.region.x - recorder.region.w, recorder.region.h]]

        Rectangle {
            required property var modelData
            x: modelData[0]
            y: modelData[1]
            width: modelData[2]
            height: modelData[3]
            color: Qt.rgba(0, 0, 0, 0.42)
        }
    }

    Rectangle {
        x: recorder.region.x
        y: recorder.region.y
        width: recorder.region.w
        height: recorder.region.h
        color: "transparent"
        border.width: 2
        border.color: "#FFFFFF"
    }

    // A round handle centred on each corner of the region.
    Repeater {
        model: [[0, 0], [1, 0], [0, 1], [1, 1]]

        Rectangle {
            required property var modelData
            x: recorder.region.x + modelData[0] * recorder.region.w - width / 2
            y: recorder.region.y + modelData[1] * recorder.region.h - height / 2
            width: 14
            height: 14
            radius: 7
            color: "#FFFFFF"
        }
    }

    // A drag from a handle resizes the region from that corner, holding the opposite one; a drag anywhere else draws a new region from where it starts.
    MouseArea {
        anchors.fill: parent
        property var from
        onPressed: mouse => from = R.grab(recorder.region, mouse.x, mouse.y) ?? { x: mouse.x, y: mouse.y }
        onPositionChanged: mouse => recorder.region = R.span(from, { x: mouse.x, y: mouse.y }, recorder.out)
    }
}

import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/recorder.mjs" as R
import "lib/voice.mjs" as V

// Mod+Shift+R: the region picker, drawn in the Surfaces window, and the wf-recorder run it starts.
Item {
    id: recorder

    required property var theme
    // The output the Surfaces window covers, in global logical pixels.
    required property var screen
    // The picker is up; the host gives it the keyboard.
    property bool shown: false
    readonly property bool recording: proc.running
    readonly property var out: ({ x: screen?.x ?? 0, y: screen?.y ?? 0, width: screen?.width ?? width, height: screen?.height ?? height })
    property var region: R.start(out)
    property string file: ""
    // Set when Enter hides the picker; the recording starts on the next frame, so the picker is never in it.
    property bool pending: false
    readonly property string dir: Quickshell.env("DOTS_RECORDINGS_DIR") || Quickshell.env("HOME") + "/Videos/Recordings"

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: V.listLook(theme.tokens)
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

    function begin() {
        file = dir + "/" + R.fileName(new Date());
        pending = true;
        shown = false;
        // No close plays here: the recording starts on the next frame, and a sinking picker would be in it.
        motion.cut();
    }

    // SIGINT lets wf-recorder finish the file.
    function stop() {
        proc.signal(2);
    }

    function swapped() {
        if (!pending)
            return;
        pending = false;
        // wf-recorder makes no folders; -y keeps an existing file from blocking on a prompt, and -D takes every frame, so a still screen still fills the recording to its end.
        proc.command = ["sh", "-c", 'mkdir -p "$1" && exec wf-recorder -y -D -g "$2" -f "$3"', "sh", dir, R.geometry(region, out), file];
        proc.running = true;
    }

    function state() {
        // The hint as drawn, read from its key items.
        const hint = [];
        for (let i = 0; i < hintRepeater.count; i++)
            hint.push(hintRepeater.itemAt(i).keyLabel + " " + hintRepeater.itemAt(i).wordLabel);
        return JSON.stringify({ picking: shown, motion: motion.curves?.kind ?? null, settleMs: motion.settleMs, settled: motion.settled, drawing: recorder.visible, cardBox: hintCard.drawnBox(), recording: recording, region: region, step: R.STEP, file: file, hint: hint.join("  ") });
    }

    Process {
        id: proc
        onRunningChanged: Root.State.recordingSince = running ? Date.now() : 0
    }

    Component.onCompleted: Root.State.loaded.push("recorder")
    visible: motion.drawing

    Keys.onPressed: event => {
        const k = event.key;
        const shift = event.modifiers & Qt.ShiftModifier;
        const dx = k === Qt.Key_H ? -1 : k === Qt.Key_L ? 1 : 0;
        const dy = k === Qt.Key_K ? -1 : k === Qt.Key_J ? 1 : 0;
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

    // Everything outside the region is dimmed, in four bands around it.
    Repeater {
        model: [[0, 0, recorder.width, recorder.region.y], [0, recorder.region.y + recorder.region.h, recorder.width, recorder.height - recorder.region.y - recorder.region.h], [0, recorder.region.y, recorder.region.x, recorder.region.h], [recorder.region.x + recorder.region.w, recorder.region.y, recorder.width - recorder.region.x - recorder.region.w, recorder.region.h]]

        Rectangle {
            required property var modelData
            x: modelData[0]
            y: modelData[1]
            width: modelData[2]
            height: modelData[3]
            color: Qt.alpha(recorder.c.ink, 0.45)
        }
    }

    Rectangle {
        x: recorder.region.x
        y: recorder.region.y
        width: recorder.region.w
        height: recorder.region.h
        color: "transparent"
        border.width: 2
        border.color: recorder.c.accent
    }

    // The hint is a card in the theme's treatment: Paper's hard shadow and serif size, Artboard's frame label, Blueprint's chamfer and brackets.
    Root.Surface {
        id: hintCard
        x: Math.min(recorder.region.x, recorder.width - width)
        y: recorder.region.y >= height + 32 ? recorder.region.y - height - 12 : recorder.region.y + 28
        width: hintRow.implicitWidth + 28
        height: hintRow.implicitHeight + 16
        tokens: recorder.theme.tokens
        label: "Record"
        motion: recorder.motion

        Row {
            id: hintRow
            anchors.centerIn: parent
            spacing: 14

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: recorder.region.w + " × " + recorder.region.h
                color: recorder.c.ink
                font.family: recorder.fonts.display
                font.pixelSize: 20
            }

            // The keys as the launcher's legend draws them: chips in Artboard, tracked caps in Paper, brackets in Blueprint.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: recorder.look.legend("").chips ? 8 : 14

                Repeater {
                    id: hintRepeater
                    model: recorder.look.keys([["hjkl", "move"], ["⇧HJKL", "size"], ["f", "full"], ["↵", "rec"], ["esc", "cancel"]])

                    Rectangle {
                        id: keyPair
                        required property var modelData
                        readonly property string keyLabel: keyText.text
                        readonly property string wordLabel: wordText.text
                        width: pairRow.implicitWidth + (recorder.look.legend("").chips ? 14 : 0)
                        height: pairRow.implicitHeight + (recorder.look.legend("").chips ? 6 : 0)
                        radius: 6
                        color: recorder.look.chip.fill

                        Row {
                            id: pairRow
                            anchors.centerIn: parent
                            spacing: recorder.look.legend("").chips ? 6 : 5

                            Text {
                                id: keyText
                                textFormat: Text.PlainText
                                text: keyPair.modelData.key
                                color: recorder.look.chip.key
                                font.family: recorder.fonts.mono
                                font.pixelSize: recorder.look.small.size
                                font.letterSpacing: recorder.look.small.spacing
                                font.bold: true
                            }
                            Text {
                                id: wordText
                                textFormat: Text.PlainText
                                text: keyPair.modelData.word
                                color: recorder.c.muted
                                font.family: recorder.look.small.font
                                font.pixelSize: recorder.look.small.size
                                font.letterSpacing: recorder.look.small.spacing
                            }
                        }
                    }
                }
            }
        }
    }

    // A drag draws a region from where it starts.
    MouseArea {
        anchors.fill: parent
        property point from
        onPressed: mouse => from = Qt.point(mouse.x, mouse.y)
        onPositionChanged: mouse => {
            const x = Math.max(0, Math.min(from.x, mouse.x)), y = Math.max(0, Math.min(from.y, mouse.y));
            recorder.region = { x: Math.round(x), y: Math.round(y), w: Math.max(R.MIN, Math.round(Math.abs(mouse.x - from.x))), h: Math.max(R.MIN, Math.round(Math.abs(mouse.y - from.y))) };
        }
    }
}

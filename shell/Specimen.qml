import QtQuick
import "." as Root
import "lib/themes.mjs" as Lib

// One theme's desktop in miniature, from its tokens alone: its paper, margins, island, two windows and palette.
Item {
    id: specimen

    required property var tokens
    // The folder holding the paper shaders.
    required property string dir
    readonly property var c: tokens.color
    readonly property var margins: Lib.specimenMargins(tokens)
    readonly property real inset: 10
    // The room the card leaves between the preview and the palette for its name.
    property real gap: 32
    // The paper the card's switch plays over: the current theme's.
    property color under: "transparent"
    readonly property var motion: Lib.previewSwitch(Root.State.slowdown)
    // The ms from the key that started the last play to its end, or -1 while it plays.
    property real playedMs: -1
    property real playT0: 0

    // Plays the desktop's crossfade in miniature: the specimen fades in over the current paper.
    function play(t0) {
        playing.stop();
        playT0 = t0;
        playedMs = -1;
        playing.start();
    }

    width: 306
    height: column.implicitHeight
    // A card loads its specimen while the picker opens, so the detail fades in over the card's paper.
    opacity: 0
    Component.onCompleted: arrive.start()

    NumberAnimation {
        id: arrive
        target: specimen
        property: "opacity"
        to: 1
        duration: 60
    }

    // The preview, the palette and every margin as drawn, in the window's pixels, for the picker's state.
    function drawn() {
        const box = i => {
            const a = i.mapToItem(null, 0, 0);
            const b = i.mapToItem(null, i.width, i.height);
            return { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y };
        };
        const swatches = [];
        for (let i = 0; i < strip.count; i++)
            swatches.push(Object.assign(box(strip.itemAt(i)), { color: strip.itemAt(i).color.toString() }));
        return {
            preview: box(preview),
            swatches: swatches,
            left: leftNumber.text + leftTail.text,
            right: rightGoal.text + rightDate.text,
            clock: clock.text,
            terminal: terminal.lines(),
            paperReady: fill.ready,
            stage: { y: stage.y, h: stage.height, w: stage.width, opacity: stage.opacity, scale: stage.scale }
        };
    }

    Column {
        id: column
        width: parent.width
        spacing: 10

        Item {
            id: preview
            width: parent.width
            height: 196
            clip: true

            // What the card's switch plays over: the picker's own paper.
            Rectangle {
                anchors.fill: parent
                visible: playing.running
                color: specimen.under
            }

            Item {
                id: stage
                width: preview.width
                height: preview.height

                Item {
                    width: preview.width
                    height: preview.height

                    Root.PaperFill {
                        id: fill
                        anchors.fill: parent
                        tokens: specimen.tokens
                        dir: specimen.dir
                        period: 0.5
                        // The arrival and the crossfade fade the specimen and the stage, not the fill.
                        blending: specimen.opacity < 1 || stage.opacity < 1
                    }

                    Row {
                        x: specimen.inset
                        y: 7
                        Text {
                            id: leftNumber
                            textFormat: Text.PlainText
                            text: specimen.margins.number
                            color: specimen.margins.numberColor
                            font.family: specimen.margins.font
                            font.pixelSize: 6
                            font.weight: Font.Bold
                            font.letterSpacing: specimen.margins.tracking
                        }
                        Text {
                            id: leftTail
                            textFormat: Text.PlainText
                            text: specimen.margins.tail
                            color: specimen.c.muted
                            font: leftNumber.font
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: specimen.inset
                        y: 7
                        Text {
                            id: rightGoal
                            textFormat: Text.PlainText
                            text: specimen.margins.goal
                            color: specimen.margins.goalColor
                            font: leftNumber.font
                        }
                        Text {
                            id: rightDate
                            textFormat: Text.PlainText
                            text: specimen.margins.date
                            color: specimen.c.muted
                            font.family: specimen.margins.font
                            font.pixelSize: 6
                            font.letterSpacing: specimen.margins.tracking
                        }
                    }

                    // The ink rules run along the margin, broken by the island.
                    Repeater {
                        model: specimen.margins.rules ? [specimen.inset, 186] : []
                        Rectangle {
                            required property var modelData
                            x: modelData
                            y: 19
                            width: 110
                            height: 1
                            color: specimen.c.ink
                        }
                    }

                    Root.Surface {
                        id: chip
                        x: 127
                        y: 5
                        width: 52
                        height: 16
                        tokens: specimen.tokens
                        role: "chip"
                    }

                    Text {
                        id: clock
                        textFormat: Text.PlainText
                        anchors.centerIn: chip
                        text: specimen.margins.clock
                        color: chip.style.text
                        font.family: specimen.tokens.type.mono
                        font.pixelSize: 8
                        font.weight: Font.Medium
                    }

                    Frame {
                        x: 10
                        y: 30
                        width: 168
                        height: 152
                        look: Lib.windowLook(specimen.tokens, true)

                        Column {
                            id: terminal
                            x: 9
                            y: 8
                            spacing: 3

                            function lines() {
                                const out = [];
                                for (let i = 0; i < terminalLines.count; i++)
                                    out.push(terminalLines.itemAt(i).runs);
                                return out;
                            }

                            Repeater {
                                id: terminalLines
                                model: Lib.terminalLines(specimen.tokens)

                                Row {
                                    required property var modelData
                                    readonly property var runs: modelData.map(r => ({ text: r.text, color: r.color }))
                                    Repeater {
                                        model: parent.modelData
                                        Text {
                                            required property var modelData
                                            textFormat: Text.PlainText
                                            text: modelData.text
                                            color: modelData.color
                                            font.family: specimen.tokens.type.mono
                                            font.pixelSize: 8
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Frame {
                        x: 190
                        y: 30
                        width: 106
                        height: 152
                        look: Lib.windowLook(specimen.tokens, false)

                        Column {
                            x: 9
                            y: 9
                            width: parent.width - 18
                            spacing: 6
                            Text {
                                textFormat: Text.PlainText
                                text: "Good afternoon"
                                color: specimen.c.ink
                                font.family: specimen.tokens.type.ui
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                            Repeater {
                                model: [80, 62]
                                Rectangle {
                                    required property var modelData
                                    width: modelData
                                    height: 3
                                    color: specimen.c.line
                                }
                            }
                        }

                        Rectangle {
                            x: 9
                            y: parent.height - 9 - height
                            width: parent.width - 18
                            height: 26
                            color: "transparent"
                            border.width: 1
                            border.color: specimen.c.line
                        }
                    }
                }
            }

        }

        Item {
            width: parent.width
            height: specimen.gap
        }

        Row {
            width: parent.width
            spacing: 3

            Repeater {
                id: strip
                model: Lib.swatches(specimen.tokens)

                Rectangle {
                    required property var modelData
                    required property int index
                    width: (specimen.width - 7 * 3) / 8
                    height: 10
                    color: modelData
                    // The paper swatch would vanish into a card of the same colour, so it keeps a hairline.
                    border.width: index === 7 ? 1 : 0
                    border.color: specimen.c.line
                }
            }
        }
    }

    // The stage fades in over the current paper, on Qt's nearest curve to the desktop's.
    NumberAnimation {
        id: playing
        target: stage
        property: "opacity"
        from: 0
        to: 1
        duration: specimen.motion.ms
        easing.type: Easing.InOutSine
        onFinished: specimen.playedMs = Date.now() - specimen.playT0
    }

    // A window as niri frames it: its fill, square, and its 1 px frame.
    component Frame: Item {
        id: win
        required property var look
        default property alias content: body.data

        // Its text stays inside it, as a window's does.
        Rectangle {
            id: body
            anchors.fill: parent
            clip: true
            radius: win.look.radius
            color: win.look.fill
            border.width: win.look.frame.width
            border.color: win.look.frame.color
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../components"

// Dictation OSD — the card that says the microphone is open, with the live
// level to prove it.
//
// WHY IT IS NOT THE OSD PILL NEXT DOOR. Modules/Osd/Osd.qml is a
// show-and-timeout pill: something changed, here is its glyph and value, gone
// in 1.2 s. Dictation is the opposite shape — it is a state you are IN, for as
// long as you hold the key, and the thing worth drawing is that it is still
// listening. Those are different surfaces, so this is its own window rather
// than a fifth mode bolted onto the pill.
//
// WHY IT IS NOT UPSTREAM'S. voxtype 1.x ships a Quickshell OSD frontend of its
// own (`voxtype-osd-quickshell`, `[osd] frontend = "quickshell"`) and it is
// good — but it runs as a SECOND `qs -p` process with its own QML tree, its
// own theme file and its own idea of our palette. One quickshell on this
// desktop is the whole point of the shell; a second one that has to be told
// our colours through a generated JSON file is a worse version of reading
// `theme` directly. So `[osd] enabled` stays false and this reads the same
// audio bridge upstream's frontend reads.
//
// TOP CENTRE, not the bottom: the pill lives at the bottom and dictating while
// changing the volume is not a strange thing to do.
Scope {
    id: root

    required property var theme
    required property var dictation

    // The bridge only runs while something wants levels AND the daemon is
    // recording; this is the "something". Declared as a Binding so a future
    // eviction of this surface takes the want back with it rather than leaving
    // the service believing a dead window still needs frames.
    Binding {
        target: root.dictation
        property: "levelsWanted"
        value: true
    }

    readonly property bool shown: dictation.busy

    // 64 bars, mirrored about the centre line — the same shape upstream's
    // default recipe draws, and the one that reads as "audio" at a glance.
    readonly property int barCount: 64
    readonly property real barWidth: 3
    readonly property real barGap: 2
    readonly property real waveHeight: theme.space(9)

    readonly property int pad: theme.space(3.5)
    readonly property int cardBorder: 1

    Loader {
        // Nothing exists until the first dictation of the session. After that
        // the surface stays — it is input-transparent and 200 px wide, and
        // rebuilding it on every keypress would cost more than keeping it.
        active: root.everShown
        sourceComponent: PanelWindow {
            id: osdWindow

            visible: root.shown || card.opacity > 0
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"
            WlrLayershell.namespace: "qshell-dictation"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            // Visual only: never take a click away from the window being
            // dictated into — which is, by definition, the focused one.
            mask: Region {}

            CardFrost {
                theme: root.theme
                card: card
                windowWidth: osdWindow.width
                windowHeight: osdWindow.height
                offsetY: cardRise.y
                visible: root.theme.blurActive && card.opacity > 0
            }

            Rectangle {
                id: card

                width: root.cardBorder + root.pad + content.implicitWidth + root.pad + root.cardBorder
                height: root.cardBorder + root.pad + content.implicitHeight + root.pad + root.cardBorder
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: root.theme.space(12)

                color: root.theme.glass(root.theme.alpha(root.theme.surface1, 0.97))
                border.width: root.cardBorder
                // The border is the state: accent while the microphone is
                // open, muted once it is whisper's turn and the mic is shut.
                border.color: root.dictation.recording ? root.theme.accent : root.theme.textMuted
                radius: root.theme.radius(1)

                opacity: root.shown ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }

                transform: Translate {
                    id: cardRise
                    y: root.shown ? 0 : -root.theme.space(1.5)
                    Behavior on y {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Column {
                    id: content
                    anchors.centerIn: parent
                    spacing: root.theme.space(1.5)

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: root.theme.space(1.5)

                        OpticalGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.dictation.recording ? "󰍬" : "󰔟"
                            pixelSize: root.theme.fontPx(1.0)
                            color: root.dictation.recording ? root.theme.accent : root.theme.textPrimary
                        }

                        StyledText {
                            theme: root.theme
                            role: StyledText.Small
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.dictation.recording ? "Listening" : "Transcribing"
                            color: root.dictation.recording ? root.theme.accent : root.theme.textPrimary
                        }
                    }

                    // ------------------------------------------------ waveform
                    Item {
                        id: wave

                        width: root.barCount * root.barWidth + (root.barCount - 1) * root.barGap
                        height: root.waveHeight

                        Row {
                            anchors.fill: parent
                            spacing: root.barGap

                            Repeater {
                                model: root.barCount

                                Item {
                                    required property int index

                                    width: root.barWidth
                                    height: wave.height

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: root.barWidth
                                        // Mirrored about the centre, and with a
                                        // floor of 2 px so silence draws as a
                                        // flat line rather than as nothing at
                                        // all — a waveform that vanishes looks
                                        // like a broken widget, not like quiet.
                                        height: Math.max(2, Math.min(1, root.dictation.levels[index] * 1.6) * wave.height)
                                        radius: root.barWidth / 2
                                        color: root.theme.accent
                                        // Older samples fade off to the left,
                                        // which is what makes the thing read as
                                        // moving rather than as flickering.
                                        opacity: 0.35 + 0.65 * (index / (root.barCount - 1))
                                    }
                                }
                            }
                        }

                        // While whisper works there are no frames to draw — the
                        // microphone is already shut — so the waveform is
                        // replaced by a sweep rather than freezing on the last
                        // syllable, which would read as "still listening".
                        Rectangle {
                            id: sweep

                            visible: !root.dictation.recording && root.shown
                            width: wave.width * 0.22
                            height: 2
                            radius: 1
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.theme.textMuted

                            // Back and forth rather than a loop that snaps to
                            // the left edge: the snap reads as a glitch.
                            SequentialAnimation on x {
                                running: sweep.visible
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 0
                                    to: wave.width - sweep.width
                                    duration: 900
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    from: wave.width - sweep.width
                                    to: 0
                                    duration: 900
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Built on the first dictation, kept afterwards.
    property bool everShown: false
    onShownChanged: if (shown)
        everShown = true
}

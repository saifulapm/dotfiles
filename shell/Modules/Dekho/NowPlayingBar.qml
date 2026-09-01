import QtQuick
import "components"

// SOMETHING IS PLAYING AND YOU ARE NOT LOOKING AT IT.
//
// Until this existed the only Stop control in the whole hub lived on the
// playback screen — and Escape POPS that screen off the nav stack, with nothing
// anywhere that pushes it back. So the ordinary thing to do after starting a
// film (press Escape, go and look at something else) left the run with no
// control able to end it, and closing the panel left it running until you found
// the mpv window and closed that by hand.
//
// Playback deliberately outlives this panel — it is a transient systemd unit in
// a different slice precisely so a shell restart cannot kill a film (doc §3).
// That is only a defensible trade if there is always a way to end it, and this
// is that way. It rides above every screen, so wherever you wandered to, the run
// is one click from over.
//
// It is also what a run ADOPTED after eviction shows up as: the panel asks
// `dekho-play --status` on every open (Dekho.qml `adoptRun`), so a hub reopened
// forty minutes into a film knows about it even though the QML that started it
// was destroyed.
Item {
    id: bar

    required property var style
    property string label: ""
    // The run's own last line, so the bar says "Buffering…" while there is
    // nothing to watch yet and the title once there is.
    property string headline: ""
    property bool playing: false

    signal opened
    signal stopped

    implicitHeight: pill.height

    Rectangle {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - bar.style.ui(48), row.implicitWidth + bar.style.ui(40))
        height: bar.style.ui(56)
        radius: height / 2
        // Opaque, not glass: this sits over poster art and a translucent pill
        // over a bright cover is a pill you cannot read.
        color: bar.style.panel
        border.width: bar.style.hairline
        border.color: bar.style.alpha(bar.style.accent, 0.55)

        Row {
            id: row

            anchors.centerIn: parent
            spacing: bar.style.ui(14)

            // The state dot. Green once mpv has the film, accent while dekho is
            // still measuring a swarm — the same distinction the playback
            // screen's headline colour makes, in the one glyph there is room for.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: bar.style.ui(10)
                height: width
                radius: width / 2
                color: bar.playing ? bar.style.green : bar.style.accent

                SequentialAnimation on opacity {
                    running: !bar.playing
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 0.35
                        duration: bar.style.slow
                        easing.type: bar.style.easingSmooth
                    }
                    NumberAnimation {
                        to: 1.0
                        duration: bar.style.slow
                        easing.type: bar.style.easingSmooth
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.round(bar.width * 0.4))
                // The label is the title once there is one; before that, the
                // run's own narration, so a bar that appears during a two-minute
                // swarm probe is saying something true rather than naming a film
                // nothing is playing yet.
                text: bar.label !== "" ? bar.label : bar.headline
                color: bar.style.fg
                font.family: bar.style.fontFamily
                font.pixelSize: bar.style.type(11)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            GlassButton {
                anchors.verticalCenter: parent.verticalCenter
                style: bar.style
                compact: true
                text: "DETAILS"
                onClicked: bar.opened()
            }

            GlassButton {
                anchors.verticalCenter: parent.verticalCenter
                style: bar.style
                compact: true
                primary: true
                text: "STOP"
                onClicked: bar.stopped()
            }
        }
    }
}

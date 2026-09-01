import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "../components"
import "../DekhoModel.js" as Model

// What dekho is doing between "play" and the first frame in mpv. That gap is
// real — releases are looked up, then the swarm is MEASURED before mpv is
// launched — and it is the whole reason playback does not stutter, so the panel
// narrates it instead of showing a spinner.
//
// The narration is unchanged; what it is drawn with is not. The hand-rolled
// meter is a MeterRow, the numbers that were buried inside the trail's prose
// are a 3-up StatTile grid (omakade's fact tiles, and the reason `describeEvent`
// now carries `rate` and `buffered` as numbers), and the two controls are
// GlassButtons like every other control in the module.
Item {
    id: playback

    required property var style

    // The session object the module accumulates from the NDJSON, or null before
    // the first line lands.
    property var session: null
    property string label: ""
    property string posterPath: ""
    property string backdropPath: ""
    property bool running: false
    // The run was ended from this panel's own Stop button. Not derivable from
    // the session: stopping SIGTERMs the unit, so the `exit` line that ends a
    // normal run may never be written and the tail is dropped either way — the
    // last thing this view ever heard is the green "Playing …" it is still
    // showing. Without this the screen after a stop was identical to the screen
    // before it, minus the button (user, 2026-08-20).
    property bool wasStopped: false
    // Which of the two runs this is, so the ended state can say "trailer"
    // rather than claiming a film's position was remembered.
    property bool isTrailer: false

    signal stopped
    signal dismissed

    readonly property var events: session && session.events ? session.events : []
    readonly property string headline: session && session.headline ? session.headline : "Starting…"
    readonly property real ratio: session ? Number(session.ratio) || 0 : 0
    readonly property bool playing: session ? session.playing === true : false
    readonly property string error: session && session.error ? session.error : ""

    // THE RUN IS OVER — however it ended. `wasStopped` only says whether the
    // Stop button was what ended it; a trailer that simply finishes, or an mpv
    // the user closes, leaves `running` false with nothing else changed, and
    // that is the same stale screen for the same reason. So the terminal state
    // hangs off `running`, and wasStopped only picks the word.
    readonly property bool ended: !running && session !== null
    // "" means there is nothing better to say than the run's own last line — an
    // error is already spelled out below in its own colour, and replacing the
    // headline would bury it.
    readonly property string endedLabel: {
        if (playback.error !== "")
            return "";
        if (playback.wasStopped)
            return playback.playing ? "STOPPED" : "CANCELLED";
        return playback.playing ? "FINISHED" : "";
    }
    readonly property bool endedCleanly: ended && endedLabel !== ""

    readonly property var meters: Model.swarmTiles(session, ended)

    function colorFor(kind) {
        switch (kind) {
        case "error":
            return playback.style.red;
        case "warn":
            return playback.style.yellow;
        case "ok":
        case "playing":
            return playback.style.green;
        default:
            return playback.style.fg;
        }
    }

    function focusPrimary() {
        actionButton.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: playback.style.bg
    }

    // Dimmed well below a hero — this screen is read, not admired, and the
    // trail's small lines need the contrast.
    Image {
        anchors.fill: parent
        source: playback.backdropPath ? "file://" + playback.backdropPath.split("/").map(encodeURIComponent).join("/") : ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.min(width, 1600)
        opacity: status === Image.Ready ? 0.22 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: playback.style.slow
                easing.type: playback.style.easing
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: playback.style.alpha(playback.style.bg, 0.35)
            }
            GradientStop {
                position: 1.0
                color: playback.style.alpha(playback.style.bg, 0.85)
            }
        }
    }

    GlassButton {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: playback.style.ui(24)
        z: 2
        style: playback.style
        text: "BACK"
        iconText: "←"
        compact: true
        onClicked: playback.dismissed()
    }

    // A centred column rather than the full width. The library and the title
    // page earn their width by filling it with posters and episodes; this is
    // one poster and a running commentary, and stretched across a 3467 px
    // window it reads as a corner of empty glass.
    ColumnLayout {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Math.round(parent.height * 0.12)
        anchors.bottomMargin: playback.style.ui(22)
        width: Math.min(Math.round(parent.width * 0.62), playback.style.ui(760))
        spacing: playback.style.ui(16)

        Text {
            Layout.fillWidth: true
            text: playback.label
            color: playback.style.brightFg
            font.family: playback.style.fontFamily
            font.pixelSize: Math.max(playback.style.type(24), Math.min(playback.style.type(40), playback.width * 0.03))
            font.weight: Font.Bold
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: playback.style.ui(24)

            // radius small, and no corner cover: this poster sits on the
            // backdrop gradient, where a stroke in the page colour would paint
            // four visible notches over live art. Doc §5 measured the uncovered
            // nub at this radius as about a pixel.
            Rectangle {
                Layout.preferredWidth: playback.style.ui(170)
                Layout.preferredHeight: Math.round(playback.style.ui(170) * 1.5)
                Layout.alignment: Qt.AlignTop
                radius: playback.style.radiusSm
                color: playback.style.raised
                clip: true

                Image {
                    anchors.fill: parent
                    source: playback.posterPath ? "file://" + playback.posterPath.split("/").map(encodeURIComponent).join("/") : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.ceil(width * Math.max(1, Screen.devicePixelRatio))
                    visible: status === Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: playback.style.ui(12)

                // The headline is the run's own last word while the run is
                // alive, and a lie the moment it is not — "Playing Lanterns —
                // S01E01" describes an mpv that has gone. Ending replaces it
                // and drops the colour, because the colour was carrying as much
                // of the meaning as the words were.
                Text {
                    Layout.fillWidth: true
                    text: playback.endedCleanly ? playback.endedLabel : playback.headline
                    color: playback.endedCleanly ? playback.style.muted : playback.colorFor(playback.session ? playback.session.kind : "status")
                    font.family: playback.style.fontFamily
                    font.pixelSize: playback.style.type(15)
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                GridLayout {
                    Layout.fillWidth: true
                    visible: playback.meters.length > 0
                    columns: Math.max(1, playback.meters.length)
                    columnSpacing: playback.style.ui(10)
                    rowSpacing: playback.style.ui(10)

                    Repeater {
                        model: playback.meters

                        StatTile {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.minimumWidth: playback.style.ui(130)
                            style: playback.style
                            label: modelData.label
                            value: modelData.value
                        }
                    }
                }

                // THE THROUGHPUT GATE, DRAWN. dekho requires 1.25x the
                // release's own bitrate before it will launch mpv, so the bar
                // is scaled to that mark rather than to the raw rate: full
                // means "this will play smoothly", not "this is fast". A meter
                // of a swarm nobody is downloading from any more is the same
                // stale-by-a-frozen-session problem as the headline, so it goes
                // when the run does.
                MeterRow {
                    Layout.fillWidth: true
                    visible: playback.ratio > 0 && !playback.ended
                    style: playback.style
                    label: "SWARM · READY AT 100%"
                    value: Math.min(1, playback.ratio / 1.25)
                    valueText: Math.round(Math.min(1, playback.ratio / 1.25) * 100) + "%"
                    fillColor: playback.ratio >= 1.25 ? playback.style.green : playback.style.accent
                }

                Text {
                    Layout.fillWidth: true
                    visible: playback.playing && !playback.ended
                    text: "mpv has it. This panel can close — playback runs on its own, and where you stop is remembered."
                    color: playback.style.muted
                    font.family: playback.style.fontFamily
                    font.pixelSize: playback.style.type(10)
                    wrapMode: Text.Wrap
                }

                // What ending actually did, in the same place the live line
                // above it occupied — so the block CHANGES rather than merely
                // losing a button, which is what made a stop read as a click
                // that did nothing. A film's position is dekho's to record and
                // it does record it on shutdown; a trailer's is not, and saying
                // otherwise would be inventing a feature.
                Text {
                    Layout.fillWidth: true
                    visible: playback.endedCleanly
                    text: !playback.playing ? "The run ended before mpv started. Nothing was watched." : playback.isTrailer ? "mpv closed. A trailer is not recorded as watching the title." : "mpv closed. Where you stopped is remembered — the title offers Resume."
                    color: playback.style.muted
                    font.family: playback.style.fontFamily
                    font.pixelSize: playback.style.type(10)
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: playback.error !== ""
                    text: playback.error
                    color: playback.style.red
                    font.family: playback.style.fontFamily
                    font.pixelSize: playback.style.type(10)
                    wrapMode: Text.Wrap
                }

                // ONE BUTTON, TWO JOBS: it stops a live run, and once there is
                // nothing left to stop it becomes the way out. Leaving a bare
                // gap where the control had been is what made a stop read as a
                // click that did nothing.
                GlassButton {
                    id: actionButton

                    Layout.topMargin: playback.style.ui(4)
                    visible: playback.running || playback.ended
                    style: playback.style
                    primary: true
                    text: playback.running ? (playback.playing ? "STOP PLAYBACK" : "CANCEL") : "BACK TO THE TITLE"
                    onClicked: {
                        if (playback.running)
                            playback.stopped();
                        else
                            playback.dismissed();
                    }
                }
            }
        }

        Text {
            Layout.topMargin: playback.style.ui(8)
            text: "PROGRESS"
            color: playback.style.muted
            font.family: playback.style.fontFamily
            font.pixelSize: playback.style.type(9)
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
        }

        // The full trail, newest last. Which releases were tried and why one
        // was rejected is the answer to "why is this taking a moment", and it
        // is the same trail the CLI prints.
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: playback.events
            clip: true
            spacing: playback.style.ui(2)
            boundsBehavior: Flickable.StopAtBounds
            // Follow the tail: the interesting line is always the newest one.
            onCountChanged: positionViewAtEnd()

            delegate: Text {
                required property var modelData

                width: ListView.view.width
                text: modelData.text
                color: playback.colorFor(modelData.kind)
                opacity: 0.85
                font.family: playback.style.fontFamily
                font.pixelSize: playback.style.type(10)
                elide: Text.ElideRight
            }
        }
    }
}

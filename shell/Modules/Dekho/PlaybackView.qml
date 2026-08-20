import QtQuick
import "../../components"

// What dekho is doing between "play" and the first frame in mpv. That gap is
// real — releases are looked up, then the swarm is MEASURED before mpv is
// launched — and it is the whole reason playback does not stutter, so the
// panel narrates it instead of showing a spinner. The film's own backdrop
// stays under the narration: the wait belongs to the thing you picked.
Item {
    id: playback

    required property var theme
    // The hub's module-local type scale (Dekho.qml `fonts`).
    required property var fonts
    // The session object the hub accumulates from the NDJSON, or null before
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
    // showing. Without this the screen after a stop was identical to the
    // screen before it, minus the button (user, 2026-08-20).
    property bool wasStopped: false
    // Which of the two runs this is, so the stopped state can say "trailer"
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
    // "" means there is nothing better to say than the run's own last line —
    // an error is already spelled out below in its own colour, and replacing
    // the headline would bury it.
    readonly property string endedLabel: {
        if (error !== "")
            return "";
        if (wasStopped)
            return playing ? "Stopped" : "Cancelled";
        return playing ? "Finished" : "";
    }
    readonly property bool endedCleanly: ended && endedLabel !== ""

    function colorFor(kind) {
        switch (kind) {
        case "error":
            return theme.error;
        case "warn":
            return theme.warn;
        case "ok":
        case "playing":
            return theme.okColor;
        default:
            return theme.textPrimary;
        }
    }

    // Dimmed well below the hub's hero — this view is read, not admired, and
    // the trail's small mono lines need the contrast.
    Image {
        anchors.fill: parent
        source: playback.backdropPath ? "file://" + playback.backdropPath.split("/").map(encodeURIComponent).join("/") : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.min(width, 1600)
        asynchronous: true
        opacity: status === Image.Ready ? 0.22 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: playback.theme.motion.slow
                easing.type: playback.theme.motion.easing
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: playback.theme.alpha(playback.theme.surface0, 0.35)
            }
            GradientStop {
                position: 1.0
                color: playback.theme.alpha(playback.theme.surface0, 0.85)
            }
        }
    }

    // A centred column rather than the view's full width. The hub and the
    // detail view earn their width by filling it with posters and episodes;
    // this view is one poster and a running commentary, and stretched across
    // a 3490 px screen it reads as a corner of empty glass.
    Column {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Math.round(parent.height * 0.12)
        anchors.bottomMargin: playback.theme.space(8)
        width: Math.min(Math.round(parent.width * 0.62), playback.fonts.heroBody * 60)
        spacing: playback.theme.space(5)

        Row {
            width: parent.width
            spacing: playback.theme.space(4)

            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                width: playback.theme.space(11)
                height: playback.theme.space(10)
                theme: playback.theme
                glyph: "󰁍"
                glyphSize: playback.fonts.heroMeta
                hint: "Back to the hub (Esc)"
                onActivated: playback.dismissed()
            }

            StyledText {
                width: parent.width - playback.theme.space(15)
                anchors.verticalCenter: parent.verticalCenter
                theme: playback.theme
                font.pixelSize: playback.fonts.railTitle
                font.weight: Font.Bold
                elide: Text.ElideRight
                text: playback.label
            }
        }

        Row {
            width: parent.width
            spacing: playback.theme.space(6)

            // The poster, so the view is unmistakably about the thing you
            // just picked while the text beside it changes every second.
            Rectangle {
                width: Math.round(playback.fonts.heroBody * 11)
                height: Math.round(width * 1.5)
                // radius 4 like the detail stills: this poster sits on the
                // backdrop gradient, so the rails' page-colour corner cover
                // is not available and the radius must keep the uncovered
                // corner nub at the measured ~1 px (doc §5).
                radius: playback.theme.radius(0.5)
                color: playback.theme.surface2

                Image {
                    anchors.fill: parent
                    source: playback.posterPath ? "file://" + playback.posterPath.split("/").map(encodeURIComponent).join("/") : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: parent.width
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: parent.radius
                    border.width: playback.theme.borderWidth
                    border.color: playback.theme.alpha(playback.theme.surface3, 0.6)
                }
            }

            Column {
                width: parent.width - Math.round(playback.fonts.heroBody * 11) - playback.theme.space(6)
                spacing: playback.theme.space(3)

                // The headline is the run's own last word while the run is
                // alive, and a lie the moment it is not — "Playing Lanterns —
                // S01E01" describes an mpv that has gone. Ending replaces it
                // and drops the green, because the colour was carrying as much
                // of the meaning as the words were.
                StyledText {
                    width: parent.width
                    theme: playback.theme
                    font.pixelSize: playback.fonts.heroMeta
                    font.weight: Font.DemiBold
                    color: playback.endedCleanly ? playback.theme.textMuted : playback.colorFor(playback.session ? playback.session.kind : "status")
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: playback.endedCleanly ? playback.endedLabel : playback.headline
                }

                // The throughput gate, drawn. dekho requires 1.25x the
                // release's own bitrate before it will launch mpv, so the bar
                // is scaled to that mark rather than to the raw rate: full
                // means "this will play smoothly", not "this is fast".
                Item {
                    width: parent.width
                    height: playback.theme.space(2.5)
                    // A meter of a swarm nobody is downloading from any more
                    // is the same stale-by-a-frozen-session problem as the
                    // headline: it is measuring nothing once the unit is gone.
                    visible: playback.ratio > 0 && !playback.ended

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: playback.theme.surface2
                    }

                    Rectangle {
                        height: parent.height
                        radius: height / 2
                        width: Math.max(height, parent.width * Math.min(1, playback.ratio / 1.25))
                        color: playback.ratio >= 1.25 ? playback.theme.okColor : playback.theme.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: playback.theme.motion.standard
                                easing.type: playback.theme.motion.easingSmooth
                            }
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: playback.session !== null && playback.session.peers > 0 && !playback.ended
                    theme: playback.theme
                    font.pixelSize: playback.fonts.meta
                    mono: true
                    muted: true
                    text: playback.session ? playback.session.peers + " peers connected" : ""
                }

                StyledText {
                    width: parent.width
                    visible: playback.playing && !playback.ended
                    theme: playback.theme
                    font.pixelSize: playback.fonts.meta
                    muted: true
                    wrapMode: Text.Wrap
                    text: "mpv has it. This panel can close — playback runs on its own, and where you stop is remembered."
                }

                // What ending actually did, in the same place the live line
                // above it occupied — so the block CHANGES rather than merely
                // losing a button, which is what made a stop read as a click
                // that did nothing. A film's position is dekho's to record and
                // it does record it on shutdown; a trailer's is not, and
                // saying otherwise would be inventing a feature.
                StyledText {
                    width: parent.width
                    visible: playback.endedCleanly
                    theme: playback.theme
                    font.pixelSize: playback.fonts.meta
                    muted: true
                    wrapMode: Text.Wrap
                    text: {
                        if (!playback.playing)
                            return "The run ended before mpv started. Nothing was watched.";
                        if (playback.isTrailer)
                            return "mpv closed. A trailer is not recorded as watching the title.";
                        return "mpv closed. Where you stopped is remembered — the title offers Resume.";
                    }
                }

                StyledText {
                    width: parent.width
                    visible: playback.error !== ""
                    theme: playback.theme
                    font.pixelSize: playback.fonts.meta
                    color: playback.theme.error
                    wrapMode: Text.Wrap
                    text: playback.error
                }

                // One pill, two jobs: it stops a live run, and once there is
                // nothing left to stop it becomes the way out. Leaving a bare
                // gap where the button had been is what made a stop read as a
                // click that did nothing — the row has to still be a control,
                // pointing at the only thing left to do.
                Rectangle {
                    readonly property bool danger: playback.running && playback.playing

                    width: stopLabel.implicitWidth + playback.theme.space(10)
                    height: Math.round(playback.fonts.heroBody * 2.2)
                    radius: height / 2
                    visible: playback.running || playback.ended
                    color: playback.theme.alpha(danger ? playback.theme.error : playback.theme.accent, 0.22)
                    border.width: playback.theme.borderWidth
                    border.color: playback.theme.alpha(danger ? playback.theme.error : playback.theme.accent, 0.6)

                    StyledText {
                        id: stopLabel
                        anchors.centerIn: parent
                        theme: playback.theme
                        font.pixelSize: playback.fonts.heroBody
                        font.weight: Font.DemiBold
                        text: playback.running ? (playback.playing ? "Stop playback" : "Cancel") : "Back to the title"
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (playback.running)
                                playback.stopped();
                            else
                                playback.dismissed();
                        }
                    }
                }
            }
        }

        // SectionHeader's Caption role is bar-scale type — unreadable inside
        // this module's boosted scale, so the caption is drawn at the local
        // meta size with the same uppercase mono voice.
        StyledText {
            theme: playback.theme
            font.pixelSize: playback.fonts.meta
            font.letterSpacing: 1.2
            font.weight: Font.DemiBold
            mono: true
            muted: true
            text: "PROGRESS"
        }

        // The full trail, newest last. Which releases were tried and why one
        // was rejected is the answer to "why is this taking a moment", and it
        // is the same trail the CLI prints.
        ListView {
            width: parent.width
            height: Math.max(0, parent.height - y)
            model: playback.events
            clip: true
            spacing: playback.theme.space(1)
            boundsBehavior: Flickable.StopAtBounds
            // Follow the tail: the interesting line is always the newest one.
            onCountChanged: positionViewAtEnd()

            delegate: StyledText {
                required property var modelData

                width: ListView.view.width
                theme: playback.theme
                font.pixelSize: playback.fonts.meta
                mono: true
                color: playback.colorFor(modelData.kind)
                opacity: 0.85
                elide: Text.ElideRight
                text: modelData.text
            }
        }
    }
}

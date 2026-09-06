import QtQuick
import "../components"
import "../../../components"

// Now playing — the state glyph and the track title, present only while
// something is actually playing.
//
// WHY THIS EXISTS AGAIN. Services/Media.qml records that the bar widget this
// replaces was deleted on 2026-08-18, when cliamp became the music player:
// cliamp has its own window, so a bar row repeated what `music` already
// showed. bin/youtube's `audio` verb broke that assumption on 2026-09-06 —
// it is `mpv --no-video`, a player with NO window at all, so without this
// there is nothing on screen to say sound is coming out of the machine, and
// nothing to click. The media keys always worked; awareness is what was
// missing, and a key cannot supply it.
//
// Narrower than the widget it replaces, deliberately: no album art, no
// progress bar, no panel. It occupies zero bar space when nothing is
// playing, which is the condition under which the old one was judged not to
// be worth its room.
//
// Nothing here is YouTube-specific. It reads the same MPRIS ladder every
// XF86Audio* bind does, so cliamp, a browser tab and mpv all light it up.
BarButton {
    id: rootItem

    // Services/Media.qml, injected by the bar's registry.
    required property var media

    // Inline shell.json entry {"id": "media", "maxWidth": N}, same knob and
    // the same elide behaviour as the window-title widget next to it.
    readonly property int maxWidth: Number(setting("maxWidth", 220))

    readonly property bool playing: media && media.activePlayer ? media.activePlayer.isPlaying === true : false
    readonly property string label: media ? (media.title || media.artist) : ""

    visible: media ? media.hasMedia : false

    // Action-oriented, as StayAwake's pair is: the tooltip says what a click
    // will do, and carries the full title the bar had to elide.
    tooltipText: {
        if (!media || !media.hasMedia)
            return "";
        var who = media.artist ? media.artist + " — " + media.title : media.title;
        return (playing ? "Pause" : "Play") + " · " + who;
    }

    onTapped: button => {
        if (!rootItem.media)
            return;
        if (button === Qt.MiddleButton || button === Qt.RightButton)
            rootItem.media.stopPlayback(true);
        else
            rootItem.media.runAction("playPause", true);
    }

    // The title changes width with every track; without this the widgets to
    // the right of it jump.
    Behavior on implicitWidth {
        NumberAnimation {
            duration: rootItem.theme.time(1.2)
            easing.type: rootItem.theme.motion.easing
        }
    }

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: rootItem.playing ? "󰐊" : "󰏤"
        color: rootItem.contentColor
        pixelSize: 13
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    StyledText {
        id: title
        theme: rootItem.theme
        role: StyledText.BodyLarge
        mono: true

        anchors.verticalCenter: parent.verticalCenter
        // A title is a run of text and a 28 px column has nowhere to put one
        // — the same reason the window widget hides itself on a vertical bar.
        // Here the glyph still carries the fact that something is playing, so
        // only the label goes.
        visible: !rootItem.vertical && rootItem.label !== ""
        width: visible ? Math.min(implicitWidth, rootItem.maxWidth) : 0
        elide: Text.ElideRight
        opacity: 0.85
        color: rootItem.contentColor
        renderType: Text.NativeRendering
        text: rootItem.label
    }
}

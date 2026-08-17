import QtQuick
import Quickshell
import "../components"
import "../../../components"

// MPRIS now-playing — full port of omarchy's media bar widget
// (shell/plugins/services/media/BarWidget.qml, CREDITS.md) over our media
// service: play/pause glyph dimmed darker while paused, the "title · artist"
// label auto-scrolling inside a clip when it outgrows `maxLabelWidth` (an
// inline shell.json setting, their default 180), left click play/pause,
// middle click next, wheel prev/next, and the right-click popup card with
// album art, transport controls and the SOURCES list (MediaPanel.qml).
// Hidden without media; glyph only on a vertical bar, as theirs.
BarButton {
    id: rootItem

    // The shared media service at the shell root, reached through the
    // injected bar (null for the first frames, before the bar lands).
    readonly property var media: bar && bar.shell ? bar.shell.media : null
    readonly property var player: media ? media.activePlayer : null
    readonly property bool hasMedia: media ? media.hasMedia : false
    readonly property bool playing: player !== null && player.isPlaying
    readonly property string title: media ? media.title : ""
    readonly property string artist: media ? media.artist : ""
    readonly property real maxLabelWidth: Number(setting("maxLabelWidth", 180))

    visible: hasMedia
    tooltipText: hasMedia ? title + (artist ? " — " + artist : "") : ""

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("MediaPanel.qml", {
                theme: rootItem.theme,
                media: rootItem.media
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (!rootItem.player)
            return;
        if (button === Qt.MiddleButton)
            rootItem.media.runAction("next", false);
        else if (button === Qt.RightButton)
            rootItem.openPanel();
        else
            rootItem.media.runAction("playPause", false);
    }

    onWheelMoved: delta => {
        if (!rootItem.player)
            return;
        if (delta > 0)
            rootItem.media.runAction("previous", false);
        else if (delta < 0)
            rootItem.media.runAction("next", false);
    }

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: rootItem.playing ? "󰏤" : "󰐊" // pause / play
        color: rootItem.playing ? rootItem.contentColor : Qt.darker(rootItem.contentColor, 1.5)
        pixelSize: 13
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    // Their marquee: the label lives in a clip sized to the smaller of its
    // own width and maxLabelWidth, and glides through when it doesn't fit.
    Item {
        id: scrollClip

        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(rootItem.maxLabelWidth, labelText.implicitWidth)
        height: labelText.implicitHeight
        clip: true
        visible: !rootItem.vertical && rootItem.title !== ""

        Text {
            id: labelText

            anchors.verticalCenter: parent.verticalCenter
            text: rootItem.title + (rootItem.artist ? "  ·  " + rootItem.artist : "")
            color: rootItem.contentColor
            opacity: 0.85
            font.family: rootItem.theme.fontMono
            font.pixelSize: rootItem.theme.fontPx(0.917)
            renderType: Text.NativeRendering

            property bool needsScroll: implicitWidth > scrollClip.width

            // A label that stops needing to scroll (track change, panel
            // open) must not stay frozen mid-glide off screen.
            onNeedsScrollChanged: if (!needsScroll)
                x = 0

            NumberAnimation on x {
                id: scrollAnim
                running: labelText.needsScroll && !(panelLoader.item && panelLoader.item.opened) && !rootItem.vertical
                loops: Animation.Infinite
                duration: Math.max(6000, labelText.implicitWidth * 25)
                from: scrollClip.width
                to: -labelText.implicitWidth
                easing.type: Easing.Linear
            }
        }
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}

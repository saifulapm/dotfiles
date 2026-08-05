import QtQuick
import Quickshell.Services.Mpris
import "../components"

// MPRIS now-playing, omarchy media-widget style: play/pause glyph (dimmed
// darker when paused) + title, elided at 180 px. Left click play/pause,
// middle click next, wheel prev/next. Hidden without a player.
BarButton {
    id: rootItem

    readonly property var player: {
        const all = Mpris.players.values;
        return all.find(p => p.isPlaying) || all[0] || null;
    }
    readonly property bool playing: player !== null && player.isPlaying

    visible: player !== null
    tooltipText: {
        if (!player)
            return "";
        const artist = player.trackArtist;
        return player.trackTitle + (artist ? " — " + artist : "");
    }

    onTapped: button => {
        if (!rootItem.player)
            return;
        if (button === Qt.MiddleButton && rootItem.player.canGoNext)
            rootItem.player.next();
        else if (rootItem.player.canTogglePlaying)
            rootItem.player.togglePlaying();
    }

    onWheelMoved: delta => {
        if (!rootItem.player)
            return;
        if (delta > 0 && rootItem.player.canGoPrevious)
            rootItem.player.previous();
        else if (delta < 0 && rootItem.player.canGoNext)
            rootItem.player.next();
    }

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: rootItem.playing ? "󰏤" : "󰐊" // pause / play
        color: rootItem.playing ? rootItem.contentColor : Qt.darker(rootItem.contentColor, 1.5)
        pixelSize: 13
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 180)
        elide: Text.ElideRight
        // Glyph only on a vertical bar — theirs hides the scrolling title
        // there for the same reason the window title goes away entirely.
        visible: !rootItem.vertical && rootItem.player !== null && rootItem.player.trackTitle !== ""
        text: rootItem.player ? rootItem.player.trackTitle : ""
        color: rootItem.contentColor
        opacity: 0.85
        font.family: rootItem.theme.fontMono
        font.pixelSize: rootItem.theme.fontPx(0.917)
        renderType: Text.NativeRendering
    }
}

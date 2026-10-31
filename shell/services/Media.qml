import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import ".." as Root

// MPRIS players announce every change on the bus, so the island's now-playing slot follows them without polling.
Scope {
    id: media

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? null
    // The island's playing slot, {title, artist}, null while nothing plays.
    readonly property var playing: player ? {
        title: player.trackTitle,
        artist: player.trackArtist
    } : null
    // The players that played, newest first, so once a video's window closes Play resumes the paused Queue under it, not the bus's first player.
    property var played: []
    onPlayerChanged: {
        if (player)
            played = [player].concat(played.filter(p => p !== player && Mpris.players.values.includes(p)));
    }
    readonly property var target: player ?? played.find(p => Mpris.players.values.includes(p)) ?? Mpris.players.values[0] ?? null

    // The media keys: niri runs qs ipc call media <playPause|next|previous>.
    Root.Ipc {
        target: "media"

        function playPause(): void {
            if (media.target?.canTogglePlaying)
                media.target.togglePlaying();
        }
        function next(): void {
            if (media.target?.canGoNext)
                media.target.next();
        }
        function previous(): void {
            if (media.target?.canGoPrevious)
                media.target.previous();
        }
    }
}

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

    function playPause() {
        if (target?.canTogglePlaying)
            target.togglePlaying();
    }
    function next() {
        if (target?.canGoNext)
            target.next();
    }
    function previous() {
        if (target?.canGoPrevious)
            target.previous();
    }

    // The media keys: niri runs qs ipc call media <playPause|next|previous>; the island's media card runs the same three.
    Root.Ipc {
        target: "media"

        function playPause(): void {
            media.playPause();
        }
        function next(): void {
            media.next();
        }
        function previous(): void {
            media.previous();
        }
    }
}

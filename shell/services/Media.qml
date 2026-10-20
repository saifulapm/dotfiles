import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// MPRIS players announce every change on the bus, so the island's now-playing slot follows them without polling.
Scope {
    id: media

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? null
    // The island's playing slot, {title, artist}, null while nothing plays.
    readonly property var playing: player ? {
        title: player.trackTitle,
        artist: player.trackArtist
    } : null
    // The player that played last, so Play resumes a paused one while nothing plays.
    property var last: null
    onPlayerChanged: {
        if (player)
            last = player;
    }
    readonly property var target: player ?? (Mpris.players.values.includes(last) ? last : null) ?? Mpris.players.values[0] ?? null

    // The media keys: niri runs qs ipc call media <playPause|next|previous>.
    IpcHandler {
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

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// MPRIS players announce every change on the bus, so the island's now-playing slot follows them without polling.
Scope {
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? null
    // The island's playing slot, {title, artist}, null while nothing plays.
    readonly property var playing: player ? {
        title: player.trackTitle,
        artist: player.trackArtist
    } : null
}

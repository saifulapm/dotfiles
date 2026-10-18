import Quickshell
import QtQuick

// Idle steps: dim, then lock, then monitors off, each held back by any idle inhibitor.
Scope {
    id: idle

    required property var lock
    // The shell's LazyLoader of the Surfaces window, where the dim draws.
    required property var surfaces
}

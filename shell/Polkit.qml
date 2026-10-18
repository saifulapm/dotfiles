import Quickshell
import QtQuick

// The polkit agent; it registers as the shell starts and shows its prompt in the Surfaces window.
Scope {
    id: polkit

    // The shell's LazyLoader of the Surfaces window.
    required property var surfaces
}

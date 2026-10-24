//@ pragma AppId mpv
import Quickshell
import QtQuick

// The play check's stand-in for mpv: one window with mpv's app id, which dev-fake-dekho's play opens a moment after its playing event, as the real mpv maps late.
ShellRoot {
    FloatingWindow {
        implicitWidth: 320
        implicitHeight: 180
        color: "#101010"
        title: "fake mpv"
    }
}

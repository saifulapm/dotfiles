//@ pragma AppId mpv
import Quickshell
import Quickshell.Io
import QtQuick

// The play check's stand-in for mpv: one window with mpv's app id, which dev-fake-dekho's play opens a moment after its playing event, as the real mpv maps late, titled as the real one titles it.
ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 320
        implicitHeight: 180
        color: "#101010"
        title: Quickshell.env("FAKE_MPV_TITLE") || "fake mpv"
    }

    // An appended episode: mpv retitles its window when it moves on, and says nothing else; the mark tells the fake backend, as mpv's own state tells dekho.
    Timer {
        interval: Number(Quickshell.env("FAKE_MPV_NEXT_SECS") || 0) * 1000
        running: (Quickshell.env("FAKE_MPV_NEXT_TITLE") || "") !== ""
        onTriggered: {
            win.title = Quickshell.env("FAKE_MPV_NEXT_TITLE");
            marker.running = true;
        }
    }
    Process {
        id: marker
        command: ["touch", Quickshell.env("FAKE_MPV_NEXT_MARK") || "/dev/null"]
    }

    // mpv quits when its window closes, and qs has no quit of its own, so a child ends it.
    Process {
        id: ender
        command: ["sh", "-c", "kill -TERM $PPID"]
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() {
            ender.running = true;
        }
    }
}

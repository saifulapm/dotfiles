import Quickshell
import Quickshell.Io
import QtQuick
import "lib/dekho.mjs" as D

// A title's trailer in its own mpv window, under a unit of its own, so it never stops a film and is never recorded as watched; one that cannot start toasts once.
Item {
    id: runner

    required property var dekho

    readonly property string bin: Quickshell.shellDir + "/../bin/dots-dekho-play"
    // What is played: id, kind and title.
    property var target: ({})
    property string session: ""
    // The playing event, kept for checks.
    property var playing: null
    property bool failed: false

    // A trailer started while one plays replaces it: the wrapper stops the earlier trailer's unit first.
    function play(t) {
        tail.running = false;
        target = t;
        playing = null;
        failed = false;
        session = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dekho/session-trailer-" + Date.now() + ".ndjson";
        starter.running = true;
    }

    function heard(line) {
        const e = D.answer(line);
        if (!e)
            return;
        if (e.event === "playing")
            playing = e;
        if (!failed && (e.event === "error" || (e.event === "exit" && e.code !== 0))) {
            failed = true;
            dekho.toast("Trailer could not start");
        }
        if (e.event === "exit")
            tail.running = false;
    }

    function state() {
        return {
            trailer: {
                session: session,
                playing: playing,
                failed: failed
            }
        };
    }

    Process {
        id: starter
        command: [runner.bin, "--trailer", "--session", runner.session, "--id", String(runner.target.id), "--kind", String(runner.target.kind)]
        onExited: tail.running = true
    }

    // As the release list's tail: it ends with the App by watching qs's pid, and polls every 0.1 s.
    Process {
        id: tail
        command: ["sh", "-c", "exec tail --pid=\"$PPID\" -n +1 -s 0.1 -F \"$1\"", "sh", runner.session]
        stdout: SplitParser {
            onRead: line => runner.heard(line)
        }
    }
}

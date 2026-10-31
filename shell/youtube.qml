//@ pragma AppId youtube
import Quickshell
import Quickshell.Io
import QtQuick
import "services" as Services
import "lib/status.mjs" as Status
import "lib/youtube-look.mjs" as Y

// The YouTube App: its own qs process started by bin/dots-youtube, one window in the shell's theme with a sidebar of views beside their list; the process ends with its window.
ShellRoot {
    id: app

    // Process start to the window's first frame, set once.
    property var firstFrameMs: null
    readonly property string backend: Quickshell.env("DOTS_YOUTUBE") || "dots-youtube-api"
    // The sidebar's entry the list shows: search, saved or history.
    property string view: "search"
    // Which pane the keys move in while the field is not focused: sidebar or list.
    property string pane: "list"
    readonly property string focusAt: board.fieldFocused ? "field" : pane
    readonly property string query: board.queryText
    // The rows the list draws, as youtube.mjs rows() makes them, and the one under the cursor.
    property var rows: []
    property int cursor: 0
    property int savedCount: 0
    property int historyCount: 0
    // What the Queue plays, as the now-playing line writes it; empty while it is stopped.
    property string nowPlaying: ""

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: Y.youtubeLook(theme.tokens)
    readonly property string voice: look.voice

    // qs has no quit, so a child ends its parent: the process must not outlive the window.
    function quit() {
        ender.running = true;
    }

    function focusField() {
        board.focusField();
    }

    function focusPane(name) {
        pane = name;
        board.focusKeys();
    }

    // j and k: the sidebar's cursor is the view it opens, the list's is a row.
    function move(step) {
        if (pane === "sidebar") {
            const names = look.places.map(p => p.view);
            view = names[Math.max(0, Math.min(names.length - 1, names.indexOf(view) + step))];
        } else if (rows.length > 0)
            cursor = Math.max(0, Math.min(rows.length - 1, cursor + step));
    }

    // Saved and History go back to Search; Search has nothing behind it, so Esc there closes the App.
    function back() {
        if (view !== "search")
            view = "search";
        else
            quit();
    }

    Services.Theme {
        id: theme
    }

    Process {
        id: ender
        // Its children first: qs dies on SIGTERM without ending them, which would leave a backend call running on.
        command: ["sh", "-c", "for p in $(pgrep -P $PPID); do [ \"$p\" = $$ ] || kill -TERM \"$p\"; done; kill -TERM $PPID"]
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() {
            app.quit();
        }
    }

    FileView {
        id: uptime
        path: "/proc/uptime"
        blockAllReads: true
    }

    FileView {
        id: selfStat
        path: "/proc/self/stat"
        blockLoading: true
    }

    // Read at call time; blockAllReads, or text() after reload() is the previous call's RSS.
    FileView {
        id: procStatus
        path: "/proc/self/status"
        blockAllReads: true
    }

    IpcHandler {
        target: "youtube"

        function state(): string {
            procStatus.reload();
            return JSON.stringify(Object.assign({
                view: app.view,
                focus: app.focusAt,
                query: app.query,
                rows: app.rows,
                cursor: app.cursor,
                firstFrameMs: app.firstFrameMs,
                rssKiB: Status.rssKiB(procStatus.text()),
                voice: app.voice
            }, board.state()));
        }
    }

    FloatingWindow {
        id: win

        title: "YouTube"
        implicitWidth: 1200
        implicitHeight: 716
        color: "transparent"

        Connections {
            target: win.contentItem.Window.window
            function onFrameSwapped() {
                if (app.firstFrameMs !== null)
                    return;
                uptime.reload();
                app.firstFrameMs = Status.processAgeMs(uptime.text(), selfStat.text());
            }
        }

        YouTubeBoard {
            id: board
            anchors.fill: parent
            yt: app
        }
    }
}

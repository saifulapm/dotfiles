//@ pragma AppId youtube
import Quickshell
import Quickshell.Io
import QtQuick
import "services" as Services
import "lib/status.mjs" as Status
import "lib/youtube-look.mjs" as Y
import "lib/youtube.mjs" as YT
import "lib/youtube-queue.mjs" as Q

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
    // The last search's rows and Saved's, as youtube.mjs rows() makes them; the list draws the view's, with the cursor on one.
    property var results: []
    readonly property var savedRows: YT.rows({
        rows: store.saved
    })
    readonly property var rows: view === "search" ? results : view === "saved" ? savedRows : []
    property int cursor: 0
    // Each search's number: an answer from any search but the last is dropped.
    property int searchSeq: 0
    // Thumbnail files by thumb id, as dots-youtube-api thumbs answers them.
    property var thumbs: ({})
    // The last search's failure as youtube.mjs failure() reads it, {error, kind, raw}, or null.
    property var failed: null
    // The youtube-video-<n> units this App started, in order.
    property var units: []
    readonly property int savedCount: savedRows.length
    property int historyCount: 0
    // The Queue as mpv reports it over youtube-audio's socket, and the buffer that holds what m and a send while the unit starts.
    property var queue: Q.initial()
    property var link: Q.link()
    // What the Queue plays, as the now-playing line writes it; empty while it is stopped.
    readonly property string nowPlaying: Q.nowLine(queue)

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: Y.youtubeLook(theme.tokens)
    readonly property string voice: look.voice

    // qs has no quit, so a child ends its parent: the process must not outlive the window.
    function quit() {
        ender.running = true;
    }

    // Only Search draws the field, so / from Saved or History goes there first; Esc in the field returns to its list.
    function focusField() {
        view = "search";
        pane = "list";
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

    // Runs a command off the render loop and hands done its one JSON answer, or null when it failed.
    function run(command, done) {
        const call = caller.createObject(app, {
            command: command
        });
        call.done = done;
        call.running = true;
    }

    function api(args, done) {
        run([backend].concat(args), done);
    }

    // Enter on a row: each play is an mpv window in a unit of its own, which outlives this window; it pauses the Queue first, and nothing resumes the Queue by itself.
    function play(row) {
        if (!row)
            return;
        queueCommand(Q.setPauseLine(true));
        // The repo's bin is on the session PATH only through fish, so the player is found beside the shell.
        run([Quickshell.shellDir + "/../bin/dots-youtube-play", "video", row.id], answer => {
            if (answer && typeof answer.unit === "string")
                app.units = app.units.concat([answer.unit]);
        });
    }

    // m plays a row in the Queue in place of what it holds, a appends it; the first ask with no Queue connected starts youtube-audio, and what follows waits for its socket.
    function queueItem(row, how) {
        if (!row)
            return;
        const lines = Q.itemLines(queue, row, how);
        queue = Q.asked(queue);
        const r = Q.send(link, lines);
        link = r.link;
        writeQueue(r.write);
        if (!r.start)
            return;
        run([Quickshell.shellDir + "/../bin/dots-youtube-play", "audio"], answer => {
            if (answer && typeof answer.socket === "string")
                queueSocket.connected = true;
            // A failed start, or a socket that refused the connect, drops what waited, so the next m or a starts the unit again.
            if (!queueSocket.connected)
                app.dropQueue();
        });
    }

    // Space and r: a command with no Queue connected has nothing to reach.
    function queueCommand(line) {
        if (link.status === "up")
            writeQueue([line]);
    }

    function writeQueue(lines) {
        if (lines.length === 0)
            return;
        queueSocket.write(lines.join("\n") + "\n");
        queueSocket.flush();
    }

    function dropQueue() {
        link = Q.lost();
        queue = Q.initial();
    }

    // Enter in the field: the list takes focus at once, and the rows come when the CLI answers.
    function search() {
        const q = query.trim();
        if (q === "")
            return;
        searchSeq += 1;
        const seq = searchSeq;
        focusPane("list");
        api(["search", q, "videos", "0"], answer => {
            if (seq !== app.searchSeq)
                return;
            app.failed = YT.failure(answer);
            app.results = app.failed ? [] : YT.rows(answer);
            app.cursor = 0;
            app.fetchThumbs(app.results);
        });
    }

    // s on a row: Saved keeps it in the store, at most once.
    function save(row) {
        if (row)
            store.save(row);
    }

    // Each view's list starts at its top.
    onViewChanged: cursor = 0
    // Saved draws from the store with no search behind it, so a thumbnail no list has fetched yet is asked for here.
    onSavedRowsChanged: fetchThumbs(savedRows.filter(r => !thumbs[r.thumb]))

    // One thumbs call for a list's ids; a thumb it does not name keeps its row's placeholder.
    function fetchThumbs(list) {
        const ids = list.map(r => r.thumb).filter((t, i, all) => t && all.indexOf(t) === i);
        if (ids.length === 0)
            return;
        api(["thumbs"].concat(ids), answer => {
            const files = answer && answer.files;
            if (files && typeof files === "object")
                app.thumbs = Object.assign({}, app.thumbs, files);
        });
    }

    // The file a thumb id draws from, or "" for its placeholder.
    function thumbSource(id) {
        const f = thumbs[id];
        return typeof f === "string" && f.startsWith("/") ? "file://" + f : "";
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

    // Connects as the App opens, so a reopened App reads the running Queue; with no socket the connect fails and the line stays empty until m or a starts one.
    Socket {
        id: queueSocket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/dots/youtube-audio.sock"
        connected: true
        onConnectedChanged: {
            if (connected) {
                const r = Q.connected(app.link);
                app.link = r.link;
                app.writeQueue(Q.connectLines().concat(r.write));
            } else
                app.dropQueue();
        }
        parser: SplitParser {
            onRead: text => app.queue = Q.reduce(app.queue, text)
        }
    }

    YouTubeStore {
        id: store
    }

    Component {
        id: caller

        Process {
            property var done: null
            stdout: StdioCollector {
                id: answerOut
            }
            onExited: {
                const answer = YT.answer(answerOut.text);
                if (done)
                    done(answer);
                destroy();
            }
        }
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
                searchSeq: app.searchSeq,
                units: app.units,
                queue: app.queue,
                error: app.failed,
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

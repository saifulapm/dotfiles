//@ pragma AppId youtube
import Quickshell
import Quickshell.Io
import QtQuick
import "services" as Services
import "lib/status.mjs" as Status
import "lib/youtube-look.mjs" as Y
import "lib/youtube.mjs" as YT
import "lib/youtube-find.mjs" as F
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
    // The type filter under the field: what Enter in the field searches for.
    readonly property var types: ["videos", "playlists", "channels"]
    property string type: "videos"
    // The last search as youtube-find.mjs pages it, and the query and type it pages on; its rows, Saved's and History's are as youtube.mjs rows() makes them, and the list draws the view's, with the cursor on one.
    property var found: F.page(null)
    property var searched: null
    // A playlist or channel opened from a row, as youtube-find.mjs opening() makes it: its name, count, list and failure, and the results cursor Esc comes back to; null while the results show.
    property var opened: null
    readonly property var results: opened ? opened.list.rows : found.rows
    // The list head's count: a playlist's own, else the rows listed.
    readonly property string listCount: opened && opened.kind === "playlist" && YT.count(opened.count) ? YT.count(opened.count) : String(rows.length)
    readonly property var savedRows: YT.rows({
        rows: store.saved
    })
    readonly property var historyRows: history.rows
    readonly property var rows: view === "search" ? results : view === "saved" ? savedRows : historyRows
    property int cursor: 0
    // Each search's number: an answer from any search but the last is dropped.
    property int searchSeq: 0
    // Thumbnail files by thumb id, as dots-youtube-api thumbs answers them.
    property var thumbs: ({})
    // The last search's failure as youtube.mjs failure() reads it, {error, kind, raw}, or null; the list shows the opened item's instead while one is open.
    property var searchFailed: null
    readonly property var failed: opened ? opened.failed : searchFailed
    // The youtube-video-<n> units this App started, in order.
    property var units: []
    readonly property int savedCount: savedRows.length
    readonly property int historyCount: historyRows.length
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
        } else if (rows.length > 0) {
            cursor = Math.max(0, Math.min(rows.length - 1, cursor + step));
            pageOn();
        }
    }

    // The cursor on the last 5 rows of a search or a channel's uploads asks for the next page, once while it loads; the rows on screen stay as they are, the new ones go below.
    function pageOn() {
        const list = opened ? opened.list : found;
        if (view !== "search" || failed !== null || !F.wants(list, cursor))
            return;
        const seq = searchSeq;
        const asked = F.asking(list);
        setList(asked);
        const args = opened ? ["channel", opened.id, String(list.next)] : ["search", searched.query, searched.type, String(list.next)];
        // A search started before this page shares its number, so the page lands only on the very list it was asked for.
        api(args, answer => {
            const now = app.opened ? app.opened.list : app.found;
            if (seq !== app.searchSeq || now !== asked)
                return;
            app.setList(F.append(now, answer));
            app.fetchThumbs(app.results.slice(now.rows.length));
        });
    }

    function setList(list) {
        if (opened)
            opened = Object.assign({}, opened, {
                list: list
            });
        else
            found = list;
    }

    // Enter on a row: a video plays, a playlist or channel opens in the list.
    function enter(row) {
        if (row && row.kind === "video")
            play(row);
        else if (row)
            open(row);
    }

    // A playlist lists every item, a channel its uploads newest first; the results behind it, and a page of them still loading, wait for Esc.
    function open(row) {
        searchSeq += 1;
        const seq = searchSeq;
        if (found.loading)
            found = Object.assign({}, found, {
                loading: false
            });
        opened = F.opening(row, opened ? opened.back : cursor);
        cursor = 0;
        api(row.kind === "playlist" ? ["playlist", row.id] : ["channel", row.id, "0"], answer => {
            if (seq !== app.searchSeq)
                return;
            app.opened = F.opened(app.opened, answer);
            app.fetchThumbs(app.results);
        });
    }

    // Enter on a failed list asks again for what failed.
    function retry() {
        if (opened)
            open(opened);
        else
            search();
    }

    // h and l on Search: the filter moves one type, and a query in the field is searched again under it.
    function moveType(step) {
        const next = types[Math.max(0, Math.min(types.length - 1, types.indexOf(type) + step))];
        if (next === type)
            return;
        type = next;
        if (query.trim() !== "")
            search();
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
        if (!row || row.kind !== "video")
            return;
        history.add(row);
        queueCommand(Q.setPauseLine(true));
        // The repo's bin is on the session PATH only through fish, so the player is found beside the shell.
        run([Quickshell.shellDir + "/../bin/dots-youtube-play", "video", row.id], answer => {
            if (answer && typeof answer.unit === "string")
                app.units = app.units.concat([answer.unit]);
        });
    }

    // m plays a row in the Queue in place of what it holds, a appends it; the first ask with no Queue connected starts youtube-audio, and what follows waits for its socket.
    function queueItem(row, how) {
        if (!row || row.kind !== "video")
            return;
        history.add(row);
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

    // Enter in the field: the list takes focus at once, and the rows come when the CLI answers; a pasted YouTube link opens its item instead.
    function search() {
        const q = query.trim();
        if (q === "")
            return;
        focusPane("list");
        if (F.isLink(q))
            paste(q);
        else
            searchText(q);
    }

    // resolve says what a link names: a video is the only row, a playlist or channel opens as Enter on its row does, and a YouTube URL it cannot place is searched as text.
    function paste(q) {
        searchSeq += 1;
        const seq = searchSeq;
        api(["resolve", q], answer => {
            if (seq !== app.searchSeq)
                return;
            const failure = YT.failure(answer);
            if (!failure && (answer.kind === "playlist" || answer.kind === "channel"))
                return app.open({
                    kind: answer.kind,
                    id: answer.id,
                    title: "",
                    count: null
                });
            if (!failure && answer.kind !== "video")
                return app.searchText(q);
            app.opened = null;
            app.searchFailed = failure;
            app.searched = null;
            app.found = F.page(failure ? null : answer);
            app.cursor = 0;
            app.fetchThumbs(app.results);
        });
    }

    function searchText(q) {
        searchSeq += 1;
        const seq = searchSeq;
        const asked = {
            query: q,
            type: type
        };
        api(["search", q, type, "0"], answer => {
            if (seq !== app.searchSeq)
                return;
            app.opened = null;
            app.searchFailed = YT.failure(answer);
            app.searched = asked;
            app.found = F.page(app.searchFailed ? null : answer);
            app.cursor = 0;
            app.fetchThumbs(app.results);
        });
    }

    // s on a video row: Saved keeps it in the store, at most once; a playlist's snapshot is m70's.
    function save(row) {
        if (row && row.kind === "video")
            store.save(row);
    }

    // Each view's list starts at its top.
    onViewChanged: cursor = 0
    // Saved and History draw from their files with no search behind them, so a thumbnail no list has fetched yet is asked for here.
    onSavedRowsChanged: fetchThumbs(savedRows.filter(r => !thumbs[r.thumb]))
    onHistoryRowsChanged: fetchThumbs(historyRows.filter(r => !thumbs[r.thumb]))

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

    // Saved and History go back to Search, an opened playlist or channel to the results on the row it opened from; Search has nothing behind it, so Esc there closes the App.
    function back() {
        if (view !== "search")
            view = "search";
        else if (opened) {
            searchSeq += 1;
            cursor = opened.back;
            opened = null;
        } else
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

    YouTubeHistory {
        id: history
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
                type: app.type,
                rows: app.rows,
                cursor: app.cursor,
                paging: {
                    next: (app.opened ? app.opened.list : app.found).next,
                    more: (app.opened ? app.opened.list : app.found).more,
                    loading: (app.opened ? app.opened.list : app.found).loading
                },
                opened: app.opened ? {
                    kind: app.opened.kind,
                    id: app.opened.id,
                    title: app.opened.title,
                    count: app.opened.count,
                    back: app.opened.back
                } : null,
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

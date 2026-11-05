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
import "lib/youtube-playlists.mjs" as P
import "lib/youtube-get.mjs" as G

// The YouTube App: its own qs process started by bin/dots-youtube, one window in the shell's theme with a sidebar of views beside their list; the process ends with its window.
ShellRoot {
    id: app

    // Process start to the window's first frame, set once.
    property var firstFrameMs: null
    readonly property string backend: Quickshell.env("DOTS_YOUTUBE") || "dots-youtube-api"
    // The sidebar's entry the list shows: search, saved, history, or playlist with the Playlist's id in playlistId.
    property string view: "search"
    property string playlistId: ""
    readonly property var lists: store.lists
    // The Playlist the list shows, as YouTubeStore lists it, or null.
    readonly property var playlist: view === "playlist" ? store.lists.find(l => l.id === playlistId) || null : null
    readonly property var playlistRows: view === "playlist" ? YT.rows({
        rows: P.items(store.playlists, playlistId)
    }) : []
    // The sidebar's entries top to bottom: the views, then each Playlist as pl:<id>; sideKey is the one the list shows.
    readonly property var sideKeys: look.places.map(p => p.view).concat(store.lists.map(l => "pl:" + l.id))
    readonly property string sideKey: view === "playlist" ? "pl:" + playlistId : view
    // Which pane the keys move in while the field is not focused: sidebar or list.
    property string pane: "list"
    readonly property string focusAt: board.fieldFocused ? "field" : board.nameFocused ? "name" : pane
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
    readonly property var rows: view === "search" ? results : view === "saved" ? savedRows : view === "playlist" ? playlistRows : historyRows
    property int cursor: 0
    // Each search's number: an answer from any search but the last is dropped.
    property int searchSeq: 0
    // Thumbnail files by thumb id, as dots-youtube-api thumbs answers them, and the ids asked for so far.
    property var thumbs: ({})
    property var thumbsAsked: ({})
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
    // The download index as dots-youtube-get keeps it, {files, failed}; read once its where has pruned the files gone since, and on every write after.
    property var downloads: G.index("")
    property string indexPath: ""
    readonly property string getter: Quickshell.shellDir + "/../bin/dots-youtube-get"

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: Y.youtubeLook(theme.tokens)

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

    // j and k: the sidebar's cursor is the view or Playlist it opens, the list's is a row.
    function move(step) {
        if (pane === "sidebar")
            show(sideKeys[Math.max(0, Math.min(sideKeys.length - 1, sideKeys.indexOf(sideKey) + step))]);
        else if (rows.length > 0) {
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

    // n or e in the sidebar: "new" while a new Playlist is named, the Playlist's id while it is renamed, else "".
    property string naming: ""
    // x on a Playlist in the sidebar asks first; y deletes it, Esc keeps it.
    property bool confirming: false

    function startName(what) {
        naming = what;
        board.focusName(what === "new" || !playlist ? "" : playlist.name);
    }

    // A new Playlist opens beside the sidebar at once, so its empty view says how to fill it; one named from the picker takes the video instead, and the list it came from keeps the focus.
    function commitName(text) {
        const video = pendingAdd;
        if (naming === "new") {
            const id = store.create(text);
            if (id !== "" && video)
                store.add(id, video);
            else if (id !== "")
                show("pl:" + id);
        } else if (naming !== "")
            store.rename(naming, text);
        naming = "";
        pendingAdd = null;
        focusPane(video ? "list" : "sidebar");
    }

    function cancelName() {
        const video = pendingAdd;
        naming = "";
        pendingAdd = null;
        focusPane(video ? "list" : "sidebar");
    }

    // s on a playlist: the snapshot dots-youtube-api snapshot is reading, as youtube.mjs snapshotting() makes it, or null.
    property var snapshot: null
    // The Playlist the last snapshot made, marked new in the sidebar until it is opened.
    property string freshId: ""
    // The toast's line, shown for 3 s.
    property string toast: ""

    // p on a video: the video and the picker's cursor, whose last place is new playlist; it starts on the first Playlist that lacks the video. null while the picker is closed.
    property var picking: null
    // A video p is adding to a Playlist n is naming from the picker.
    property var pendingAdd: null

    function pick(row) {
        if (!row || row.kind !== "video")
            return;
        const first = lists.findIndex(l => !store.holds(l.id, row.id));
        picking = {
            video: row,
            cursor: first < 0 ? lists.length : first
        };
    }

    function holds(listId, videoId) {
        return store.holds(listId, videoId);
    }

    function movePick(step) {
        picking = Object.assign({}, picking, {
            cursor: Math.max(0, Math.min(lists.length, picking.cursor + step))
        });
    }

    // Enter on a Playlist adds the video to it, once; on new playlist, or n, the name field opens and the video goes to the Playlist it names.
    function choosePick(fresh) {
        const at = picking.cursor;
        const video = picking.video;
        picking = null;
        if (fresh || at >= lists.length) {
            pendingAdd = video;
            startName("new");
        } else
            store.add(lists[at].id, video);
    }

    // x in a Playlist's list: the item goes and the cursor stays on the row that takes its place.
    function removeItem(row) {
        if (!playlist || !row)
            return;
        store.removeItem(playlistId, row.id);
        cursor = Math.max(0, Math.min(cursor, rows.length - 1));
    }

    // Shift+J and Shift+K: the cursor goes with the item it moves.
    function moveItem(step) {
        const row = rows[cursor];
        if (playlist && row && store.move(playlistId, row.id, step))
            cursor += step;
    }

    // The sidebar moves up to the entry above the deleted Playlist.
    function deleteNow() {
        const id = playlistId;
        confirming = false;
        show(sideKeys[sideKeys.indexOf(sideKey) - 1]);
        store.remove(id);
    }

    // A sidebar key: a view's name, or pl:<id> for a Playlist; a new snapshot's mark goes once it is opened.
    function show(key) {
        if (key === "pl:" + freshId)
            freshId = "";
        if (key.startsWith("pl:")) {
            playlistId = key.slice(3);
            view = "playlist";
        } else
            view = key;
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

    // Enter on a row: each play is an mpv window in a unit of its own, which outlives this window; it pauses the Queue first, and nothing resumes the Queue by itself. A video YouTube marks unavailable never reaches a player.
    function play(row) {
        if (!row || row.kind !== "video" || row.unavailable)
            return;
        history.add(row);
        playVideos([row.id]);
    }

    // Enter in a Playlist plays its items straight through in one window; a whole Playlist adds nothing to History.
    function playPlaylist() {
        const ids = playlistRows.filter(r => !r.unavailable).map(r => r.id);
        if (ids.length > 0)
            playVideos(ids);
    }

    function playVideos(ids) {
        queueCommand(Q.setPauseLine(true));
        // The repo's bin is on the session PATH only through fish, so the player is found beside the shell.
        run([Quickshell.shellDir + "/../bin/dots-youtube-play", "video"].concat(ids), answer => {
            if (answer && typeof answer.unit === "string")
                app.units = app.units.concat([answer.unit]);
        });
    }

    // d and D: a row's audio or video, or every item of the Playlist shown, into the queue dots-youtube-get works through one at a time; what is already downloaded it skips.
    function download(kind, list, name) {
        const lines = G.stdinLines(list);
        if (lines === "")
            return;
        const call = getCaller.createObject(app, {
            command: [getter, kind].concat(name ? ["--playlist", name] : []),
            lines: lines
        });
        call.running = true;
    }

    function downloadKey(kind) {
        if (playlist)
            download(kind, playlistRows, playlist.name);
        else if (pane === "list" && rows[cursor])
            download(kind, [rows[cursor]], "");
    }

    function hasFile(id) {
        return G.downloaded(downloads, id);
    }

    function downloadFailed(id) {
        return G.failedOf(downloads, id);
    }

    // Enter on a row whose download failed asks for that download again.
    function retryDownload(row) {
        const f = row ? downloadFailed(row.id) : null;
        if (f)
            download(f.kind, [row], "");
    }

    // m plays a row in the Queue in place of what it holds, a appends it.
    function queueItem(row, how) {
        if (!row || row.kind !== "video" || row.unavailable)
            return;
        history.add(row);
        withFiles([row], files => app.sendQueue(Q.itemLines(app.queue, row, how, files)));
    }

    // m, a and S on a Playlist: its items in order, appended, or shuffled, by DOTS_YOUTUBE_SEED when a check sets one; none of them goes to History.
    function queuePlaylist(how) {
        const rows = playlistRows;
        withFiles(rows, files => app.sendQueue(how === "shuffle" ? Q.shuffledLines(app.queue, rows, parseInt(Quickshell.env("DOTS_YOUTUBE_SEED") || "", 10), files) : Q.listLines(app.queue, rows, how, files)));
    }

    // Rows with a downloaded file wait for dots-youtube-get where, which drops a file gone since so it streams; a press after one that waits waits behind it, so the Queue takes them in the order pressed.
    property var queueWaits: []

    function withFiles(list, then) {
        const ids = list.filter(r => hasFile(r.id)).map(r => r.id);
        if (ids.length === 0 && queueWaits.length === 0)
            return then({});
        queueWaits = queueWaits.concat([{
                ids: ids,
                then: then
            }]);
        if (queueWaits.length === 1)
            nextWait();
    }

    function nextWait() {
        const w = queueWaits[0];
        const done = files => {
            w.then(files);
            app.queueWaits = app.queueWaits.slice(1);
            if (app.queueWaits.length > 0)
                app.nextWait();
        };
        if (w.ids.length === 0)
            done({});
        else
            run([getter, "where"].concat(w.ids), answer => done(G.playFiles(answer)));
    }

    // The first ask with no Queue connected starts youtube-audio, and what follows waits for its socket.
    function sendQueue(lines) {
        if (lines.length === 0)
            return;
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

    // Space, r and a video's pause: a command with no Queue connected has nothing to reach. It waits behind any load still asking where, so Enter's pause never comes before the song m loaded and unpaused (CE6JY061).
    function queueCommand(line) {
        withFiles([], () => {
            if (app.link.status === "up")
                app.writeQueue([line]);
        });
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

    // s: anywhere in an opened playlist, or on a playlist row, saves the playlist whole as a Playlist; on a video it goes to Saved, at most once.
    function save(row) {
        if (view === "search" && opened && opened.kind === "playlist" && failed === null)
            snapshotOf(opened.id, opened.title, opened.count);
        else if (row && row.kind === "playlist")
            snapshotOf(row.id, row.title, row.count);
        else if (row && row.kind === "video")
            store.save(row);
    }

    // One snapshot reads at a time.
    function snapshotOf(id, title, count) {
        if (snapshot !== null)
            return;
        snapshot = YT.snapshotting(id, title, count);
        snapshotProc.command = [backend, "snapshot", id];
        snapshotProc.running = true;
    }

    function snapshotLine(text) {
        if (snapshot === null)
            return;
        snapshot = YT.snapshotStep(snapshot, text);
        if (snapshot.done)
            finishSnapshot();
    }

    // The new Playlist holds the items as they were read; it never follows the original.
    function finishSnapshot() {
        const s = snapshot;
        snapshot = null;
        if (s.failed)
            return say(s.failed.error);
        const id = store.snapshot(s.title, s.rows);
        if (id === "")
            return;
        freshId = id;
        say(look.toast.saved(s.rows.length));
    }

    function say(text) {
        toast = text;
        toastTick.restart();
    }

    // Each view's list starts at its top.
    onViewChanged: cursor = 0
    onPlaylistIdChanged: cursor = 0
    // Saved and History draw from their files with no search behind them, so a thumbnail no list has fetched yet is asked for here.
    onSavedRowsChanged: fetchThumbs(savedRows.filter(r => !thumbs[r.thumb]))
    onHistoryRowsChanged: fetchThumbs(historyRows.filter(r => !thumbs[r.thumb]))
    onPlaylistRowsChanged: fetchThumbs(playlistRows.filter(r => !thumbs[r.thumb]))

    // Thumbs calls for a list's ids, 20 at a time, the next once the last answers, so a long list draws its top rows first; an id already asked for is not asked again, unless its call failed. A thumb no call names keeps its row's placeholder.
    function fetchThumbs(list) {
        const ids = list.map(r => r.thumb).filter((t, i, all) => t && !thumbsAsked[t] && all.indexOf(t) === i);
        if (ids.length === 0)
            return;
        markThumbs(ids, true);
        fetchBatch(ids);
    }

    function fetchBatch(ids) {
        const batch = ids.slice(0, 20);
        api(["thumbs"].concat(batch), answer => {
            const files = answer && answer.files;
            if (files && typeof files === "object")
                app.thumbs = Object.assign({}, app.thumbs, files);
            else
                app.markThumbs(ids, false);
            if (files && ids.length > 20)
                app.fetchBatch(ids.slice(20));
        });
    }

    function markThumbs(ids, on) {
        const asked = Object.assign({}, thumbsAsked);
        for (const t of ids)
            asked[t] = on;
        thumbsAsked = asked;
    }

    // The file a thumb id draws from, or "" for its placeholder.
    function thumbSource(id) {
        const f = thumbs[id];
        return typeof f === "string" && f.startsWith("/") ? "file://" + f : "";
    }

    // Saved, History and a Playlist go back to Search, an opened playlist or channel to the results on the row it opened from; Search has nothing behind it, so Esc there closes the App.
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

    // dots-youtube-get where makes the index when there is none, so the watch below starts on a file that exists.
    Component.onCompleted: run([getter, "where"], () => {
        app.indexPath = (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/youtube/downloads.json";
    })

    // dots-youtube-get renames each write over the index, and the watch follows the path.
    FileView {
        path: app.indexPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: app.downloads = G.index(text())
        onLoadFailed: app.downloads = G.index("")
    }

    // A download's rows go in on stdin; a refusal, such as no yt-dlp, shows as the toast.
    Component {
        id: getCaller

        Process {
            property string lines: ""
            stdinEnabled: true
            stdout: StdioCollector {
                id: getOut
            }
            onStarted: {
                write(lines);
                stdinEnabled = false;
            }
            onExited: {
                const answer = YT.answer(getOut.text);
                if (answer && typeof answer.error === "string")
                    app.say(answer.error);
                destroy();
            }
        }
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

    // A snapshot's answer comes a line at a time; one that ends with no last line failed without saying why, and the line it did print is read first.
    Process {
        id: snapshotProc
        stdout: SplitParser {
            onRead: text => app.snapshotLine(text)
        }
        onExited: Qt.callLater(() => {
            if (app.snapshot !== null)
                app.snapshotLine(JSON.stringify({
                    error: "dots-youtube-api gave no answer"
                }));
        })
    }

    Tick {
        id: toastTick
        interval: 3000
        onTriggered: app.toast = ""
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
                playlistId: app.playlistId,
                naming: app.naming,
                picking: app.picking ? app.picking.cursor : null,
                snapshot: app.snapshot ? {
                    read: app.snapshot.read,
                    count: app.snapshot.count
                } : null,
                freshId: app.freshId,
                confirming: app.confirming,
                playlists: store.lists,
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
                downloads: app.downloads,
                queue: app.queue,
                error: app.failed,
                firstFrameMs: app.firstFrameMs,
                rssKiB: Status.rssKiB(procStatus.text())
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

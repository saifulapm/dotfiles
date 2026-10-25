//@ pragma AppId dekho
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import "services" as Services
import "lib/dekho.mjs" as D
import "lib/dekho-playing.mjs" as P
import "lib/status.mjs" as Status
import "lib/voice.mjs" as L

// Dekho, an App: its own qs process started by bin/dots-dekho, a normal window in the shell's theme that routes between its pages; the process ends with its window.
ShellRoot {
    id: app

    // Process start to the window's first frame, set once.
    property var firstFrameMs: null
    // The pages open, Home at the root; Esc on Home closes the window.
    property var stack: [
        {
            page: "home",
            args: null
        }
    ]
    readonly property string page: stack[stack.length - 1].page
    // The id Enter last opened, for checks.
    property var opened: null
    readonly property string backend: Quickshell.env("DOTS_DEKHO") || "dekho"
    // The TMDB images on disk, by size and then path, as prefetch has listed them; each picture binds its own path, so an answer for another title or older rows only adds paths nothing drawn names.
    property var pictures: ({})
    // Each size's cache folder as the backend names it, "" while asked; a file there draws at once, so a picture on disk never waits for a prefetch held up by the network.
    property var folders: ({})
    // What plays in the film's unit, from its session's events: {id, kind, title, episode}, else null. Every page's bar draws it.
    property var nowPlaying: null
    property var playEvents: []
    // The session followed: Starting's run, or the run a reopened Dekho finds active.
    property string playSession: ""
    property var playTail: null
    readonly property string playBin: Quickshell.shellDir + "/../bin/dots-dekho-play"

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property string voice: look.voice

    // qs has no quit, so a child ends its parent: the process must not outlive the window.
    function quit() {
        ender.running = true;
    }

    // A one-line notice at the window's bottom for 2.4 s; a second one takes its place.
    function toast(text) {
        toastItem.show(text);
    }

    // Plays a title's trailer, {id, kind, title}, in its own mpv window.
    function trailer(target) {
        trailers.play(target);
    }

    function open(page, args) {
        // Leaving a Title page keeps it, since a credit's title opened further on reloads the one shared page.
        const top = stack[stack.length - 1];
        if (top && top.page === "title")
            top.title = titlePage.snapshot();
        stack = stack.concat([
            {
                page: page,
                args: args
            }
        ]);
    }

    function back() {
        if (stack.length <= 1)
            return quit();
        stack = stack.slice(0, -1);
        const top = stack[stack.length - 1];
        if (top.page === "title" && top.title && top.title.entry !== titlePage.entry)
            titlePage.restore(top.title);
    }

    // Runs `dekho <args>` off the render loop and hands done its one JSON answer, or null when it failed.
    function api(args, done) {
        const call = caller.createObject(app, {
            command: [backend].concat(args)
        });
        call.done = done;
        call.running = true;
    }

    // One prefetch call for one list's images of one size, then done; a path it does not list keeps its place's empty mark.
    function prefetch(size, paths, done) {
        // The backend names a size's folder at once when asked for no paths, as nothing is missing.
        if (folders[size] === undefined) {
            folders = Object.assign({}, folders, {
                [size]: ""
            });
            api(["api", "prefetch", "--size", size], answer => {
                if (answer && typeof answer.dir === "string" && answer.dir.startsWith("/"))
                    app.folders = Object.assign({}, app.folders, {
                        [size]: answer.dir
                    });
            });
        }
        const want = D.wanted(paths, pictures[size] || {});
        if (want.length === 0)
            return done ? done() : undefined;
        api(["api", "prefetch", "--size", size].concat(want), answer => {
            app.pictures = Object.assign({}, app.pictures, {
                [size]: D.withFiles(app.pictures[size] || {}, answer, want)
            });
            if (done)
                done();
        });
    }

    // What is in a size's folder joins what is on disk, as it is read and as each download lands.
    function seen(size, folder) {
        const names = [];
        for (let i = 0; i < folder.count; i++)
            names.push(folder.get(i, "fileName"));
        pictures = Object.assign({}, pictures, {
            [size]: D.onDisk(pictures[size] || {}, folders[size], names)
        });
    }

    // A picture's file URL once it is on disk, else "".
    function picture(size, path) {
        const file = D.picturePath(path) && pictures[size] ? pictures[size][path] : "";
        return file ? "file://" + file : "";
    }

    // Follows a film's session file from its first line; a play that never plays shows no bar.
    function follow(session) {
        if (playTail)
            playTail.running = false;
        playSession = session;
        playEvents = [];
        nowPlaying = null;
        playTail = tailer.createObject(app, {
            session: session
        });
        playTail.running = true;
    }

    function playHeard(session, line) {
        const e = D.answer(line);
        if (!e || session !== playSession)
            return;
        playEvents = playEvents.concat([e]);
        const was = nowPlaying;
        nowPlaying = P.fromEvents(playEvents);
        if (was && !nowPlaying)
            ended();
        else if (e.event === "exit")
            unfollow();
    }

    // A run that ended before it played, or was cancelled in Starting, needs no tail.
    function unfollow() {
        if (playTail)
            playTail.running = false;
        playTail = null;
        playSession = "";
    }

    // The run is over, by mpv quitting, a stop, or its unit gone: the bar goes, and Continue watching and Resume read history again.
    function ended() {
        if (playTail)
            playTail.running = false;
        playTail = null;
        playSession = "";
        nowPlaying = null;
        home.reloadHistory();
        titlePage.refreshSeen();
    }

    function stopPlay() {
        if (nowPlaying && !stopper.running)
            stopper.running = true;
    }

    function openTitle(hit) {
        opened = hit.id;
        titlePage.load(hit);
        open("title", hit);
    }

    Services.Theme {
        id: theme
    }

    Instantiator {
        model: ["w185", "w342", "w780"]

        FolderListModel {
            required property string modelData
            folder: app.folders[modelData] ? "file://" + app.folders[modelData] : ""
            showDirs: false
            onCountChanged: app.seen(modelData, this)
        }
    }

    Component {
        id: tailer

        // tail ends with the App, even one killed outright, by watching qs's pid; it never stops the unit.
        Process {
            property string session: ""
            command: ["sh", "-c", "exec tail --pid=\"$PPID\" -n +1 -s 0.1 -F \"$1\"", "sh", session]
            stdout: SplitParser {
                onRead: line => app.playHeard(session, line)
            }
            onRunningChanged: {
                if (!running)
                    destroy();
            }
        }
    }

    // A run already playing when Dekho opens is adopted, never started again; while one plays, a unit gone without its exit event ends it too.
    Process {
        id: playStatus
        command: [app.playBin, "--status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const s = D.answer(text);
                if (!s)
                    return;
                if (s.active && s.session && s.session !== app.playSession)
                    app.follow(s.session);
                else if (!s.active && app.nowPlaying)
                    app.ended();
            }
        }
    }
    Tick {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: app.nowPlaying !== null
        onTriggered: {
            if (!playStatus.running)
                playStatus.running = true;
            if (!playWindow.running)
                playWindow.running = true;
        }
    }
    // A series moves on with no event of dekho's: the windows' JSON on the first line, then the pids in the film's unit, whose mpv window names the episode on screen.
    Process {
        id: playWindow
        command: ["sh", "-c", "niri msg -j windows; echo; cg=$(systemctl --user show -p ControlGroup --value \"$1.service\"); [ -z \"$cg\" ] || cat \"/sys/fs/cgroup$cg/cgroup.procs\" 2>/dev/null", "sh", Quickshell.env("DOTS_DEKHO_UNIT") || "dekho-play"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                if (app.nowPlaying)
                    app.nowPlaying = P.fromWindow(app.nowPlaying, lines[0], lines.slice(1).filter(l => l !== "").map(Number));
            }
        }
    }

    Process {
        id: stopper
        command: [app.playBin, "--stop"]
        onExited: app.ended()
    }

    Component {
        id: caller

        Process {
            property var done: null
            stdout: StdioCollector {
                id: answerOut
            }
            onExited: {
                const answer = D.answer(answerOut.text);
                if (done)
                    done(answer);
                destroy();
            }
        }
    }

    Process {
        id: ender
        // Its children first: qs dies on SIGTERM without ending them, which would leave a dekho call running on.
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
        target: "dekho"

        function state(): string {
            procStatus.reload();
            return JSON.stringify(Object.assign({
                page: app.page,
                firstFrameMs: app.firstFrameMs,
                rssKiB: Status.rssKiB(procStatus.text()),
                voice: app.voice,
                opened: app.opened,
                toast: toastItem.state(),
                playing: app.nowPlaying,
                bar: ({
                        home: home.playingBar,
                        title: titlePage.playingBar,
                        browse: browsePage.playingBar,
                        person: personPage.playingBar
                    })[app.page].drawn()
            }, home.state(), titlePage.state(),
            releases.state(),
            browsePage.state(),
            personPage.state(),
            trailers.state()));
        }
    }

    FloatingWindow {
        id: win

        title: "Dekho"
        implicitWidth: 1200
        implicitHeight: 716
        color: app.c.surface ?? "white"

        Connections {
            target: win.contentItem.Window.window
            function onFrameSwapped() {
                if (app.firstFrameMs !== null)
                    return;
                uptime.reload();
                app.firstFrameMs = Status.processAgeMs(uptime.text(), selfStat.text());
            }
        }

        DekhoHome {
            id: home
            anchors.fill: parent
            visible: app.page === "home"
            focus: visible
            dekho: app
        }

        DekhoTitle {
            id: titlePage
            anchors.fill: parent
            visible: app.page === "title"
            focus: visible
            dekho: app
            // / searches from Home's field, with Home's rows behind it.
            onSearch: {
                app.back();
                home.focusSearch();
            }
        }

        DekhoReleases {
            id: releases
            anchors.fill: parent
            dekho: app
            onSearch: {
                app.back();
                home.focusSearch();
            }
        }
        Connections {
            target: titlePage
            function onRelease(t) {
                releases.choose(t, titlePage);
            }
            function onResume(item) {
                releases.resume(item, titlePage);
            }
        }
        Connections {
            target: home
            function onResume(item) {
                releases.resume(item, home);
            }
        }

        DekhoTrailer {
            id: trailers
            dekho: app
        }

        DekhoBrowse {
            id: browsePage
            anchors.fill: parent
            visible: app.page === "browse"
            focus: visible
            dekho: app
        }

        DekhoPerson {
            id: personPage
            anchors.fill: parent
            visible: app.page === "person"
            focus: visible
            dekho: app
            // / searches from Home's field, past every page opened since.
            onSearch: {
                app.stack = app.stack.slice(0, 1);
                home.focusSearch();
            }
        }

        // Shift+S stops the film from any page; a text field takes its own S first.
        Shortcut {
            sequence: "Shift+S"
            enabled: app.nowPlaying !== null && releases.mode === ""
            onActivated: app.stopPlay()
        }

        // Last, so it draws over every page and the release overlay; 56 px up keeps it off a page's keys strip.
        DekhoToast {
            id: toastItem
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 56
            dekho: app
        }
    }
}

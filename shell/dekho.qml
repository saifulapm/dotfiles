//@ pragma AppId dekho
import Quickshell
import Quickshell.Io
import QtQuick
import "services" as Services
import "lib/dekho.mjs" as D
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

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property string voice: look.voice

    // qs has no quit, so a child ends its parent: the process must not outlive the window.
    function quit() {
        ender.running = true;
    }

    function open(page, args) {
        stack = stack.concat([
            {
                page: page,
                args: args
            }
        ]);
    }

    function back() {
        if (stack.length > 1)
            stack = stack.slice(0, -1);
        else
            quit();
    }

    // Runs `dekho <args>` off the render loop and hands done its one JSON answer, or null when it failed.
    function api(args, done) {
        const call = caller.createObject(app, {
            command: [backend].concat(args)
        });
        call.done = done;
        call.running = true;
    }

    function openTitle(hit) {
        opened = hit.id;
        // t7: title page
        titlePage.load(hit);
        open("title", hit);
    }

    Services.Theme {
        id: theme
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
                // t11: saved rows
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
                opened: app.opened
            }, home.state(), titlePage.state(),
            // t8: releases state
            {},
            // t9: browse state
            {},
            // t10: person state
            {}));
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

        // t8: releases and starting

        // t9: browse

        // t10: person
    }
}

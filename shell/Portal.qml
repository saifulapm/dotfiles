import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/picker.mjs" as P

// bin/dots-portal's other end: each connection is one file chooser request, held open until the picker answers it; a request that comes while one shows waits its turn.
Scope {
    id: portal

    // The shell's loader of the Surfaces window (active, item).
    required property var surfaces
    readonly property var card: surfaces.item?.picker ?? null
    // {socket, request, t0} entries, oldest first, behind the one shown.
    property var waiting: []
    property var current: null

    function next() {
        if (current || waiting.length === 0)
            return;
        const c = waiting[0];
        waiting = waiting.slice(1);
        current = c;
        surfaces.active = true;
        surfaces.item.openPicker(Object.assign({}, c.request, {
            t0: c.t0,
            answer: text => portal.answer(c, text)
        }));
    }

    // The picker's answer line goes to this request's connection only.
    function answer(c, text) {
        if (current !== c)
            return;
        current = null;
        if (c.socket.connected) {
            c.socket.write(text);
            c.socket.flush();
            c.socket.connected = false;
        }
        next();
    }

    // The app closed its request, so its card goes, or it leaves the queue, and nothing is written.
    function hungUp(socket) {
        waiting = waiting.filter(w => w.socket !== socket);
        if (current?.socket === socket) {
            current = null;
            card?.dismiss();
            next();
        }
    }

    SocketServer {
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/dots-picker-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            id: connection
            onConnectedChanged: if (!connected)
                portal.hungUp(connection)
            parser: SplitParser {
                onRead: data => {
                    // Taken before the surface loads, so a cold open's time includes loading.
                    const t0 = Date.now();
                    const request = P.parseRequest(data);
                    if (!request) {
                        connection.write(P.answerLine(2, []));
                        connection.flush();
                        connection.connected = false;
                        return;
                    }
                    portal.waiting = portal.waiting.concat([{ socket: connection, request: request, t0: t0 }]);
                    portal.next();
                }
            }
        }
    }

    Root.Ipc {
        target: "picker"

        function state(): string {
            const shown = portal.card ? JSON.parse(portal.card.state()) : { loaded: false, open: false, settled: false, keyboard: false, mode: "", app: "", heading: "", folder: "", rows: [], selected: 0, name: "", question: false, notice: "", marked: [], foot: "", openMs: null, opens: 0 };
            return JSON.stringify(Object.assign(shown, { waiting: portal.waiting.length }));
        }
    }
}

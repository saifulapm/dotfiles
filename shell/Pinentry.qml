import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/pinentry.mjs" as P

// bin/dots-pinentry's other end: each connection is one gpg request, held open until the card answers it; a request that comes while one shows waits its turn.
Scope {
    id: pinentry

    // The shell's loader of the Surfaces window (active, item).
    required property var surfaces
    readonly property var card: surfaces.item?.pinentry ?? null
    // {socket, request} pairs, oldest first, behind the one shown.
    property var waiting: []
    property var current: null

    function next() {
        if (current || waiting.length === 0)
            return;
        const c = waiting[0];
        waiting = waiting.slice(1);
        current = c;
        surfaces.active = true;
        surfaces.item.openPinentry({
            kind: c.request.kind,
            description: c.request.description,
            prompt: c.request.prompt,
            error: c.request.error,
            answer: text => pinentry.answer(c, text)
        });
    }

    // The card's answer goes to the stub, which hands it to gpg as it is.
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

    // gpg gave up (the client went, or the agent interrupted its pinentry), so its card goes too.
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
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/dots-pinentry-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            id: connection
            onConnectedChanged: if (!connected)
                pinentry.hungUp(connection)
            parser: SplitParser {
                onRead: data => {
                    const request = P.parseRequest(data);
                    if (!request) {
                        connection.write(P.CANCEL);
                        connection.flush();
                        connection.connected = false;
                        return;
                    }
                    pinentry.waiting = pinentry.waiting.concat([{ socket: connection, request: request }]);
                    pinentry.next();
                }
            }
        }
    }

    Root.Ipc {
        target: "pinentry"

        function state(): string {
            const shown = pinentry.card ? JSON.parse(pinentry.card.state()) : { open: false, loaded: false };
            return JSON.stringify(Object.assign(shown, { waiting: pinentry.waiting.length }));
        }
    }
}

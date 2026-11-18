import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/pinentry.mjs" as P

// bin/dots-pinentry's other end: each connection is one gpg-agent pinentry run, whose requests come one line at a time, the retries after a wrong passphrase among them; the prompt holds the island until the run hangs up, and a connection that comes while one shows waits its turn.
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
        show(c);
    }

    function show(c) {
        surfaces.active = true;
        surfaces.item.openPinentry({
            kind: c.request.kind,
            description: c.request.description,
            prompt: c.request.prompt,
            error: c.request.error,
            answer: text => pinentry.answer(c, text),
            hangUp: () => pinentry.hangUp(c)
        });
    }

    // The card's answer goes to the stub, which hands it to gpg as it is; the connection stays current, so the prompt holds the island while gpg-agent checks the answer.
    function answer(c, text) {
        if (current !== c || !c.socket.connected)
            return;
        c.socket.write(text);
        c.socket.flush();
    }

    // Esc or Cancel while gpg-agent checks an answer: the stub cancels whatever gpg-agent asks next.
    function hangUp(c) {
        if (current !== c)
            return;
        c.socket.connected = false;
        hungUp(c.socket);
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
                    // gpg-agent asking again on the shown connection, after a wrong passphrase, shows in the same prompt.
                    if (pinentry.current?.socket === connection) {
                        pinentry.current.request = request;
                        pinentry.show(pinentry.current);
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

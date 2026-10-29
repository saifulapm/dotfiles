pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "lib/bt-pairing.mjs" as P

// bin/dots-bt-agent's other end: each connection is one BlueZ request, held open until the island answers it or the agent hangs up; a request that comes while one shows waits its turn. Control's Enter on a new device runs its pair, trust and connect here, so the steps outlive Control closing.
Singleton {
    id: pairing

    // {socket, request, id} entries, oldest first, behind the one shown.
    property var waiting: []
    property var current: null
    // What has been typed for a PIN or passkey request.
    property string pin: ""
    property int serial: 0
    // The request as the island's question slot shows it: no options, the keys that answer it, and the kind.
    readonly property var question: current ? {
        "id": current.id,
        project: "Bluetooth",
        machine: "",
        text: P.promptText(current.request),
        options: [],
        pairing: current.request.kind,
        keys: P.keyText(current.request.kind)
    } : null
    // The device Control asked to pair, until its pair ends.
    property var device: null

    signal failed(string device)

    function next() {
        if (current || waiting.length === 0)
            return;
        current = waiting[0];
        waiting = waiting.slice(1);
        pin = "";
    }

    function answer(ok) {
        const c = current;
        if (!c)
            return;
        current = null;
        if (c.socket.connected) {
            c.socket.write(P.answerLine(c.request.kind, ok, pin));
            c.socket.flush();
            c.socket.connected = false;
        }
        next();
    }

    // The agent gave up (BlueZ cancelled, the pair ended or the time ran out), so its question goes too.
    function hungUp(socket) {
        waiting = waiting.filter(w => w.socket !== socket);
        if (current?.socket === socket) {
            current = null;
            next();
        }
    }

    // A pair that failed on the device side gets no Cancel for a code it only showed, so its questions go here; each hang-up reaches hungUp.
    function dropFor(address) {
        for (const c of waiting.concat(current ? [current] : []))
            if (c.request.address === address)
                c.socket.connected = false;
    }

    // Enter answers yes, Esc no; a PIN or passkey takes typed characters and Backspace; a code shown on the device has only Esc.
    function key(event) {
        if (!current)
            return false;
        const kind = current.request.kind;
        if (event.key === Qt.Key_Escape)
            answer(false);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (kind !== "display" && ((kind !== "pin" && kind !== "passkey") || pin !== ""))
                answer(true);
        } else if (event.key === Qt.Key_Backspace)
            pin = pin.slice(0, -1);
        else
            pin = P.typed(kind, pin, event.text);
        return true;
    }

    // Pairs a new device, then trusts and connects it. Quickshell's own pair gives up at D-Bus's 25 s default while the agent's question still shows, so Pair runs here with room for the agent's 60 s and says by its exit how it ended.
    function pairTrustConnect(d) {
        if (pairer.running)
            return;
        device = d;
        pairer.command = ["gdbus", "call", "--system", "--timeout", "90", "--dest", "org.bluez", "--object-path", d.dbusPath, "--method", "org.bluez.Device1.Pair"];
        pairer.running = true;
    }

    Process {
        id: pairer
        stderr: StdioCollector {
            id: pairErr
        }
        onExited: code => {
            const d = pairing.device;
            pairing.device = null;
            if (!d)
                return;
            if (code === 0) {
                d.trusted = true;
                d.connect();
                return;
            }
            console.warn("pairing: Pair on " + d.address + " failed: " + pairErr.text.trim());
            pairing.dropFor(d.address);
            pairing.failed(P.deviceName(d.deviceName, d.address));
        }
    }

    SocketServer {
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/dots-bt-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            id: connection
            onConnectedChanged: if (!connected)
                pairing.hungUp(connection)
            parser: SplitParser {
                onRead: data => {
                    const request = P.parseRequest(data);
                    if (!request) {
                        connection.write(P.answerLine("", false, ""));
                        connection.flush();
                        connection.connected = false;
                        return;
                    }
                    pairing.serial += 1;
                    pairing.waiting = pairing.waiting.concat([{
                            socket: connection,
                            request: request,
                            id: "bt-" + pairing.serial
                        }]);
                    pairing.next();
                }
            }
        }
    }
}

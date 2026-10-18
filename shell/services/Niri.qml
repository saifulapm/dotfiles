import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/niri.mjs" as N

// Workspaces and windows from niri's event stream on $NIRI_SOCKET. niri sends the whole
// state first and then each change, so nothing here polls.
Scope {
    id: niri

    property var state: N.initial
    readonly property string focusedOutput: N.focusedOutput(state) ?? ""

    function view(output) {
        return N.outputView(state, output);
    }

    Socket {
        path: Quickshell.env("NIRI_SOCKET")
        connected: true
        onConnectedChanged: {
            if (connected) {
                write('"EventStream"\n');
                flush();
            }
        }
        parser: SplitParser {
            onRead: line => niri.state = N.reduce(niri.state, JSON.parse(line))
        }
    }
}

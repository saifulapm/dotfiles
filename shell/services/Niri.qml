import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/niri.mjs" as N

// niri's event stream sends the whole state first and then each change, so nothing here polls.
Scope {
    id: niri

    property var state: N.initial
    readonly property string focusedOutput: N.focusedOutput(state) ?? ""
    readonly property bool overview: state.overview

    function view(output) {
        return N.outputView(state, output);
    }

    function urgent(output) {
        return N.urgentWorkspaces(state, output);
    }

    function column(output) {
        return N.columnPosition(state, output);
    }

    function shares(ownPid) {
        return N.shares(state, ownPid);
    }

    Socket {
        id: stream
        path: Quickshell.env("NIRI_SOCKET")
        connected: true
        onConnectedChanged: {
            // The stream starts with the whole state again, so nothing from before a drop is kept but a failed config, which the shell has already told.
            niri.state = N.reconnected(niri.state);
            if (connected) {
                write('"EventStream"\n');
                flush();
            } else {
                // niri drops a client 64 events behind and Quickshell connects only once, so the shell connects again, after Quickshell's own handler returns.
                Qt.callLater(() => stream.connected = true);
            }
        }
        parser: SplitParser {
            onRead: line => {
                const before = niri.state;
                niri.state = N.reduce(before, JSON.parse(line));
                if (N.configNotifies(before, niri.state))
                    Quickshell.execDetached(["notify-send", "-a", "niri", "Config rejected", "niri still runs the last good config"]);
            }
        }
    }
}

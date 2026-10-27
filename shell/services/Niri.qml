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

    Socket {
        path: Quickshell.env("NIRI_SOCKET")
        connected: true
        onConnectedChanged: {
            if (connected) {
                // The stream starts with the whole state again, so nothing from before a drop is kept.
                niri.state = N.initial;
                write('"EventStream"\n');
                flush();
            }
        }
        parser: SplitParser {
            onRead: line => niri.state = N.reduce(niri.state, JSON.parse(line))
        }
    }
}

import Quickshell
import Quickshell.Io
import QtQuick

// The drag check's drop target: a window that writes every drop's formats and raw data as JSON to DROP_OUT.
ShellRoot {
    FloatingWindow {
        id: win
        property var drops: []
        implicitWidth: 400
        implicitHeight: 300
        color: "#202020"
        title: "drop-target"

        DropArea {
            anchors.fill: parent
            onDropped: drop => {
                win.drops = win.drops.concat([{
                        formats: drop.formats,
                        uriList: drop.formats.indexOf("text/uri-list") >= 0 ? drop.getDataAsString("text/uri-list") : null,
                        text: drop.formats.indexOf("text/plain") >= 0 ? drop.getDataAsString("text/plain") : null
                    }]);
                out.setText(JSON.stringify(win.drops));
                drop.accept(Qt.CopyAction);
            }
        }

        FileView {
            id: out
            path: Quickshell.env("DROP_OUT")
            atomicWrites: true
            printErrors: false
        }
    }
}

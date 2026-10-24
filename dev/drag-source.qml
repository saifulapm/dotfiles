import Quickshell
import QtQuick

// The drop check's drag source: a window whose drag offers DRAG_FILES (paths, one a line) as text/uri-list, as Chromium's downloads offer a file.
ShellRoot {
    FloatingWindow {
        id: win
        readonly property string uris: Quickshell.env("DRAG_FILES").split("\n").filter(p => p).map(p => "file://" + p.split("/").map(encodeURIComponent).join("/") + "\r\n").join("")
        implicitWidth: 300
        implicitHeight: 200
        color: "#203040"
        title: "drag-source"

        MouseArea {
            id: area
            anchors.fill: parent
            drag.target: offer
        }

        Item {
            id: offer
            Drag.active: area.drag.active
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.mimeData: ({
                    "text/uri-list": win.uris
                })
        }
    }
}

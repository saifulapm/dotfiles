import Quickshell.Io
import QtQuick
import "." as Root

// An IpcHandler the shell also answers over its own socket, for dots-call; qs ipc reaches it as before.
IpcHandler {
    id: handler

    Component.onCompleted: Root.State.addIpc(handler)
    Component.onDestruction: Root.State.removeIpc(handler)
}

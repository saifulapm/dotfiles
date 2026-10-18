import Quickshell
import Quickshell.Io
import QtQuick

// The session lock: a WlSessionLock cannot live in the Overlay host, so it is the one surface outside it.
Scope {
    id: lock

    required property var theme

    IpcHandler {
        target: "lock"

        function lock(): void {
        }

        function state(): string {
            return JSON.stringify({ locked: false });
        }
    }
}

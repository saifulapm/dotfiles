import QtQuick
import "." as Root

// Mod+C: Audio, Wi-Fi, Bluetooth, Power, Display and Route, drawn in the Surfaces window.
Item {
    id: control

    required property var theme
    property bool shown: false
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        shown = true;
        forceActiveFocus();
    }

    function close() {
        shown = false;
    }

    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function state() {
        return JSON.stringify({ open: shown, openMs: openMs, opens: opens });
    }

    Component.onCompleted: Root.State.loaded.push("control")
    visible: shown
    Keys.onEscapePressed: close()
}

import QtQuick
import "." as Root

// Mod+Shift+R: the region picker, drawn in the Surfaces window, and the recording it starts.
Item {
    id: recorder

    required property var theme
    // The picker is up; the host gives it the keyboard.
    property bool shown: false
    property bool recording: false

    function toggle() {
        if (shown)
            close();
        else
            open();
    }

    function open() {
        shown = true;
        forceActiveFocus();
    }

    function close() {
        shown = false;
    }

    function swapped() {
    }

    function state() {
        return JSON.stringify({ picking: shown, recording: recording });
    }

    Component.onCompleted: Root.State.loaded.push("recorder")
    visible: shown
    Keys.onEscapePressed: close()
}

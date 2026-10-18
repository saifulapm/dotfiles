import QtQuick
import "." as Root

// The one Overlay prompt a polkit request shows, drawn in the Surfaces window.
Item {
    id: prompt

    required property var theme
    property bool shown: false

    function close() {
        shown = false;
    }

    function swapped() {
    }

    function state() {
        return JSON.stringify({ open: shown });
    }

    Component.onCompleted: Root.State.loaded.push("polkit")
    visible: shown
}

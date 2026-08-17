import QtQuick
import "../components"

// Focused window title, omarchy-style: bare text at 0.85 opacity, elided at
// maxWidth, animated width; middle or right click closes the window.
//
// Hidden on a vertical bar, exactly as theirs is: a title is a run of text,
// and a 28 px column has nowhere to put one.
BarButton {
    id: rootItem

    required property var niri
    // Inline shell.json entry {"id": "window", "maxWidth": N} — omarchy's
    // window widget reads the same key from its settings.
    readonly property int maxWidth: Number(setting("maxWidth", 280))

    visible: niri.focusedTitle !== "" && !vertical
    tooltipText: label.truncated ? niri.focusedTitle : ""

    onTapped: button => {
        if (button === Qt.MiddleButton || button === Qt.RightButton)
            rootItem.niri.closeFocusedWindow();
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: rootItem.theme.time(1.2)
            easing.type: rootItem.theme.motion.easing
        }
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, rootItem.maxWidth)
        elide: Text.ElideRight
        opacity: 0.85
        color: rootItem.contentColor
        font.family: rootItem.theme.fontMono
        font.pixelSize: rootItem.theme.fontPx(1.0)
        renderType: Text.NativeRendering
        text: rootItem.niri.focusedTitle
    }
}

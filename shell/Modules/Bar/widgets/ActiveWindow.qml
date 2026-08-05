import QtQuick
import "../components"

// Focused window title, omarchy-style: bare text at 0.85 opacity, elided at
// maxWidth, animated width; middle or right click closes the window.
BarButton {
    id: rootItem

    required property var niri
    property int maxWidth: 280

    visible: niri.focusedTitle !== ""
    tooltipText: label.truncated ? niri.focusedTitle : ""

    onTapped: button => {
        if (button === Qt.MiddleButton || button === Qt.RightButton)
            rootItem.niri.closeFocusedWindow();
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
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

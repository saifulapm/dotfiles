import QtQuick
import "../components"
import "../../../components"

// Active XKB layout as omarchy renders it: first word, first three letters,
// uppercased, caption-sized. Hidden with a single layout. Click cycles.
BarButton {
    id: rootItem

    required property var niri

    readonly property string label: {
        const name = rootItem.niri.keyboardLayoutName;
        if (name === "")
            return "";
        return name.split(/\s+/)[0].substring(0, 3).toUpperCase();
    }

    visible: niri.keyboardLayouts.length > 1
    horizontalMargin: 6
    tooltipText: niri.keyboardLayoutName

    onTapped: rootItem.niri.switchKeyboardLayout()

    StyledText {
        theme: rootItem.theme
        role: StyledText.Small
        mono: true

        anchors.verticalCenter: parent.verticalCenter
        text: rootItem.label
        color: rootItem.contentColor
        renderType: Text.NativeRendering
    }
}

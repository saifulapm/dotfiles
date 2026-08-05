import QtQuick
import QtQuick.Effects

// One StatusNotifier item's icon. Quickshell already resolves the item into a
// ready-to-use image:// URL (including the "?path=" fallback search dir for
// apps that ship their tray icon outside a standard theme), so it goes
// straight to the Image — guessing a theme sub-directory here only breaks apps
// whose layout doesn't match the guess.
//
// Symbolic icons ship a fixed near-white fill that the host is meant to
// replace with its own foreground; they are detected by the freedesktop
// "-symbolic" name suffix and colorized, otherwise they vanish on a light
// theme. Ported from omarchy's Tray.qml TrayIcon (CREDITS.md).
Item {
    id: root

    property var icon: ""
    property color tint: "white"

    readonly property string iconSource: String(icon || "")
    readonly property string iconName: iconSource.split("?")[0]
    readonly property bool symbolic: iconName.endsWith("-symbolic")

    Image {
        id: image

        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        source: root.iconSource
        // Decode at physical pixels: the logical size leaves PNG icons
        // upscaled and blurry on HiDPI displays.
        sourceSize.width: Math.round(Math.min(root.width, root.height) * (Screen.devicePixelRatio || 1))
        sourceSize.height: Math.round(Math.min(root.width, root.height) * (Screen.devicePixelRatio || 1))
        // Symbolic icons are kept as a hidden layer so the effect below can
        // sample them as a texture.
        visible: !root.symbolic
        layer.enabled: root.symbolic
    }

    MultiEffect {
        anchors.fill: image
        source: image
        visible: root.symbolic
        colorization: 1.0
        colorizationColor: root.tint
    }
}

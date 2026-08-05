import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Wallpaper — omarchy's background plugin, simplified: one image per
// output on the background layer, path in ~/.local/state/qshell/background
// (written by bin/theme-set per theme, or by IPC `background set`).
// 420 ms crossfade between images via two stacked layers.
Scope {
    id: backgroundRoot

    required property var theme

    property string source: ""
    property string previousSource: ""

    function apply(path) {
        if (path === source)
            return;
        previousSource = source;
        source = path;
    }

    // Per-segment percent-encoding: a raw '#' or '?' in the path would parse
    // as URL fragment/query and truncate it (same treatment as
    // FilePickerModel.pathToUrl).
    function fileUrl(path) {
        return path ? "file://" + String(path).split("/").map(encodeURIComponent).join("/") : "";
    }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/qshell/background"
        watchChanges: true
        printErrors: false
        onLoaded: backgroundRoot.apply(text().trim())
        onFileChanged: reload()
        onLoadFailed: backgroundRoot.apply("")
    }

    IpcHandler {
        target: "background"

        function set(path: string): string {
            backgroundRoot.apply(path);
            return "ok";
        }

        function clear(): string {
            backgroundRoot.apply("");
            return "ok";
        }

        function current(): string {
            return backgroundRoot.source;
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: wall

            required property var modelData

            screen: modelData
            visible: backgroundRoot.source !== ""
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: backgroundRoot.theme.surface1
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "qshell-background"

            Image {
                id: oldImage
                anchors.fill: parent
                source: backgroundRoot.fileUrl(backgroundRoot.previousSource)
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true
            }

            Image {
                id: newImage
                anchors.fill: parent
                source: backgroundRoot.fileUrl(backgroundRoot.source)
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true

                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 420
                        easing.type: Easing.InOutCubic
                    }
                }
            }
        }
    }
}

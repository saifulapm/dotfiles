import Quickshell
import Quickshell.Wayland
import QtQuick
import "." as Root

// The one Overlay window every surface draws in; it stays mapped, since a remap costs 20 to 30 ms.
PanelWindow {
    id: host

    required property var theme
    required property var themeList
    readonly property var launcher: launcherLoader.item
    readonly property var themes: themesLoader.item
    readonly property bool shown: (launcher?.shown ?? false) || (themes?.shown ?? false)

    // t0 is taken before the first load, so a cold open's time includes loading.
    function openLauncher(t0) {
        themes?.close();
        launcherLoader.active = true;
        launcher.open(t0);
    }

    function openThemes(t0) {
        launcher?.close();
        themesLoader.active = true;
        themes.open(t0);
    }

    Connections {
        target: host.contentItem.Window.window
        function onFrameSwapped() {
            host.launcher?.swapped();
            host.themes?.swapped();
        }
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dots-surfaces"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    mask: shown ? null : noInput

    Region {
        id: noInput
    }

    Loader {
        id: launcherLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Launcher {
            theme: host.theme
        }
    }

    Loader {
        id: themesLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Themes {
            theme: host.theme
            themes: host.themeList
        }
    }
}

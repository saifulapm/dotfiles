import Quickshell
import Quickshell.Wayland
import QtQuick
import "." as Root

// The one Overlay window every surface draws in; it stays mapped, since a remap costs 20 to 30 ms.
PanelWindow {
    id: host

    required property var theme
    required property var themeList
    required property var notifs
    readonly property var launcher: launcherLoader.item
    readonly property var themes: themesLoader.item
    readonly property var notifications: notifsLoader.item
    readonly property bool shown: (launcher?.shown ?? false) || (themes?.shown ?? false) || (notifications?.shown ?? false)

    // t0 is taken before the first load, so a cold open's time includes loading.
    function openLauncher(t0) {
        themes?.close();
        notifications?.close();
        launcherLoader.active = true;
        launcher.open(t0);
    }

    function openThemes(t0) {
        launcher?.close();
        notifications?.close();
        themesLoader.active = true;
        themes.open(t0);
    }

    function openNotifs(t0) {
        launcher?.close();
        themes?.close();
        notifsLoader.active = true;
        notifications.open(t0);
    }

    Connections {
        target: host.contentItem.Window.window
        function onFrameSwapped() {
            host.launcher?.swapped();
            host.themes?.swapped();
            host.notifications?.swapped();
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

    Loader {
        id: notifsLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Notifications {
            theme: host.theme
            notifs: host.notifs
        }
    }
}

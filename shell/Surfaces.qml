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
    // The Desk's goals service, null until the Desk loads.
    required property var goals
    // The Desk's sync service, null until the Desk loads.
    required property var sync
    readonly property var launcher: launcherLoader.item
    readonly property var themes: themesLoader.item
    readonly property var notifications: notifsLoader.item
    readonly property var cheatsheet: cheatsheetLoader.item
    readonly property var control: controlLoader.item
    readonly property var recorder: recorderLoader.item
    readonly property var polkit: polkitLoader.item
    readonly property var goalsView: goalsLoader.item
    // Every surface that takes the keyboard while it shows; a recording carries on with its picker closed.
    readonly property var all: [launcher, themes, notifications, cheatsheet, control, recorder, polkit, goalsView]
    readonly property bool shown: all.some(s => s?.shown ?? false)

    // Only one surface shows at a time.
    function closeOthers(keep) {
        for (const s of all) {
            if (s && s !== keep)
                s.close();
        }
    }

    // t0 is taken before the first load, so a cold open's time includes loading.
    function openLauncher(t0, mode) {
        launcherLoader.active = true;
        closeOthers(launcher);
        launcher.open(t0, mode);
    }

    function openThemes(t0) {
        themesLoader.active = true;
        closeOthers(themes);
        themes.open(t0);
    }

    function openNotifs(t0) {
        notifsLoader.active = true;
        closeOthers(notifications);
        notifications.open(t0);
    }

    function openCheatsheet(t0) {
        cheatsheetLoader.active = true;
        closeOthers(cheatsheet);
        cheatsheet.open(t0);
    }

    function openControl(t0) {
        controlLoader.active = true;
        closeOthers(control);
        control.open(t0);
    }

    function openGoals(t0) {
        goalsLoader.active = true;
        closeOthers(goalsView);
        goalsView.open(t0);
    }

    function toggleRecorder() {
        recorderLoader.active = true;
        if (!recorder.shown && !recorder.recording)
            closeOthers(recorder);
        recorder.toggle();
    }

    // The polkit agent calls this when a request arrives.
    function openPolkit(flow) {
        polkitLoader.active = true;
        closeOthers(polkit);
        polkit.show(flow);
    }

    Connections {
        target: host.contentItem.Window.window
        function onFrameSwapped() {
            for (const s of host.all)
                s?.swapped();
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

    Loader {
        id: cheatsheetLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.CheatSheet {
            theme: host.theme
        }
    }

    Loader {
        id: controlLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Control {
            theme: host.theme
            notifs: host.notifs
            sync: host.sync
        }
    }

    Loader {
        id: recorderLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Recorder {
            theme: host.theme
            screen: host.screen
        }
    }

    Loader {
        id: polkitLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.PolkitPrompt {
            theme: host.theme
        }
    }

    Loader {
        id: goalsLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Goals {
            theme: host.theme
            goals: host.goals
        }
    }
}

import Quickshell
import Quickshell.Wayland
import QtQuick
import "." as Root

// The one Overlay window every surface draws in; it stays mapped, since a remap costs 20 to 30 ms.
PanelWindow {
    id: host

    required property var theme
    required property var themeList
    // The desktop entries with their icons, scanned by the shell after its first frame.
    required property var apps
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
    readonly property var pinentry: pinentryLoader.item
    readonly property var pass: passLoader.item
    // Every surface that takes the keyboard while it shows; a recording carries on with its picker closed.
    readonly property var all: [launcher, themes, notifications, cheatsheet, control, recorder, polkit, goalsView, pinentry, pass]
    readonly property bool shown: all.some(s => s?.shown ?? false)

    // Only one surface shows at a time, so another's close is cut short.
    function closeOthers(keep) {
        for (const s of all) {
            if (s && s !== keep) {
                s.close();
                s.motion?.cut();
            }
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

    function openPass(t0) {
        passLoader.active = true;
        closeOthers(pass);
        pass.open(t0);
    }

    // The Pinentry service calls this with each gpg request it shows.
    function openPinentry(request) {
        pinentryLoader.active = true;
        closeOthers(pinentry);
        pinentry.show(request);
    }

    // Each surface is made in turn, one per tick, so none holds a frame long and a first open finds it built; Goals waits for the Desk's store.
    function warm() {
        warmTick.start();
    }

    Root.Tick {
        id: warmTick
        interval: 50
        repeat: true
        onTriggered: {
            const next = [launcherLoader, themesLoader, notifsLoader, cheatsheetLoader, controlLoader, recorderLoader, polkitLoader, goalsLoader].find(l => !l.active && (l !== goalsLoader || host.goals));
            if (next)
                next.active = true;
            else
                stop();
        }
    }

    Connections {
        target: host.contentItem.Window.window
        function onFrameSwapped() {
            for (const s of host.all) {
                s?.swapped();
                s?.motion?.swapped();
            }
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
            apps: host.apps
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

    // The newer surfaces load on their first open and never warm; each unloads once it has drawn nothing for 30 s.
    Loader {
        id: pinentryLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.PinentryPrompt {
            theme: host.theme
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.pinentry && !host.pinentry.visible
        onTriggered: pinentryLoader.active = false
    }

    Loader {
        id: passLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Pass {
            theme: host.theme
        }
    }

    // Pass comes back only when nothing else has taken its place.
    Connections {
        target: host.pass
        function onReopenWanted() {
            if (!host.shown)
                host.pass.reopen();
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.pass && !host.pass.visible && !host.pass.busy
        onTriggered: passLoader.active = false
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

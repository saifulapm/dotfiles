import Quickshell
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/click.mjs" as ClickLib
import "lib/launcher.mjs" as Lib
import "lib/voice.mjs" as V

// The one Overlay window every surface draws in; it stays mapped, since a remap costs 20 to 30 ms.
PanelWindow {
    id: host

    // niri closes a layer surface made while it has no output, and Quickshell never makes another, so a monitor that drops and comes back (the mini's, on unlock) left every panel drawing nowhere; hiding and showing the window on any change of screens makes a new surface.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            host.visible = false;
            Qt.callLater(() => host.visible = true);
        }
    }

    required property var theme
    required property var themeList
    // Every panel floats over the desk as a floating window does, so it reads the theme as the desk's apps do: its words moved to read there, its fills veils, its card the paper inside the accent edge.
    readonly property QtObject panelTheme: QtObject {
        readonly property var tokens: V.deskTokens(host.theme.tokens)
        readonly property var color: tokens ? tokens.color : host.theme.color
        readonly property string dir: host.theme.dir
        readonly property string name: host.theme.name
        // A panel's notice reaches the island through the real theme, which carries the signal.
        function notice(text) {
            host.theme.notice(text);
        }
    }
    // The desktop entries with their icons, scanned by the shell after its first frame.
    required property var apps
    required property var notifs
    // The Desk's goals service, null until the Desk loads.
    required property var goals
    // The Desk's sync service, null until the Desk loads.
    required property var sync
    // The Desk's reminders service, null until the Desk loads.
    required property var reminders
    // The Desk's niri service, null until the Desk loads.
    required property var niri
    // The Desk's island, which draws in this window; null until the Desk loads.
    required property var island
    readonly property var launcher: launcherLoader.item
    readonly property var notifications: notifsLoader.item
    readonly property var cheatsheet: cheatsheetLoader.item
    readonly property var control: controlLoader.item
    readonly property var recorder: recorderLoader.item
    readonly property var polkit: polkitLoader.item
    readonly property var goalsView: goalsLoader.item
    readonly property var pinentry: pinentryLoader.item
    readonly property var pass: passLoader.item
    readonly property var tailscale: tailscaleLoader.item
    readonly property var accounts: accountsLoader.item
    readonly property var dns: dnsLoader.item
    readonly property var picker: pickerLoader.item
    // Every surface that takes the keyboard while it shows; a recording carries on with its picker closed.
    readonly property var all: [launcher, notifications, cheatsheet, control, recorder, polkit, goalsView, pinentry, pass, tailscale, accounts, dns, picker]
    readonly property bool shown: all.some(s => s?.shown ?? false)
    // While niri's overview is open the shell holds the keyboard, so no key reaches the window behind it.
    readonly property bool overview: niri?.overview ?? false
    // A launcher opened by a key typed in the overview closes with it, however the overview closes.
    property bool launcherFromOverview: false

    onOverviewChanged: {
        if (!overview && launcherFromOverview)
            launcher.close();
        catchKeys();
    }
    // One thing holds the island at a time, so a surface that opens takes the keyboard from the island, unless the island opened it for an attachment.
    onShownChanged: {
        if (shown && !(island?.attaching ?? false))
            island?.release();
        catchKeys();
    }

    function catchKeys() {
        if (overview && !shown)
            overviewKeys.forceActiveFocus();
    }

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
    function openLauncher(t0, mode, typed) {
        launcherFromOverview = !!typed;
        launcherLoader.active = true;
        closeOthers(launcher);
        launcher.open(t0, mode, typed);
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

    function openTailscale(t0) {
        tailscaleLoader.active = true;
        closeOthers(tailscale);
        tailscale.open(t0);
    }

    function openAccounts(t0) {
        accountsLoader.active = true;
        closeOthers(accounts);
        accounts.open(t0);
    }

    function openDns(t0) {
        dnsLoader.active = true;
        closeOthers(dns);
        dns.open(t0);
    }

    // The Pinentry service calls this with each gpg request it shows.
    function openPinentry(request) {
        pinentryLoader.active = true;
        closeOthers(pinentry);
        pinentry.show(request);
    }

    // The Portal service calls this with each file chooser request it shows.
    function openPicker(request) {
        pickerLoader.active = true;
        closeOthers(picker);
        picker.show(request);
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
            const next = [launcherLoader, notifsLoader, cheatsheetLoader, controlLoader, recorderLoader, polkitLoader, goalsLoader].find(l => !l.active && (l !== goalsLoader || host.goals));
            if (next)
                next.active = true;
            else
                stop();
        }
    }

    Connections {
        target: host.contentItem.Window.window
        function onBeforeSynchronizing() {
            if (host.island)
                host.island.syncedAt = Date.now();
        }
        function onAfterRendering() {
            if (host.island)
                host.island.renderedAt = Date.now();
        }
        function onFrameSwapped() {
            host.island?.swapped();
            for (const s of host.all) {
                s?.swapped();
                s?.motion?.swapped();
            }
        }
    }

    // The window follows niri's focused output (N0107CYM), as the island in it does.
    readonly property var output: Quickshell.screens.find(s => s.name === niri?.focusedOutput) ?? Quickshell.screens[0]
    screen: output
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dots-surfaces"
    WlrLayershell.keyboardFocus: shown || overview || (island?.wantsKeys ?? false) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    // A drag out of the notification centre must reach the window under it, which this full-output layer would otherwise cover; at rest only the island takes clicks, and after Mod+I the whole output does, so a click outside gives the keyboard back (SMB51G7B).
    mask: shown && !(notifications?.dragging ?? false) ? null : island?.wantsKeys && !island.noteDragging ? null : island?.visible ? islandInput : noInput

    Region {
        id: noInput
    }

    Region {
        id: islandInput
        item: host.island ? host.island.maskItem : null
    }

    // Holds focus while the overview is open and no surface shows; a printable key opens the launcher with it typed, and Esc or Enter closes the overview on the window it shows focused.
    Item {
        id: overviewKeys
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                Quickshell.execDetached(["niri", "msg", "action", "close-overview"]);
                event.accepted = true;
                return;
            }
            const typed = Lib.overviewChar(event.text, {
                ctrl: event.modifiers & Qt.ControlModifier,
                alt: event.modifiers & Qt.AltModifier,
                meta: event.modifiers & Qt.MetaModifier
            });
            if (typed)
                host.openLauncher(Date.now(), null, typed);
            event.accepted = true;
        }
    }

    // Under every surface, so it takes only the presses nothing drawn above it takes: one outside the shown card closes that surface as Escape does, and focus goes back to the window that had it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: mouse => {
            const s = host.all.find(s => s?.shown);
            // After Mod+I a press of any button outside the island gives the keyboard back and goes no further; one on it is the island's.
            if (!s && host.island?.wantsKeys) {
                const box = host.island.maskItem;
                if (box.contains(mapToItem(box, mouse.x, mouse.y)))
                    mouse.accepted = false;
                else
                    host.island.release();
                return;
            }
            if (mouse.button !== Qt.LeftButton) {
                mouse.accepted = false;
                return;
            }
            // A surface in the island is drawn inside it, so the press is read in the surface's own coordinates.
            const at = s ? mapToItem(s, mouse.x, mouse.y) : null;
            if (!s || ClickLib.onCard(s, at.x, at.y))
                mouse.accepted = false;
            else if (s.stepBack)
                s.stepBack();
            else
                s.close();
        }
        // A wheel turned outside the island after Mod+I gives the keyboard back too.
        onWheel: wheel => {
            if (!host.all.some(s => s?.shown) && host.island?.wantsKeys)
                host.island.release();
            wheel.accepted = false;
        }
    }

    Loader {
        id: launcherLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Launcher {
            theme: panelTheme
            apps: host.apps
            schemes: host.themeList
            reminders: host.reminders
            // A launch or a picked window from the overview closes it too; Esc returns to it.
            onLaunched: {
                if (host.overview)
                    Quickshell.execDetached(["niri", "msg", "action", "close-overview"]);
            }
        }
    }

    Loader {
        id: notifsLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Notifications {
            theme: panelTheme
            notifs: host.notifs
        }
    }

    // The cheat sheet draws inside the island, on the island's fill, so it reads the scheme's own tokens.
    Loader {
        id: cheatsheetLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        active: false
        sourceComponent: Root.CheatSheet {
            theme: host.theme
        }
    }

    // The surfaces that draw inside the island, and the one of them shown, or null.
    readonly property var islandSurfaces: [cheatsheet]
    readonly property var islandSurface: islandSurfaces.find(s => s?.shown) ?? null
    // The last of them shown keeps its size while the island closes, so its content does not collapse mid-morph.
    property var islandLast: null
    onIslandSurfaceChanged: if (islandSurface)
        islandLast = islandSurface

    // While a card is open, a click on the island is a click outside that card, so the island takes no input.
    Binding {
        when: !!host.island
        target: host.island
        property: "cardOpen"
        value: host.shown && !host.islandSurface
    }

    Binding {
        when: !!host.island
        target: host.island
        property: "surface"
        value: host.islandSurface?.name ?? null
    }

    Binding {
        when: !!host.island && !!host.islandLast
        target: host.island
        property: "surfaceWidth"
        value: host.islandLast?.wantWidth ?? 0
    }

    Binding {
        when: !!host.island && !!host.islandLast
        target: host.island
        property: "surfaceHeight"
        value: host.islandLast?.implicitHeight ?? 0
    }

    Binding {
        when: !!host.island && !!host.islandLast
        target: host.island
        property: "surfaceBusy"
        value: host.islandLast?.busy ?? false
    }

    Connections {
        target: host.island
        function onSurfaceYielded() {
            host.islandSurface?.close();
        }
    }

    Loader {
        id: controlLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Control {
            theme: panelTheme
            notifs: host.notifs
            sync: host.sync
        }
    }

    Loader {
        id: recorderLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Recorder {
            theme: panelTheme
            screen: host.screen
        }
    }

    Loader {
        id: polkitLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.PolkitPrompt {
            theme: panelTheme
        }
    }

    // The newer surfaces load on their first open and never warm; each unloads once it has drawn nothing for 30 s.
    Loader {
        id: pinentryLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.PinentryPrompt {
            theme: panelTheme
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
            theme: panelTheme
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
        id: tailscaleLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Tailscale {
            theme: panelTheme
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.tailscale && !host.tailscale.visible && !host.tailscale.busy
        onTriggered: tailscaleLoader.active = false
    }

    Loader {
        id: accountsLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Accounts {
            theme: panelTheme
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.accounts && !host.accounts.visible && !host.accounts.busy
        onTriggered: accountsLoader.active = false
    }

    Loader {
        id: dnsLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Dns {
            theme: panelTheme
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.dns && !host.dns.visible && !host.dns.busy
        onTriggered: dnsLoader.active = false
    }

    Loader {
        id: pickerLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.FilePicker {
            theme: panelTheme
            apps: host.apps
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.picker && !host.picker.visible && !host.picker.busy
        onTriggered: pickerLoader.active = false
    }

    Loader {
        id: goalsLoader
        anchors.fill: parent
        active: false
        sourceComponent: Root.Goals {
            theme: panelTheme
            goals: host.goals
        }
    }
}

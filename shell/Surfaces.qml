import Quickshell
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/click.mjs" as ClickLib
import "lib/launcher.mjs" as Lib
import "lib/takeover.mjs" as T

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
    readonly property var pairing: pairingLoader.item
    readonly property var chat: chatLoader.item
    // Every surface that takes the keyboard while it shows; a recording carries on with its picker closed.
    readonly property var all: [launcher, notifications, cheatsheet, control, recorder, polkit, pairing, goalsView, pinentry, pass, tailscale, accounts, dns, picker, chat]
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

    // t0 is taken before the first load, so a cold open's time includes loading. A surface in the island opens before the other closes, so the island goes straight from one to the other and never reads null between.
    function openLauncher(t0, mode, typed) {
        if (host.takeoverItem)
            return;
        launcherFromOverview = !!typed;
        launcherLoader.active = true;
        launcher.open(t0, mode, typed);
        closeOthers(launcher);
    }

    function openNotifs(t0) {
        if (host.takeoverItem)
            return;
        notifsLoader.active = true;
        notifications.open(t0);
        closeOthers(notifications);
    }

    function openCheatsheet(t0) {
        if (host.takeoverItem)
            return;
        cheatsheetLoader.active = true;
        cheatsheet.open(t0);
        closeOthers(cheatsheet);
    }

    function openControl(t0) {
        if (host.takeoverItem)
            return;
        controlLoader.active = true;
        control.open(t0);
        closeOthers(control);
    }

    function openGoals(t0) {
        if (host.takeoverItem)
            return;
        goalsLoader.active = true;
        goalsView.open(t0);
        closeOthers(goalsView);
    }

    function toggleRecorder() {
        if (host.takeoverItem && !(recorder?.recording ?? false))
            return;
        recorderLoader.active = true;
        if (!recorder.shown && !recorder.recording)
            closeOthers(recorder);
        recorder.toggle();
    }

    // The polkit agent calls this when a request arrives; it takes the island over whatever shows (7E95CSV2).
    function openPolkit(flow) {
        polkitLoader.active = true;
        takeOver(polkit);
        polkit.show(flow);
    }

    // Pairing shows bin/dots-bt-agent's requests one at a time; each takes the island over whatever shows, Control's Bluetooth page included.
    function openPairing() {
        pairingLoader.active = true;
        takeOver(pairing);
        pairing.show();
    }

    Connections {
        target: Root.Pairing
        function onCurrentChanged() {
            if (Root.Pairing.current)
                host.openPairing();
        }
    }

    // The prompts that take the island over the surface in it and hand it back once answered, cancelled or hung up; each loads in the island's surface slot.
    readonly property var takeovers: [polkit, pinentry, pairing, picker]
    // Their names as they showed, oldest first, and the item each took the keyboard from.
    property var stack: []
    property var focusUnder: ({})
    readonly property var takeoverItem: takeovers.find(t => t && t.name === stack[stack.length - 1]) ?? null
    // What the island draws: the newest prompt, else the open surface.
    readonly property var drawnSurface: takeoverItem ?? islandSurface

    // Called just before a prompt shows: it goes on top of the stack, and the item that had the keyboard is kept for its return.
    function takeOver(p) {
        if (stack.indexOf(p.name) < 0)
            focusUnder = Object.assign({}, focusUnder, { [p.name]: host.contentItem.Window.activeFocusItem });
        stack = T.push(stack, p.name);
    }

    // A prompt that left hands the keyboard back to what it covered; one that left from under another passes what it covered to the one above it.
    function handBack(p) {
        const at = stack.indexOf(p.name);
        if (at < 0)
            return;
        const under = Object.assign({}, focusUnder);
        const was = under[p.name];
        delete under[p.name];
        if (at < stack.length - 1)
            under[stack[at + 1]] = was;
        focusUnder = under;
        stack = T.drop(stack, p.name);
        if (at === stack.length && was)
            was.forceActiveFocus();
    }

    Binding {
        when: !!host.island
        target: host.island
        property: "takeover"
        value: host.takeoverItem?.name ?? null
    }

    // A prompt's chip names what it returns to: the prompt before it, else the surface; nothing over the resting island.
    function chipFor(name) {
        return T.chipText(T.under(islandSurface?.name ?? null, stack.slice(0, stack.indexOf(name) + 1)));
    }

    // True once the island has come to rest on that prompt, so a check can read its pixels.
    function settledOn(name) {
        return island?.takeover === name && !(island?.animating ?? true);
    }

    function openPass(t0) {
        if (host.takeoverItem)
            return;
        passLoader.active = true;
        pass.open(t0);
        closeOthers(pass);
    }

    function openTailscale(t0) {
        if (host.takeoverItem)
            return;
        tailscaleLoader.active = true;
        tailscale.open(t0);
        closeOthers(tailscale);
    }

    function openAccounts(t0) {
        if (host.takeoverItem)
            return;
        accountsLoader.active = true;
        accounts.open(t0);
        closeOthers(accounts);
    }

    function openChat(t0) {
        if (host.takeoverItem)
            return;
        chatLoader.active = true;
        chat.open(t0);
        closeOthers(chat);
    }

    // The launcher's "? " question opens the chat and sends it there.
    function askChat(text) {
        openChat(Date.now());
        chat?.askFrom(text);
    }

    function openDns(t0) {
        if (host.takeoverItem)
            return;
        dnsLoader.active = true;
        dns.open(t0);
        closeOthers(dns);
    }

    // The Pinentry service calls this with each gpg request it shows; the prompt takes the island over whatever shows, as polkit's does, and Pass stays open under it.
    function openPinentry(request) {
        pinentryLoader.active = true;
        takeOver(pinentry);
        pass?.covered();
        pinentry.show(request);
    }

    // The Portal service calls this with each file chooser request it shows; it takes the island over whatever shows (7E95CSV2).
    function openPicker(request) {
        pickerLoader.active = true;
        takeOver(picker);
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
            const next = [launcherLoader, notifsLoader, cheatsheetLoader, controlLoader, recorderLoader, goalsLoader].find(l => !l.active && (l !== goalsLoader || host.goals));
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

    // Where the window takes input, for checks: the whole output, the island alone, or nowhere.
    readonly property string inputKind: mask === null ? "output" : mask === islandInput ? "island" : "none"

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
            const s = host.takeoverItem ?? host.all.find(s => s?.shown);
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

    // The launcher draws inside the island, on the island's fill, so it reads the scheme's own tokens; it shows while it is the island's surface, or the last one through its close.
    Loader {
        id: launcherLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.launcher
        active: false
        sourceComponent: Root.Launcher {
            theme: host.theme
            apps: host.apps
            schemes: host.themeList
            reminders: host.reminders
            onChatWanted: text => host.askChat(text)
            // A launch or a picked window from the overview closes it too; Esc returns to it.
            onLaunched: {
                if (host.overview)
                    Quickshell.execDetached(["niri", "msg", "action", "close-overview"]);
            }
        }
    }

    // The notification centre draws inside the island, on the island's fill, so it reads the scheme's own tokens.
    Loader {
        id: notifsLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.notifications
        active: false
        sourceComponent: Root.Notifications {
            theme: host.theme
            notifs: host.notifs
        }
    }

    Binding {
        target: host.notifs
        property: "seen"
        value: host.notifications?.shown ?? false
    }

    // A check waits on this before it reads the centre's pixels.
    Binding {
        when: !!host.notifications && !!host.island
        target: host.notifications
        property: "settled"
        value: host.island?.surface === "notifs" && !(host.island?.animating ?? true)
    }

    // The cheat sheet draws inside the island, on the island's fill, so it reads the scheme's own tokens.
    Loader {
        id: cheatsheetLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.cheatsheet
        active: false
        sourceComponent: Root.CheatSheet {
            theme: host.theme
        }
    }

    // The surfaces that draw inside the island, and the one of them shown, or null.
    readonly property var islandSurfaces: [launcher, notifications, cheatsheet, control, recorder, pass, tailscale, accounts, dns, goalsView, chat]
    readonly property var islandSurface: islandSurfaces.find(s => s?.shown) ?? null
    // The last thing the island drew, a surface or a prompt, keeps its size while the island closes, so its content does not collapse mid-morph.
    property var islandLast: null
    onDrawnSurfaceChanged: if (drawnSurface)
        islandLast = drawnSurface

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

    // A check waits on this before it reads the launcher's pixels.
    Binding {
        when: !!host.launcher && !!host.island
        target: host.launcher
        property: "settled"
        value: host.island?.surface === "launcher" && !(host.island?.animating ?? true)
    }

    // Control draws inside the island, on the island's fill, so it reads the scheme's own tokens.
    Loader {
        id: controlLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.control
        active: false
        sourceComponent: Root.Control {
            theme: host.theme
            notifs: host.notifs
            sync: host.sync
            clock: host.island ? host.island.clock : null
            onRecordWanted: host.toggleRecorder()
            // The calendar opens from the resting island, so it waits for Control's close to reach it.
            onCalendarWanted: Qt.callLater(() => host.island?.openCalendar())
        }
    }

    // The resting clock glides into Control's big clock, which hides while the glide draws it.
    Binding {
        when: !!host.island
        target: host.island
        property: "clockTarget"
        value: host.control?.clockItem ?? null
    }

    Binding {
        when: !!host.control && !!host.island
        target: host.control
        property: "clockHidden"
        value: host.island?.clockGlide ?? false
    }

    // A check waits on this before it reads Control's pixels.
    Binding {
        when: !!host.control && !!host.island
        target: host.control
        property: "settled"
        value: host.island?.surface === "control" && !(host.island?.animating ?? true)
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

    // The Recorder's bar draws inside the island, on the island's fill, so it reads the scheme's own tokens; its dim stays over the whole output.
    Loader {
        id: recorderBarLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.recorder
        // Made only while the bar is the island's, so it costs nothing at rest.
        active: !!host.recorder && host.islandLast === host.recorder
        sourceComponent: Root.RecorderBar {
            recorder: host.recorder
            theme: host.theme
        }
    }

    Binding {
        when: !!host.recorder
        target: host.recorder
        property: "bar"
        value: recorderBarLoader.item
    }

    // The polkit prompt draws inside the island, on the island's fill, over the surface it covers (board 7).
    Loader {
        id: polkitLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.polkit
        active: false
        sourceComponent: Root.PolkitPrompt {
            theme: host.theme
            chip: host.chipFor(name)
            settled: host.settledOn(name)
            onShownChanged: if (!shown)
                host.handBack(host.polkit)
        }
    }

    // Built on its first request rather than warmed, so the island card costs no idle memory; it unloads 30 s after it hands the island back.
    Root.Tick {
        interval: 30000
        running: !!host.polkit && !host.polkit.shown
        onTriggered: polkitLoader.active = false
    }

    // The pairing prompt draws inside the island the same way, over the surface it covers (board 7).
    Loader {
        id: pairingLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.pairing
        active: false
        sourceComponent: Root.PairingPrompt {
            theme: host.theme
            chip: host.chipFor(name)
            settled: host.settledOn(name)
            onShownChanged: if (!shown)
                host.handBack(host.pairing)
        }
    }

    // The gpg prompt draws inside the island like polkit's; it loads on its first request and unloads 30 s after it hands the island back.
    Loader {
        id: pinentryLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.pinentry
        active: false
        sourceComponent: Root.PinentryPrompt {
            theme: host.theme
            chip: host.chipFor(name)
            settled: host.settledOn(name)
            onShownChanged: if (!shown)
                host.handBack(host.pinentry)
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.pinentry && !host.pinentry.shown
        onTriggered: pinentryLoader.active = false
    }

    // Pass, Tailscale, Accounts and DNS draw inside the island, on the island's fill, so they read the scheme's own tokens (board 8); each loads on its first open and unloads 30 s after its close.
    Loader {
        id: passLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.pass
        active: false
        sourceComponent: Root.Pass {
            theme: host.theme
        }
    }

    // A surface in the island stays the island's last through its close, so its unload waits on its own close, not on what is drawn.
    Root.Tick {
        interval: 30000
        running: !!host.pass && !host.pass.shown && !host.pass.busy
        onTriggered: passLoader.active = false
    }

    Loader {
        id: tailscaleLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.tailscale
        active: false
        sourceComponent: Root.Tailscale {
            theme: host.theme
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.tailscale && !host.tailscale.shown && !host.tailscale.busy
        onTriggered: tailscaleLoader.active = false
    }

    Loader {
        id: accountsLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.accounts
        active: false
        sourceComponent: Root.Accounts {
            theme: host.theme
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.accounts && !host.accounts.shown && !host.accounts.busy
        onTriggered: accountsLoader.active = false
    }

    Loader {
        id: dnsLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.dns
        active: false
        sourceComponent: Root.Dns {
            theme: host.theme
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.dns && !host.dns.shown && !host.dns.busy
        onTriggered: dnsLoader.active = false
    }

    // The chat loads on its first open and unloads 30 s after its close, once no reply streams.
    Loader {
        id: chatLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.chat
        active: false
        sourceComponent: Root.Chat {
            theme: host.theme
        }
    }

    Root.Tick {
        interval: 30000
        running: !!host.chat && !host.chat.shown && !host.chat.held
        onTriggered: chatLoader.active = false
    }

    // A closed chat still streaming, or holding a reply not yet seen, waits behind the island's dot until it opens again.
    Binding {
        when: !!host.island
        target: host.island
        property: "chatWaiting"
        value: !!host.chat && !host.chat.shown && host.chat.held
    }

    // A check waits on these before it reads a tool's pixels.
    Binding {
        when: !!host.chat && !!host.island
        target: host.chat
        property: "settled"
        value: host.island?.surface === "chat" && !(host.island?.animating ?? true)
    }

    Binding {
        when: !!host.pass && !!host.island
        target: host.pass
        property: "settled"
        value: host.island?.surface === "pass" && !(host.island?.animating ?? true)
    }

    Binding {
        when: !!host.tailscale && !!host.island
        target: host.tailscale
        property: "settled"
        value: host.island?.surface === "tailscale" && !(host.island?.animating ?? true)
    }

    Binding {
        when: !!host.accounts && !!host.island
        target: host.accounts
        property: "settled"
        value: host.island?.surface === "accounts" && !(host.island?.animating ?? true)
    }

    Binding {
        when: !!host.dns && !!host.island
        target: host.dns
        property: "settled"
        value: host.island?.surface === "dns" && !(host.island?.animating ?? true)
    }

    Binding {
        when: !!host.goalsView && !!host.island
        target: host.goalsView
        property: "settled"
        value: host.island?.surface === "goals" && !(host.island?.animating ?? true)
    }

    // The file picker draws inside the island, on the island's fill, over the surface it covers (board 9).
    Loader {
        id: pickerLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.picker
        active: false
        sourceComponent: Root.FilePicker {
            theme: host.theme
            apps: host.apps
            chip: host.chipFor(name)
            settled: host.settledOn(name)
            onShownChanged: if (!shown)
                host.handBack(host.picker)
        }
    }

    // The picker unloads 30 s after its last request closes; like Pass, it waits on its own close, not on what the island draws, since the island keeps its last surface drawn.
    Root.Tick {
        interval: 30000
        running: !!host.picker && !host.picker.shown && !host.picker.pending
        onTriggered: pickerLoader.active = false
    }

    // Goals draws inside the island too; it warms with the rest once the Desk's store is there, and stays.
    Loader {
        id: goalsLoader
        parent: host.island ? host.island.surfaceSlot : host.contentItem
        anchors.fill: parent
        visible: host.islandLast === host.goalsView
        active: false
        sourceComponent: Root.Goals {
            theme: host.theme
            goals: host.goals
        }
    }
}

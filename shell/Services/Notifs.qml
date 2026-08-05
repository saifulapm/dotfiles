import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../Modules/Notifications/NotificationLogic.js" as Logic

// Notification service — the one deliberate exception to lazy loading: the
// server must own org.freedesktop.Notifications from startup or apps cannot
// deliver notifications at all. The popup UI stays lazy (see shell.qml);
// this object is a bus registration, three models, and the persistence and
// IPC around them.
//
// Ported from omarchy's notifications plugin Service.qml (CREDITS.md): the
// three-model split, the urgency timeout policy, replace-by-id, the DND
// bypass rules, expire-vs-dismiss, the history file and its debounced write,
// the /tmp image cache, and the IPC surface. Click-to-focus is ours — they
// shell out to a Hyprland helper, we resolve the sender against niri's own
// window list and fire one FocusWindow action.
QtObject {
    id: root

    // Services/Niri.qml, injected by shell.qml — click-to-focus needs its
    // window map. Focus is simply a no-op when it is absent.
    property var niri: null

    readonly property string home: Quickshell.env("HOME")
    // History and DND are persistent user state, not regeneratable cache, so
    // they live under XDG_STATE_HOME beside stay-awake / nightlight / reminders.
    readonly property string stateDir: home + "/.local/state/qshell/"
    readonly property string historyPath: stateDir + "notifications.json"
    // Thumbnails copied out of /tmp are genuinely disposable — if they vanish
    // the row just renders without an image — so they stay in ~/.cache.
    readonly property string imageCacheDir: home + "/.cache/qshell/notification-images/"

    // Flips true on the first popup and stays true — gates the popup window
    // Loader in shell.qml so no UI exists until something actually arrives.
    property bool everNotified: false

    // Do not disturb. Written straight through to notifications.json by the
    // same debounced save the history uses, and hydrated back on startup, so
    // it survives a shell restart. Deliberately NOT PersistentProperties:
    // that only spans in-process QML reloads, and the state file we already
    // need for history spans those too (a reload re-reads it) as well as a
    // real restart. Matches how stay-awake and nightlight persist.
    property bool dnd: false
    // Guards the write-back while hydrating from disk.
    property bool hydrating: false
    onDndChanged: {
        if (!hydrating)
            scheduleHistorySave();
    }

    function setDnd(value) {
        dnd = !!value;
    }

    function toggleDnd() {
        dnd = !dnd;
    }

    // popupModel  — the on-screen toast stack.
    // pendingModel — received but not yet seen by the user. Anything DND
    //                suppresses lands here and stays until reviewed; anything
    //                that pops up also lives here until its toast goes away.
    // pastModel   — already seen on screen, kept for a short replay window.
    readonly property ListModel popupModel: ListModel {}
    readonly property ListModel pendingModel: ListModel {}
    readonly property ListModel pastModel: ListModel {}

    readonly property int historyCap: 100
    readonly property int historyReplayLimit: 5
    // Past is a rolling "recently" window, swept once a minute.
    readonly property int pastTtlMs: 15 * 60 * 1000

    readonly property int lowPopupDuration: 5000
    readonly property int normalPopupDuration: 8000
    readonly property int maxPopupDuration: 30000

    // Live Notification objects by originalId, kept OUT of the ListModels: a
    // QObject stored in a model role becomes a dangling C++ pointer once the
    // server destroys the notification, and the next read of that role
    // crashes. A JS map only holds a wrapper, which degrades to a catchable
    // error instead.
    property var liveRefs: ({})
    property var imageCacheQueue: []
    property bool historyLoaded: false

    // ------------------------------------------------------- timeout policy
    // Critical never expires on its own. Everything else takes the sender's
    // requested timeout, floored at the per-urgency minimum and capped at 30s.
    function durationFor(urgency, expireTimeout) {
        switch (urgency) {
        case NotificationUrgency.Critical:
            return 0;
        case NotificationUrgency.Low:
            return Math.min(maxPopupDuration, Math.max(lowPopupDuration, requestedDuration(expireTimeout)));
        default:
            return Math.min(maxPopupDuration, Math.max(normalPopupDuration, requestedDuration(expireTimeout)));
        }
    }

    function requestedDuration(expireTimeout) {
        // The freedesktop spec (and Quickshell) report expireTimeout in
        // milliseconds, so pass it through directly.
        const ms = Number(expireTimeout || 0);
        if (!isFinite(ms) || ms <= 0)
            return 0;
        return Math.round(ms);
    }

    function shouldBypassDnd(notification) {
        return Logic.shouldBypassDnd(notification, NotificationUrgency.Critical);
    }

    function snapshotOf(notification) {
        return Logic.snapshotOf(notification, Date.now());
    }

    // --------------------------------------------------------- ingress
    function handleNotification(notification) {
        // Without `tracked = true` the Notification object is destroyed as
        // soon as this handler returns, which would null out the ref the card
        // needs for actions and click-to-focus.
        notification.tracked = true;
        const snapshot = snapshotOf(notification);
        const originalId = snapshot.originalId;
        liveRefs[originalId] = notification;
        // Guard the delete: a newer notification may have reused this id
        // (freedesktop replaces_id) and taken over the map slot.
        notification.closed.connect(function () {
            if (root.liveRefs[originalId] === notification)
                delete root.liveRefs[originalId];
        });

        // replaces_id: Quickshell answers a replacement by mutating the
        // existing Notification in place and does NOT re-emit `notification`
        // (verified in its server.cpp), so a model row snapshotted at arrival
        // would keep the original text forever — which is exactly what
        // upstream's remove-then-insert never gets to fix. Watch the object's
        // own change signals and route the replacement through the same
        // ingress path, so an updated notification refreshes its row, returns
        // to the top of the stack, and restarts its countdown.
        const onChanged = function () {
            root.scheduleLiveRefresh(notification, originalId);
        };
        notification.summaryChanged.connect(onChanged);
        notification.bodyChanged.connect(onChanged);
        notification.appNameChanged.connect(onChanged);
        notification.appIconChanged.connect(onChanged);
        notification.imageChanged.connect(onChanged);
        notification.urgencyChanged.connect(onChanged);
        notification.expireTimeoutChanged.connect(onChanged);
        notification.actionsChanged.connect(onChanged);
        notification.hintsChanged.connect(onChanged);

        routeNotification(notification, snapshot);
    }

    // One update per replacement, however many property signals it fired.
    property var refreshQueued: ({})

    function scheduleLiveRefresh(notification, originalId) {
        if (refreshQueued[originalId])
            return;
        refreshQueued[originalId] = true;
        Qt.callLater(function () {
            delete root.refreshQueued[originalId];
            // A newer notification may own this id by now, or the server may
            // have torn this one down.
            if (root.liveRefs[originalId] !== notification)
                return;
            root.routeNotification(notification, root.snapshotOf(notification));
        });
    }

    // Decide where an arriving (or replaced) notification goes: history
    // bucket, toast, both, or neither under DND.
    function routeNotification(notification, snapshot) {
        // History is for notifications from real apps — things worth looking
        // back at. Skip the pending/past bookkeeping when the freedesktop
        // `transient` hint is set, or the sender is one of the ephemeral
        // identities (see NotificationLogic.isEphemeralApp).
        let transient = false;
        try {
            transient = !!(notification.hints && notification.hints["transient"]);
        } catch (e) {
            transient = false;
        }
        const ephemeral = Logic.isEphemeralApp(String(notification.appName || ""));
        if (transient || ephemeral) {
            if (dnd && !shouldBypassDnd(notification)) {
                delete liveRefs[snapshot.originalId];
                notification.tracked = false;
                return;
            }
            pushPopup(snapshot);
            return;
        }

        // Pending first, unconditionally. DND only suppresses the toast — the
        // record still has to land somewhere the user can review later.
        addToPending(snapshot);
        maybeCacheImage(snapshot);

        if (dnd && !shouldBypassDnd(notification)) {
            delete liveRefs[snapshot.originalId];
            notification.tracked = false;
            return;
        }

        pushPopup(snapshot);
    }

    function pushPopup(snapshot) {
        // Qt.callLater keeps the model from being mutated while a Repeater is
        // mid-incubation.
        Qt.callLater(function () {
            root.removeByOriginalId(root.popupModel, snapshot.originalId);
            root.popupModel.insert(0, snapshot);
            root.everNotified = true;
        });
    }

    // Remove every row whose originalId matches. Chat apps reuse replaces_id
    // per the spec to update a single notification in place — without this,
    // every ping leaves a fresh row behind and the stack fills with
    // duplicates instead of updating.
    function removeByOriginalId(model, originalId) {
        for (let i = model.count - 1; i >= 0; i--) {
            const row = model.get(i);
            if (row && row.originalId === originalId)
                model.remove(i);
        }
    }

    function addToPending(snapshot) {
        Qt.callLater(function () {
            root.removeByOriginalId(root.pendingModel, snapshot.originalId);
            root.pendingModel.insert(0, snapshot);
            while (root.pendingModel.count > root.historyCap)
                root.pendingModel.remove(root.pendingModel.count - 1);
            root.scheduleHistorySave();
        });
    }

    // Called when a popup goes away (timer expired, or the user dismissed or
    // clicked it) — the user is assumed to have seen it.
    function markSeenByOriginalId(originalId) {
        Qt.callLater(function () {
            for (let i = 0; i < root.pendingModel.count; i++) {
                const entry = root.pendingModel.get(i);
                if (!entry || entry.originalId !== originalId)
                    continue;
                const snapshot = root.snapshotFromRow(entry);
                root.pendingModel.remove(i);
                root.pastModel.insert(0, snapshot);
                while (root.pastModel.count > root.historyCap)
                    root.pastModel.remove(root.pastModel.count - 1);
                root.scheduleHistorySave();
                return;
            }
        });
    }

    // Copy a ListModel row into a plain object so it can be re-inserted into
    // a different model without sharing references.
    function snapshotFromRow(row) {
        return {
            id: row.id,
            originalId: row.originalId,
            app: row.app,
            appIcon: row.appIcon,
            desktopEntry: row.desktopEntry || "",
            summary: row.summary,
            body: row.body,
            image: row.image,
            glyph: row.glyph || "",
            urgency: row.urgency,
            expireTimeout: row.expireTimeout || 0,
            timestamp: row.timestamp
        };
    }

    function markAllSeen() {
        Qt.callLater(function () {
            while (root.pendingModel.count > 0) {
                const snapshot = root.snapshotFromRow(root.pendingModel.get(0));
                root.pendingModel.remove(0);
                root.pastModel.insert(0, snapshot);
            }
            while (root.pastModel.count > root.historyCap)
                root.pastModel.remove(root.pastModel.count - 1);
            root.scheduleHistorySave();
        });
    }

    // ------------------------------------------------------ popup removal
    // expire  — the lifetime ran out; the server is told the notification
    //           expired, which is what lets a client re-post it.
    // dismiss — the user (or `dismissAll`) closed it; the server is told the
    //           notification was dismissed.
    function dismissPopup(index) {
        removePopup(index, "dismiss");
    }

    function expirePopup(index) {
        removePopup(index, "expire");
    }

    function removePopup(index, reason) {
        if (index < 0 || index >= popupModel.count)
            return;
        const entry = popupModel.get(index);
        const originalId = entry ? entry.originalId : -1;
        const ref = originalId >= 0 ? liveRefs[originalId] : null;
        popupModel.remove(index);
        if (ref) {
            try {
                if (ref.tracked) {
                    if (reason === "expire" && typeof ref.expire === "function")
                        ref.expire();
                    else
                        ref.dismiss();
                }
            } catch (e) {
                // Object already torn down by the server — nothing to close.
            }
        }
        if (originalId >= 0)
            markSeenByOriginalId(originalId);
    }

    function clearPopups() {
        while (popupModel.count > 0)
            dismissPopup(0);
    }

    function rowsFromModel(model) {
        const rows = [];
        for (let i = 0; i < model.count; i++) {
            const entry = model.get(i);
            if (entry)
                rows.push(snapshotFromRow(entry));
        }
        return rows;
    }

    // Replay the newest entries back onto the screen as toasts.
    function showRecentHistory() {
        const rows = Logic.recentHistoryRows(rowsFromModel(pendingModel), rowsFromModel(pastModel), historyReplayLimit, NotificationUrgency.Normal);

        // Replaying nothing at all looks like a dead keybinding, so say so.
        if (rows.length === 0) {
            popupModel.insert(0, {
                id: -1,
                originalId: -1,
                app: "qshell",
                appIcon: "",
                desktopEntry: "",
                summary: "No recent notifications",
                body: "",
                image: "",
                glyph: "󰂚",
                urgency: NotificationUrgency.Low,
                expireTimeout: 0,
                timestamp: Date.now()
            });
            everNotified = true;
            return "none";
        }

        clearPopups();
        for (let i = 0; i < rows.length; i++)
            popupModel.append(rows[i]);
        everNotified = true;
        return "ok";
    }

    function dismissPending(index) {
        if (index < 0 || index >= pendingModel.count)
            return;
        const entry = pendingModel.get(index);
        if (entry)
            maybeDeleteCachedImage(entry.image);
        pendingModel.remove(index);
        scheduleHistorySave();
    }

    function dismissPast(index) {
        if (index < 0 || index >= pastModel.count)
            return;
        const entry = pastModel.get(index);
        if (entry)
            maybeDeleteCachedImage(entry.image);
        pastModel.remove(index);
        scheduleHistorySave();
    }

    function clearPending() {
        for (let i = 0; i < pendingModel.count; i++) {
            const entry = pendingModel.get(i);
            if (entry)
                maybeDeleteCachedImage(entry.image);
        }
        pendingModel.clear();
        scheduleHistorySave();
    }

    function clearPast() {
        for (let i = 0; i < pastModel.count; i++) {
            const entry = pastModel.get(i);
            if (entry)
                maybeDeleteCachedImage(entry.image);
        }
        pastModel.clear();
        scheduleHistorySave();
    }

    function dismissAll() {
        clearPopups();
        clearPending();
        clearPast();
    }

    // Invoke the libnotify "default" action on a popup, then dismiss it.
    // Clients register the default action under the identifier "default";
    // e.g. `notify-send -A default=Edit` makes click-the-card open an editor.
    function invokePopupDefault(index) {
        if (index < 0 || index >= popupModel.count)
            return;
        const entry = popupModel.get(index);
        const ref = entry ? liveRefs[entry.originalId] : null;
        let invoked = false;
        try {
            if (ref && ref.actions) {
                for (let i = 0; i < ref.actions.length; i++) {
                    const action = ref.actions[i];
                    if (action && action.identifier === "default") {
                        action.invoke();
                        invoked = true;
                        break;
                    }
                }
            }
        } catch (e) {
            // Notification already torn down by the server — fall through.
            console.warn("Notifs: invoking the default action failed:", e);
        }
        // Chat apps rarely register a "default" action — they just expect a
        // click on the notification to focus their window.
        if (!invoked)
            focusApp(entry);
        dismissPopup(index);
    }

    // Focus the window that sent this notification. Upstream hands the app
    // name to omarchy-hyprland-focus-app; niri's window list is already in
    // this process, so the match happens in NotificationLogic and the result
    // is one FocusWindow action over the niri socket.
    function focusApp(entry) {
        if (!entry || !niri)
            return false;
        const ref = entry.originalId >= 0 ? liveRefs[entry.originalId] : null;
        let desktopEntry = "";
        try {
            if (ref && ref.desktopEntry)
                desktopEntry = String(ref.desktopEntry);
        } catch (e) {
            desktopEntry = "";
        }
        const id = Logic.matchWindowId(Logic.focusCandidates(entry, desktopEntry), niri.windows);
        if (id === null)
            return false;
        niri.focusWindow(id);
        return true;
    }

    // ---------------------------------------------------------- image cache
    //
    // Screenshot helpers ship an image path pointing into /tmp. The history
    // thumbnail should outlive that file, so the image is copied into a
    // long-lived cache dir on ingress and the history row is rewritten to the
    // cached path once cp finishes. The popup keeps the original path, so it
    // always renders even while the copy is in flight.
    function maybeCacheImage(snapshot) {
        const image = String(snapshot.image || "");
        if (!image)
            return;
        // image:// URIs are decoded from raw bytes by Quickshell's image
        // provider and cannot be copied out from QML — history references
        // them by URI and they disappear with the notification.
        if (image.indexOf("image://") === 0)
            return;
        if (image.indexOf("file:///tmp/") !== 0)
            return;

        const srcPath = decodeURIComponent(image.substring(7));
        const destPath = imageCacheDir + snapshot.timestamp + "-" + snapshot.originalId + "." + Logic.imageExtension(srcPath);

        imageCacheQueue = imageCacheQueue.concat([
            {
                srcPath: srcPath,
                destPath: destPath,
                targetUri: "file://" + encodeURI(destPath),
                originalId: snapshot.originalId,
                timestamp: snapshot.timestamp
            }
        ]);
        runNextImageCacheJob();
    }

    function runNextImageCacheJob() {
        if (imageCacheProc.running || imageCacheQueue.length === 0)
            return;

        const job = imageCacheQueue[0];
        imageCacheQueue = imageCacheQueue.slice(1);
        imageCacheProc.targetUri = job.targetUri;
        imageCacheProc.matchOriginalId = job.originalId;
        imageCacheProc.matchTimestamp = job.timestamp;
        imageCacheProc.command = ["cp", "-f", job.srcPath, job.destPath];
        imageCacheProc.running = true;
    }

    function rewriteCachedImage(targetUri, originalId, timestamp) {
        function rewrite(model) {
            for (let i = 0; i < model.count; i++) {
                const row = model.get(i);
                if (row && row.originalId === originalId && row.timestamp === timestamp) {
                    model.setProperty(i, "image", targetUri);
                    return true;
                }
            }
            return false;
        }

        return rewrite(pendingModel) || rewrite(pastModel);
    }

    function maybeDeleteCachedImage(image) {
        const path = String(image || "");
        if (!path || path.indexOf("file://") !== 0)
            return;
        const local = decodeURIComponent(path.substring(7));
        if (local.indexOf(imageCacheDir) !== 0)
            return;
        deleteImageProc.command = ["rm", "-f", local];
        deleteImageProc.running = true;
    }

    property Process ensureDirsProc: Process {
        command: ["mkdir", "-p", root.stateDir, root.imageCacheDir]
        running: false
    }

    property Process imageCacheProc: Process {
        property string targetUri: ""
        property int matchOriginalId: -1
        property double matchTimestamp: 0

        onExited: exitCode => {
            if (exitCode === 0 && targetUri && root.rewriteCachedImage(targetUri, matchOriginalId, matchTimestamp))
                root.scheduleHistorySave();
            targetUri = "";
            matchOriginalId = -1;
            matchTimestamp = 0;
            root.runNextImageCacheJob();
        }
    }

    property Process deleteImageProc: Process {
        running: false
    }

    // --------------------------------------------------- history persistence
    property FileView historyFile: FileView {
        path: root.historyPath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadHistory(text())
        // First run: the file does not exist yet. Without this branch
        // historyLoaded stays false forever, scheduleHistorySave becomes a
        // no-op, and the file is never created.
        onLoadFailed: root.loadHistory("")
    }

    property Timer historySaveTimer: Timer {
        interval: 200
        repeat: false
        onTriggered: root.flushHistory()
    }

    property Timer pastPruneTimer: Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.prunePast()
    }

    function prunePast() {
        if (pastModel.count === 0)
            return;
        const cutoff = Date.now() - pastTtlMs;
        let removed = false;
        for (let i = pastModel.count - 1; i >= 0; i--) {
            const entry = pastModel.get(i);
            if (entry && entry.timestamp && entry.timestamp < cutoff) {
                if (entry.image)
                    maybeDeleteCachedImage(entry.image);
                pastModel.remove(i);
                removed = true;
            }
        }
        if (removed)
            scheduleHistorySave();
    }

    function scheduleHistorySave() {
        if (!historyLoaded)
            return;
        historySaveTimer.restart();
    }

    function loadHistory(raw) {
        // FileView can fire onLoaded more than once during startup (the
        // implicit preload plus the explicit reload below), and a second pass
        // would append a second copy of every persisted row.
        if (historyLoaded)
            return;

        const parsed = Logic.parseHistory(raw, NotificationUrgency.Normal, historyCap);
        if (parsed.empty) {
            historyLoaded = true;
            return;
        }
        if (parsed.error) {
            console.warn("Notifs: history parse failed:", parsed.errorMessage || "");
            historyLoaded = true;
            return;
        }

        if (parsed.dnd !== null) {
            hydrating = true;
            dnd = parsed.dnd;
            hydrating = false;
        }

        // Newest-first on disk; append in order so the models match.
        Qt.callLater(function () {
            for (let i = 0; i < parsed.pending.length; i++)
                root.pendingModel.append(parsed.pending[i]);
            for (let j = 0; j < parsed.past.length; j++)
                root.pastModel.append(parsed.past[j]);
            root.historyLoaded = true;
            if (parsed.hadDuplicates)
                root.scheduleHistorySave();
        });
    }

    function flushHistory() {
        function dump(model) {
            const out = [];
            for (let i = 0; i < model.count; i++) {
                const r = model.get(i);
                if (!r)
                    continue;
                out.push({
                    id: r.id,
                    originalId: r.originalId,
                    app: r.app,
                    appIcon: r.appIcon,
                    desktopEntry: r.desktopEntry || "",
                    summary: r.summary,
                    body: r.body,
                    image: r.image,
                    glyph: r.glyph || "",
                    urgency: r.urgency,
                    expireTimeout: r.expireTimeout || 0,
                    timestamp: r.timestamp
                });
            }
            return out;
        }
        historyFile.setText(JSON.stringify({
            version: 2,
            dnd: dnd,
            pending: dump(pendingModel),
            past: dump(pastModel)
        }, null, 2) + "\n");
    }

    // ------------------------------------------------------------- server
    readonly property NotificationServer server: NotificationServer {
        keepOnReload: true
        imageSupported: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true

        onNotification: n => root.handleNotification(n)
    }

    // ---------------------------------------------------------------- IPC
    property IpcHandler ipc: IpcHandler {
        target: "notifs"

        // Kept from before the parity port: toggles, and says which way.
        function dnd(): string {
            root.toggleDnd();
            return root.dnd ? "dnd on" : "dnd off";
        }

        function dndState(): string {
            return root.dnd ? "on" : "off";
        }

        function isDnd(): string {
            return dndState();
        }

        function toggleDnd(): string {
            root.toggleDnd();
            return dndState();
        }

        function setDnd(value: string): string {
            const v = String(value || "").toLowerCase();
            root.setDnd(v === "true" || v === "1" || v === "on" || v === "yes");
            return dndState();
        }

        function count(): int {
            return root.popupModel.count;
        }

        function status(): string {
            return JSON.stringify({
                dnd: root.dnd,
                popups: root.popupModel.count,
                pending: root.pendingModel.count,
                past: root.pastModel.count,
                historyLoaded: root.historyLoaded
            });
        }

        function showHistory(): string {
            return root.showRecentHistory();
        }

        // `clear` empties the past bucket (the "already seen" one).
        function clear(): string {
            root.clearPast();
            return "ok";
        }

        function clearPending(): string {
            root.clearPending();
            return "ok";
        }

        function markAllSeen(): string {
            root.markAllSeen();
            return "ok";
        }

        function dismissAll(): string {
            root.dismissAll();
            return "ok";
        }

        // Dismiss the newest popup; fall back to the newest pending entry,
        // then past, when nothing is on screen.
        function dismissOne(): string {
            if (root.popupModel.count > 0) {
                root.dismissPopup(0);
                return "ok";
            }
            if (root.pendingModel.count > 0) {
                root.dismissPending(0);
                return "ok";
            }
            if (root.pastModel.count > 0) {
                root.dismissPast(0);
                return "ok";
            }
            return "none";
        }

        // Fire the default action on the newest popup, then dismiss it.
        function invokeLast(): string {
            if (root.popupModel.count === 0)
                return "none";
            root.invokePopupDefault(0);
            return "ok";
        }

        function dismiss(summary: string): string {
            const needle = String(summary || "");
            if (!needle)
                return "none";
            let hit = false;
            function sweep(model, dismissFn) {
                for (let i = model.count - 1; i >= 0; i--) {
                    const row = model.get(i);
                    if (row && String(row.summary || "").indexOf(needle) !== -1) {
                        dismissFn(i);
                        hit = true;
                    }
                }
            }
            sweep(root.pendingModel, root.dismissPending);
            sweep(root.pastModel, root.dismissPast);
            sweep(root.popupModel, root.dismissPopup);
            return hit ? "ok" : "none";
        }

        function ping(): string {
            return "ok";
        }
    }

    Component.onCompleted: {
        ensureDirsProc.running = true;
        // Give mkdir a tick, then load whatever history exists. FileView
        // surfaces a missing file through onLoadFailed, which loadHistory
        // treats as an empty history.
        Qt.callLater(() => historyFile.reload());
    }
}

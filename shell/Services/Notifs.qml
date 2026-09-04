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
// Ported from omarchy's notifications plugin Service.qml: the
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

    // The ShellRoot, injected by shell.qml: the history-center IPC verbs
    // route through its toggle/show/hideNotifCenter to reach the bar.
    property var shellRoot: null

    readonly property string home: Quickshell.env("HOME")
    // History and DND are persistent user state, not regeneratable cache, so
    // they live under XDG_STATE_HOME beside stay-awake / blur / reminders.
    readonly property string stateDir: home + "/.local/state/qshell/"
    readonly property string historyPath: stateDir + "notifications.json"
    // One file per on-screen popup, so live toasts survive a real shell
    // restart — the server's keepOnReload only spans in-process reloads. A
    // file exists exactly as long as its popup is showing: written when the
    // toast appears, deleted when it expires, is dismissed, is acted upon,
    // is replaced, or overflows the cap.
    readonly property string popupStateDir: stateDir + "notifications/"
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
    // real restart. Matches how stay-awake and blur persist.
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

    // Whether an arriving toast also plays its sound-theme event. Persisted
    // beside DND in the same file, for the same reasons.
    property bool soundEnabled: true
    onSoundEnabledChanged: {
        if (!hydrating)
            scheduleHistorySave();
    }

    function setSound(value) {
        soundEnabled = !!value;
    }

    function toggleSound() {
        soundEnabled = !soundEnabled;
    }

    // Per-sender silence: apps whose notifications are recorded but never
    // toast, sound, or count toward the bell. See NotificationLogic.muteRules
    // for why these match as substrings.
    property var mutedApps: []
    onMutedAppsChanged: {
        if (!hydrating)
            scheduleHistorySave();
    }

    function isMuted(app) {
        return Logic.isMutedApp(mutedApps, app);
    }

    function muteApp(app) {
        mutedApps = Logic.addMuteRule(mutedApps, app);
    }

    function unmuteApp(app) {
        mutedApps = Logic.removeMuteRule(mutedApps, app);
    }

    // popupModel  — the on-screen toast stack.
    // pendingModel — received but not yet seen by the user. Anything DND
    //                suppresses lands here and stays until reviewed; anything
    //                that pops up also lives here until its toast goes away.
    // pastModel   — already seen on screen, kept until it ages out.
    readonly property ListModel popupModel: ListModel {}
    readonly property ListModel pendingModel: ListModel {}
    readonly property ListModel pastModel: ListModel {}

    readonly property int historyCap: 1000
    readonly property int historyReplayLimit: 5
    // Retention, per bucket: an entry goes when it is older than this OR when
    // historyCap newer ones exist. Both limits, because either alone fails in
    // one direction — an age limit lets a notification storm keep thousands
    // of rows, and a count limit alone keeps a quiet machine's notifications
    // for years.
    //
    // Thirty days is the number both durable-history plugins in the
    // marketplace settled on (jankeesvw's and ritechoice23's), and it is a
    // deliberate PRIVACY setting as much as a storage one: this file is every
    // notification body received, two-factor codes and chat messages
    // included. Shortening it is the lever that limits what a stolen disk
    // gives up.
    readonly property int historyKeepDays: 30
    readonly property double historyKeepMs: historyKeepDays * 24 * 60 * 60 * 1000

    readonly property int lowPopupDuration: 5000
    readonly property int normalPopupDuration: 8000
    readonly property int maxPopupDuration: 30000
    // Critical stays up far longer than the cap above, but not forever — an
    // immortal toast retains its live object and signal closures for the
    // whole session.
    readonly property int criticalPopupDuration: 5 * 60 * 1000
    // A notification storm must not grow the toast stack without bound; past
    // this the oldest toasts overflow off screen (see overflowPopup).
    readonly property int popupCap: 10

    // Live Notification objects by originalId, kept OUT of the ListModels: a
    // QObject stored in a model role becomes a dangling C++ pointer once the
    // server destroys the notification, and the next read of that role
    // crashes. A JS map only holds a wrapper, which degrades to a catchable
    // error instead.
    property var liveRefs: ({})
    property var imageCacheQueue: []
    property var deleteImageQueue: []
    property bool historyLoaded: false

    // ------------------------------------------------------- timeout policy
    // Critical holds the screen for minutes, not seconds. Everything else
    // takes the sender's requested timeout, floored at the per-urgency
    // minimum and capped at 30s.
    function durationFor(urgency, expireTimeout) {
        switch (urgency) {
        case NotificationUrgency.Critical:
            return criticalPopupDuration;
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

    // The server's notification ids restart at 1 every shell run, but history
    // rows persist across runs — a raw id as the model key would let a new
    // session's notification delete an unrelated persisted row that happened
    // to share it. Fold a per-session epoch into the key at ingress: the same
    // server id still maps to the same key within a session (replace-by-id
    // keeps working), while keys from different sessions cannot collide, and
    // old on-disk rows keep their small numeric ids which are equally safe.
    readonly property double sessionEpoch: Date.now()

    function snapshotOf(notification) {
        const snapshot = Logic.snapshotOf(notification, Date.now());
        snapshot.originalId = sessionEpoch + snapshot.originalId;
        return snapshot;
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
        // A muted sender is silenced the same way DND silences everything,
        // and through the same escape hatch — shouldBypassDnd, which passes
        // our own `qshell` notifications and a critical `notify-send`. So a
        // mute can never hide the shell's own crash toast. It deliberately
        // does NOT exempt a third-party sender's own "critical": that flag is
        // set by the app being muted, and an app that can promote itself out
        // of a mute is not muted. Same rule DND already lives by.
        const silenced = (dnd || isMuted(notification.appName)) && !shouldBypassDnd(notification);

        if (transient || ephemeral) {
            if (silenced) {
                delete liveRefs[snapshot.originalId];
                notification.tracked = false;
                return;
            }
            pushPopup(snapshot);
            return;
        }

        // A muted sender's record still lands in history — the point of the
        // mute is not to be interrupted, and a searchable record costs
        // nothing — but it goes STRAIGHT TO PAST rather than to pending.
        // Pending is what the bell counts, so routing a muted app there would
        // trade a toast for a badge and silence nothing.
        if (isMuted(notification.appName) && !shouldBypassDnd(notification)) {
            addToPast(snapshot);
            maybeCacheImage(snapshot);
            delete liveRefs[snapshot.originalId];
            notification.tracked = false;
            return;
        }

        // Pending first, unconditionally. DND only suppresses the toast — the
        // record still has to land somewhere the user can review later.
        addToPending(snapshot);
        maybeCacheImage(snapshot);

        if (silenced) {
            delete liveRefs[snapshot.originalId];
            notification.tracked = false;
            return;
        }

        pushPopup(snapshot);
        playSound(snapshot);
    }

    // ---------------------------------------------------------------- sound
    //
    // One canberra call per toast, so the installed sound theme decides what
    // a notification sounds like. Fire-and-forget: a Process bound to the
    // service would serialize a burst into a queue of stale beeps, and
    // execDetached is exactly the "start it and stop caring" shape this
    // needs. Cheap enough not to need one — the binary exits on its own.
    //
    // Only ever called from the fresh-toast path: a shell restart replaying
    // the popups that were on screen must not sound them again, and neither
    // must the history replay keybinding.
    function playSound(snapshot) {
        if (!soundEnabled || !snapshot)
            return;
        Quickshell.execDetached(["canberra-gtk-play", "-i", Logic.soundEventFor(snapshot.urgency, NotificationUrgency.Critical, NotificationUrgency.Low)]);
    }

    // ------------------------------------------------------ drag clipboard
    //
    // What a "copied to clipboard" toast is talking about, so dragging that
    // toast hands over the thing itself rather than the sentence announcing
    // it. Captured when the notification ARRIVES, which is the only moment
    // the clipboard is guaranteed to still hold it — every one of our own
    // copy scripts runs wl-copy and then notifies, and by the time someone
    // drags the toast they may well have copied something else.
    //
    // In memory only, and deliberately NOT a snapshot role: a role would be
    // written to notifications.json, and putting clipboard contents into a
    // thirty-day on-disk archive is exactly the thing the retention note
    // warns about.
    property string clipboardText: ""
    readonly property int clipboardTextCap: 64 * 1024

    function captureClipboardText() {
        if (clipboardReadProc.running)
            return;
        // Cleared BEFORE the read rather than on its failure. wl-paste exits
        // non-zero whenever the clipboard holds no text at all — which is the
        // common case here, since niri's own screenshot puts a PNG on it — and
        // keeping the last successful read would let a toast hand over
        // whatever was copied ten minutes ago. Empty is correct: dragPayload
        // falls back to the notification's body.
        clipboardText = "";
        clipboardReadProc.running = true;
    }

    property Process clipboardReadProc: Process {
        // --type text/plain so an image-only clipboard fails cleanly and
        // leaves the last text alone rather than yielding binary.
        command: ["wl-paste", "--no-newline", "--type", "text/plain"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.clipboardText = text.length > root.clipboardTextCap ? text.substring(0, root.clipboardTextCap) : text
        }
    }

    function pushPopup(snapshot) {
        if (Logic.isClipboardNotification(snapshot.summary, snapshot.body))
            captureClipboardText();
        persistPopupFile(snapshot);
        // Qt.callLater keeps the model from being mutated while a Repeater is
        // mid-incubation.
        Qt.callLater(function () {
            root.removePopupsByOriginalId(snapshot.originalId, Logic.popupFileName(snapshot));
            root.popupModel.insert(0, snapshot);
            while (root.popupModel.count > root.popupCap)
                root.overflowPopup(root.popupModel.count - 1);
            root.everNotified = true;
        });
    }

    // Popup-specific variant of removeByOriginalId: a replaced popup
    // (freedesktop replaces_id) leaves the screen, so its persisted file has
    // to go too — otherwise it resurrects on the next shell restart.
    // keepFileName is the replacement's own file: a same-millisecond
    // replacement shares the replaced row's filename, and the new write is
    // already queued — deleting that path here would erase the replacement's
    // only file. Restored rows need no extra guard: their originalId carries
    // the previous session's epoch, so a fresh notification can never match
    // one here.
    function removePopupsByOriginalId(originalId, keepFileName) {
        for (let i = popupModel.count - 1; i >= 0; i--) {
            const row = popupModel.get(i);
            if (!row || row.originalId !== originalId)
                continue;
            if (Logic.popupFileName(row) !== keepFileName)
                deletePopupFileFor(row);
            popupModel.remove(i);
        }
    }

    // Overflow removal: the toast leaves the screen and the server is told it
    // expired (so the sender may re-post), but unlike expire/dismiss it is
    // NOT marked seen — a real app's record stays in pending for review.
    function overflowPopup(index) {
        if (index < 0 || index >= popupModel.count)
            return;
        const entry = popupModel.get(index);
        const originalId = entry ? entry.originalId : -1;
        const ref = originalId >= 0 ? liveRefs[originalId] : null;
        // Overflowed off screen is still off screen — the persisted file
        // must not resurrect this toast on the next shell restart.
        if (entry)
            deletePopupFileFor(entry);
        popupModel.remove(index);
        if (!ref)
            return;
        try {
            if (ref.tracked) {
                if (typeof ref.expire === "function")
                    ref.expire();
                else
                    ref.dismiss();
            }
        } catch (e) {
            // Object already torn down by the server — nothing to close.
        }
    }

    // Remove every row whose originalId matches. Chat apps reuse replaces_id
    // per the spec to update a single notification in place — without this,
    // every ping leaves a fresh row behind and the stack fills with
    // duplicates instead of updating.
    function removeByOriginalId(model, originalId) {
        for (let i = model.count - 1; i >= 0; i--) {
            const row = model.get(i);
            if (row && row.originalId === originalId) {
                // The replacement snapshot caches to its own file (the dest
                // name carries the timestamp), so the replaced row's copy has
                // no other referent — without this it stayed on disk forever.
                maybeDeleteCachedImages(row);
                model.remove(i);
            }
        }
    }

    function addToPending(snapshot) {
        Qt.callLater(function () {
            root.removeByOriginalId(root.pendingModel, snapshot.originalId);
            root.pendingModel.insert(0, snapshot);
            root.capModel(root.pendingModel);
            root.scheduleHistorySave();
        });
    }

    // Straight into the seen bucket, without ever having been on screen —
    // the muted-sender path. Same insert-and-cap shape as addToPending.
    function addToPast(snapshot) {
        Qt.callLater(function () {
            root.removeByOriginalId(root.pastModel, snapshot.originalId);
            root.pastModel.insert(0, snapshot);
            root.capModel(root.pastModel);
            root.scheduleHistorySave();
        });
    }

    // Evict from the tail until the model is within historyCap, taking each
    // evicted row's cached images with it.
    function capModel(model) {
        while (model.count > historyCap) {
            const evicted = model.get(model.count - 1);
            if (evicted)
                maybeDeleteCachedImages(evicted);
            model.remove(model.count - 1);
        }
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
                root.capModel(root.pastModel);
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
            // Carried like every other role: this is the entry the history
            // center hands to invokeEntryDefault, and a row that loses its
            // execArgv here is a row whose click silently does nothing. It is
            // also the pending→past migration in markAllSeen, so dropping it
            // would disarm a notification just for being marked seen.
            execArgv: row.execArgv || "",
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
            root.capModel(root.pastModel);
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
        // A restored row's ref is a miss by construction (its epoch belongs
        // to the dead session), so it degrades to plain removal here.
        const ref = originalId >= 0 ? liveRefs[originalId] : null;
        // The popup is leaving the screen — for any reason — so its
        // persisted file must not survive to the next shell restart. History
        // replays and the no-recent placeholder never had a file; for them
        // the rm -f is a harmless no-op.
        if (entry)
            deletePopupFileFor(entry);
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
                execArgv: "",
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
            maybeDeleteCachedImages(entry);
        pendingModel.remove(index);
        scheduleHistorySave();
    }

    function dismissPast(index) {
        if (index < 0 || index >= pastModel.count)
            return;
        const entry = pastModel.get(index);
        if (entry)
            maybeDeleteCachedImages(entry);
        pastModel.remove(index);
        scheduleHistorySave();
    }

    function clearPending() {
        for (let i = 0; i < pendingModel.count; i++) {
            const entry = pendingModel.get(i);
            if (entry)
                maybeDeleteCachedImages(entry);
        }
        pendingModel.clear();
        scheduleHistorySave();
    }

    function clearPast() {
        for (let i = 0; i < pastModel.count; i++) {
            const entry = pastModel.get(i);
            if (entry)
                maybeDeleteCachedImages(entry);
        }
        pastModel.clear();
        scheduleHistorySave();
    }

    function dismissAll() {
        clearPopups();
        clearPending();
        clearPast();
    }

    // ------------------------------------------------ history by identity
    //
    // The center shows both buckets merged and sorted by time, so a row there
    // has no index into either model. These take the row itself and find it:
    // the epoch-qualified originalId plus the timestamp, which is the same
    // pair restorePopups already trusts to recognise a popup it has seen.
    // originalId alone is not enough — a replaced notification keeps its id.
    function indexOfEntry(model, entry) {
        if (!entry)
            return -1;
        for (let i = 0; i < model.count; i++) {
            const row = model.get(i);
            if (row && row.originalId === entry.originalId && row.timestamp === entry.timestamp)
                return i;
        }
        return -1;
    }

    function dismissEntry(entry) {
        const pendingIndex = indexOfEntry(pendingModel, entry);
        if (pendingIndex >= 0) {
            dismissPending(pendingIndex);
            return true;
        }
        const pastIndex = indexOfEntry(pastModel, entry);
        if (pastIndex >= 0) {
            dismissPast(pastIndex);
            return true;
        }
        return false;
    }

    function markEntrySeen(entry) {
        if (entry && indexOfEntry(pendingModel, entry) >= 0)
            markSeenByOriginalId(entry.originalId);
    }

    // Everything that arrived in [from, to) — the panel's per-day CLEAR.
    function clearRange(from, to) {
        let removed = 0;
        function sweep(model) {
            for (let i = model.count - 1; i >= 0; i--) {
                const entry = model.get(i);
                if (!entry || !(entry.timestamp >= from && entry.timestamp < to))
                    continue;
                maybeDeleteCachedImages(entry);
                model.remove(i);
                removed += 1;
            }
        }
        sweep(pendingModel);
        sweep(pastModel);
        if (removed > 0)
            scheduleHistorySave();
        return removed;
    }

    function clearHistory() {
        clearPending();
        clearPast();
    }

    // Run a row's carried click action, if it has one. Our own toasts send it
    // as data (`--hint=string:qshell-exec-argv:...`, see
    // NotificationLogic.execArgvFromHints) precisely so it survives into the
    // popup files and the history — a restored row's liveRefs entry is a miss
    // by construction, so a libnotify action would be dead on arrival, and the
    // sender that registered it would still be blocked waiting for a click it
    // can never be told about. Ported from omarchy 5a58f79, then 07443f3.
    //
    // The constant `exec "$@"` is what keeps this out of shell-string
    // territory: the argv only ever lands in positional parameters, which bash
    // expands without re-tokenizing, so a filename or a page title stays one
    // argument no matter what is in it. The login shell is still there for the
    // PATH and session environment a GUI target needs.
    //
    // Launched through app-run, not execDetached alone: execDetached children
    // stay in qshell.service's cgroup, so anything the click opens would die
    // with the next shell restart (the same trap bin/qshell-relaunch documents).
    function runExecAction(entry) {
        const argv = Logic.parseExecArgv(entry ? entry.execArgv : "");
        if (!argv)
            return false;
        Quickshell.execDetached(["app-run", "bash", "-lc", 'exec "$@"', "bash"].concat(argv));
        return true;
    }

    // Invoke a popup's click action, then dismiss it. Our own toasts carry the
    // command (runExecAction); third-party clients instead register a
    // libnotify action under the identifier "default", e.g. `notify-send -A
    // default=Edit` — that one only works while the sender is still live.
    function invokePopupDefault(index) {
        if (index < 0 || index >= popupModel.count)
            return;
        const entry = popupModel.get(index);
        if (runExecAction(entry)) {
            dismissPopup(index);
            return;
        }
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

    // Invoke a history entry's "default" action if its live notification
    // still exists, else fall back to focusing the sender's window — the
    // history center's Enter/click, mirroring invokePopupDefault without
    // assuming a popup row.
    function invokeEntryDefault(entry) {
        if (!entry)
            return false;
        if (runExecAction(entry))
            return true;
        const ref = entry.originalId >= 0 ? liveRefs[entry.originalId] : null;
        try {
            if (ref && ref.actions) {
                for (let i = 0; i < ref.actions.length; i++) {
                    const action = ref.actions[i];
                    if (action && action.identifier === "default") {
                        action.invoke();
                        return true;
                    }
                }
            }
        } catch (e) {
            // Notification already torn down by the server — fall through.
            console.warn("Notifs: invoking the default action failed:", e);
        }
        return focusApp(entry);
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
    // Both roles, not just the big image: Chromium-family senders (every one
    // of our web apps) pass the avatar as an appIcon file in a scoped /tmp
    // directory they delete when the notification closes, so a history row
    // that keeps the original path loses its avatar (omarchy b2207c3).
    readonly property var cachedImageRoles: ["image", "appIcon"]

    function maybeCacheImage(snapshot) {
        for (let i = 0; i < cachedImageRoles.length; i++)
            maybeCacheImageRole(snapshot, cachedImageRoles[i]);
    }

    function maybeCacheImageRole(snapshot, role) {
        const value = String(snapshot[role] || "");
        if (!value)
            return;
        // image:// URIs are decoded from raw bytes by Quickshell's image
        // provider and cannot be copied out from QML — history references
        // them by URI and they disappear with the notification.
        if (value.indexOf("image://") === 0)
            return;
        if (value.indexOf("file:///tmp/") !== 0)
            return;

        const srcPath = decodeURIComponent(value.substring(7));
        // Role in the name: one notification can carry both, and they would
        // otherwise collide on the same cache path.
        const destPath = imageCacheDir + snapshot.timestamp + "-" + snapshot.originalId + "-" + role + "." + Logic.imageExtension(srcPath);

        imageCacheQueue = imageCacheQueue.concat([
            {
                role: role,
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
        imageCacheProc.matchRole = job.role;
        // Not a bare `cp` (omarchy b2207c3): the path comes from the sender,
        // and this queue is strictly serial — one job that never returns
        // wedges every later notification's image. A FIFO would do it, and so
        // would a file that keeps growing. So: read a bounded prefix under a
        // timeout, reject anything that reaches the cap rather than caching a
        // truncated image, and rename the result in so a killed job cannot
        // publish a partial file.
        //
        // 16 MiB is far above any avatar or full-resolution screenshot that
        // actually arrives here, so the cap only ever fires on something that
        // has no business being a notification image.
        imageCacheProc.command = ["bash", "-c", "src=$1; dst=$2; cap=16777216; tmp=$dst.part; " + "timeout 5s head -c $((cap + 1)) -- \"$src\" >\"$tmp\" 2>/dev/null || { rm -f \"$tmp\"; exit 1; }; " + "size=$(stat -c '%s' \"$tmp\" 2>/dev/null || echo 0); " + "[ \"$size\" -gt 0 ] && [ \"$size\" -le $cap ] || { rm -f \"$tmp\"; exit 1; }; " + "mv -f \"$tmp\" \"$dst\"", "notif-image-cache", job.srcPath, job.destPath];
        imageCacheProc.running = true;
    }

    function rewriteCachedImage(targetUri, originalId, timestamp, role) {
        function rewrite(model) {
            for (let i = 0; i < model.count; i++) {
                const row = model.get(i);
                if (row && row.originalId === originalId && row.timestamp === timestamp) {
                    model.setProperty(i, role, targetUri);
                    return true;
                }
            }
            return false;
        }

        return rewrite(pendingModel) || rewrite(pastModel);
    }

    // Deletions queue up: a Process that is already running silently ignores
    // running=true, so the synchronous loops in clearPending/clearPast/
    // prunePast would otherwise drop every file between the first and the
    // last. One rm takes the whole accumulated batch.
    function maybeDeleteCachedImage(image) {
        const path = String(image || "");
        if (!path || path.indexOf("file://") !== 0)
            return;
        const local = decodeURIComponent(path.substring(7));
        if (local.indexOf(imageCacheDir) !== 0)
            return;
        deleteImageQueue = deleteImageQueue.concat([local]);
        runNextImageDeleteJob();
    }

    // A row can hold a cached copy in either role, so eviction sweeps both.
    function maybeDeleteCachedImages(entry) {
        if (!entry)
            return;
        for (let i = 0; i < cachedImageRoles.length; i++)
            maybeDeleteCachedImage(entry[cachedImageRoles[i]]);
    }

    function runNextImageDeleteJob() {
        if (deleteImageProc.running || deleteImageQueue.length === 0)
            return;
        deleteImageProc.command = ["rm", "-f"].concat(deleteImageQueue);
        deleteImageQueue = [];
        deleteImageProc.running = true;
    }

    // 0700, and chmod as well as mkdir -m so directories that already exist
    // from before this were tightened too — `mkdir -m` only applies its mode
    // to a directory it actually creates.
    //
    // Worth the two extra syscalls because of what retention changed: this
    // tree used to hold fifteen minutes of notifications and now holds thirty
    // days of them, bodies included. That is every two-factor code and every
    // chat message received in a month, and it was mode 0644 in a 0755
    // directory. Same reasoning as the two durable-history plugins in the
    // marketplace, both of which are 0700/0600 for exactly this.
    // The history file's own 0600 is set once, here, rather than after every
    // save: FileView writes atomically through QSaveFile, which carries the
    // existing target's permissions onto its replacement, so the mode
    // survives each flush instead of resetting to the umask. (Verified on
    // this machine — see docs/notifications-2026-09-04.md.)
    property Process ensureDirsProc: Process {
        command: ["bash", "-c", 'mkdir -p -m 700 "$1" "$2" "$3" && chmod 700 "$1" "$2" "$3" && [ -e "$4" ] && chmod 600 "$4" || true', "--", root.stateDir, root.popupStateDir, root.imageCacheDir, root.historyPath]
        running: false
    }

    property Process imageCacheProc: Process {
        property string targetUri: ""
        // double, not int: originalId carries the session epoch (Date.now()
        // + the server id), which overflows a 32-bit QML int and truncates to
        // a value no row can match — so rewriteCachedImage always missed and
        // the else branch deleted the copy it had just made. Every image has
        // been cached and immediately thrown away since the epoch-qualified
        // ids landed. matchTimestamp below is a double for the same reason.
        property double matchOriginalId: -1
        property double matchTimestamp: 0
        property string matchRole: "image"

        onExited: exitCode => {
            if (exitCode === 0 && targetUri) {
                if (root.rewriteCachedImage(targetUri, matchOriginalId, matchTimestamp, matchRole))
                    root.scheduleHistorySave();
                else
                    // The row this copy was for is already gone (replaced or
                    // dismissed while the copy ran) — nothing references the
                    // file.
                    root.maybeDeleteCachedImage(targetUri);
            }
            targetUri = "";
            matchOriginalId = -1;
            matchTimestamp = 0;
            matchRole = "image";
            root.runNextImageCacheJob();
        }
    }

    property Process deleteImageProc: Process {
        running: false
        onExited: root.runNextImageDeleteJob()
    }

    // ----------------------------------------------------- popup persistence
    //
    // Mirror every on-screen popup to its own file under popupStateDir so
    // toasts survive real shell restarts. Writes and deletes go through one
    // serialized queue — same idiom as the image cache above: a burst of
    // replaces_id updates must not race a single reused Process, and the
    // ordering guarantees a delete issued after a write wins.
    property var popupFileQueue: []

    function enqueuePopupFileJob(command) {
        popupFileQueue = popupFileQueue.concat([command]);
        runNextPopupFileJob();
    }

    function runNextPopupFileJob() {
        if (popupFileProc.running || popupFileQueue.length === 0)
            return;
        popupFileProc.command = popupFileQueue[0];
        popupFileQueue = popupFileQueue.slice(1);
        popupFileProc.running = true;
    }

    property Process popupFileProc: Process {
        running: false
        onExited: root.runNextPopupFileJob()
    }

    function persistPopupFile(snapshot) {
        // The JSON travels as an argument, not through shell interpolation,
        // so summaries/bodies with quotes or backticks can't break the
        // command. The mkdir guards notifications that arrive before
        // ensureDirsProc has run — and carries the same umask, so a popup
        // that beats the service's own mkdir does not create the directory
        // world-readable and leave it that way.
        enqueuePopupFileJob(["bash", "-c", "umask 077 && mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/$3\"", "--", popupStateDir, Logic.serializePopup(snapshot, NotificationUrgency.Normal), Logic.popupFileName(snapshot)]);
    }

    function deletePopupFileFor(row) {
        if (!row)
            return;
        enqueuePopupFileJob(["rm", "-f", popupStateDir + Logic.popupFileName(row)]);
    }

    property Process restorePopupsProc: Process {
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.restorePopups(text)
        }
    }

    function restorePopups(raw) {
        const entries = Logic.parsePopupFiles(raw, NotificationUrgency.Normal);
        const now = Date.now();
        const live = [];
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            const duration = durationFor(entry.urgency, entry.expireTimeout);
            if (Logic.popupExpired(entry, duration, now)) {
                deletePopupFileFor(entry);
                continue;
            }
            // Survivors restart with a full lifetime on purpose: shell
            // restarts are rare, and a full look after the restart flicker
            // beats resuming a toast with a second left on its clock. The
            // reset is persisted as an absolute deadline so a second restart
            // while the toast is still on screen judges it by the reset
            // clock, not the original timestamp.
            entry.deadline = now + duration;
            persistPopupFile(entry);
            // deadline is persistence metadata, not a model role — fresh
            // rows never carry it, and ListModel roles must stay consistent.
            delete entry.deadline;
            live.push(entry);
        }
        if (live.length === 0)
            return;

        Qt.callLater(function () {
            for (let j = 0; j < live.length; j++) {
                const restored = live[j];
                // A notification received while the restore was reading the
                // dir may already have written this very file — then a live
                // row matches on id AND timestamp, it IS this entry, and it
                // must be left alone. Ids from the dead session cannot
                // collide with fresh ones (originalId carries the epoch), so
                // this is the only duplicate that can exist.
                let duplicate = false;
                for (let k = 0; k < root.popupModel.count; k++) {
                    const row = root.popupModel.get(k);
                    if (row && row.originalId === restored.originalId && row.timestamp === restored.timestamp) {
                        duplicate = true;
                        break;
                    }
                }
                if (duplicate)
                    continue;
                // Append (entries are newest-first) so restored toasts stack
                // in their original order below anything that just arrived.
                // Restored popups have no liveRefs entry — the server object
                // died with the old shell — so dismissal and action lookups
                // degrade gracefully to plain removal.
                root.popupModel.append(restored);
            }
            // Wakes the popup Loader in shell.qml, exactly as a fresh toast
            // would — without it the restored rows sit in an unrendered model.
            root.everNotified = true;
        });
    }

    // --------------------------------------------------- history persistence
    property Process corruptBackupProc: Process {
        command: ["cp", "-f", root.historyPath, root.historyPath + ".corrupt"]
        running: false
        onExited: exitCode => {
            if (exitCode === 0)
                root.historyLoaded = true;
            else
                console.warn("Notifs: could not back up corrupt history; keeping persistence off this session");
        }
    }

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

    // Hourly, not the minute this used to run at: the cutoff is thirty days
    // out, so a minute's precision bought nothing and cost a wakeup every
    // minute for the life of the session. An entry can outlive its retention
    // by up to an hour, which is the right trade for a 30-day window.
    // triggeredOnStart matters more than the interval — a machine that is
    // suspended most of the day prunes when it wakes.
    property Timer historyPruneTimer: Timer {
        interval: 60 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.pruneHistory()
    }

    // Both buckets, not just past: once history is durable, an unseen entry
    // from six weeks ago is as stale as a seen one, and leaving pending
    // unswept would let the bell carry a badge nothing can age out.
    function pruneHistory() {
        const cutoff = Date.now() - historyKeepMs;
        const removed = pruneModel(pendingModel, cutoff) + pruneModel(pastModel, cutoff);
        if (removed > 0)
            scheduleHistorySave();
    }

    function pruneModel(model, cutoff) {
        let removed = 0;
        for (let i = model.count - 1; i >= 0; i--) {
            const entry = model.get(i);
            // A row with no timestamp cannot be aged out — it would be
            // deleted on the first sweep after every restart. Older files
            // predate the role; leave them to the count cap.
            if (!entry || !entry.timestamp || entry.timestamp >= cutoff)
                continue;
            maybeDeleteCachedImages(entry);
            model.remove(i);
            removed += 1;
        }
        return removed;
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
            // Do NOT mark historyLoaded yet: the debounced save would
            // overwrite the corrupt-but-recoverable file with empty models.
            // Snapshot it aside first; persistence resumes only once the
            // copy is safely on disk.
            console.warn("Notifs: history parse failed:", parsed.errorMessage || "");
            corruptBackupProc.running = true;
            return;
        }

        hydrating = true;
        if (parsed.dnd !== null)
            dnd = parsed.dnd;
        if (parsed.sound !== null)
            soundEnabled = parsed.sound;
        mutedApps = parsed.muted;
        hydrating = false;

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
                    execArgv: r.execArgv || "",
                    urgency: r.urgency,
                    expireTimeout: r.expireTimeout || 0,
                    timestamp: r.timestamp
                });
            }
            return out;
        }
        historyFile.setText(JSON.stringify({
            version: 3,
            dnd: dnd,
            sound: soundEnabled,
            muted: Logic.muteRules(mutedApps),
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

        function sound(): string {
            root.toggleSound();
            return root.soundEnabled ? "on" : "off";
        }

        function setSound(value: string): string {
            const v = String(value || "").toLowerCase();
            root.setSound(v === "true" || v === "1" || v === "on" || v === "yes");
            return root.soundEnabled ? "on" : "off";
        }

        // Takes the app name as the notification reports it — `notifs muted`
        // is how you find out what to pass.
        function mute(app: string): string {
            const name = String(app || "").trim();
            if (!name)
                return "none";
            root.muteApp(name);
            return "ok";
        }

        function unmute(app: string): string {
            const name = String(app || "").trim();
            if (!name)
                return "none";
            root.unmuteApp(name);
            return "ok";
        }

        function muted(): string {
            return JSON.stringify(root.mutedApps);
        }

        function status(): string {
            return JSON.stringify({
                dnd: root.dnd,
                sound: root.soundEnabled,
                muted: root.mutedApps,
                popups: root.popupModel.count,
                pending: root.pendingModel.count,
                past: root.pastModel.count,
                keepDays: root.historyKeepDays,
                historyLoaded: root.historyLoaded
            });
        }

        function showHistory(): string {
            return root.showRecentHistory();
        }

        // The history center (the review panel, not the toast replay above).
        function toggle(): string {
            return root.shellRoot ? String(root.shellRoot.toggleNotifCenter()) : "none";
        }

        function show(): string {
            return root.shellRoot ? String(root.shellRoot.showNotifCenter()) : "none";
        }

        function hide(): string {
            return root.shellRoot ? String(root.shellRoot.hideNotifCenter()) : "none";
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
        Qt.callLater(() => {
            historyFile.reload();
            // Re-show popups that were on screen when the previous shell
            // died. The glob-through-bash tolerates a missing or empty dir
            // (first run). awk 1, not cat: a torn file missing its trailing
            // newline must not glue itself onto the next file and take a
            // valid popup down with it.
            restorePopupsProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", root.popupStateDir];
            restorePopupsProc.running = true;
        });
    }
}

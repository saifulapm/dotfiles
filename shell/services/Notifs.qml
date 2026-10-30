import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import ".." as Root
import "../lib/notifs.mjs" as N

// The shell owns org.freedesktop.Notifications; the newest notification takes the island from any older one.
Scope {
    id: notifs

    // The island's notification slot, null while none shows; it holds for its app's timeout, 5 s by default.
    property var current: null
    // Undismissed criticals a newer notification took the island from, newest first; each comes back once the island is free.
    property var waiting: []
    // Newest first, at most 200, kept in the state dir across restarts.
    property var history: []
    // While on, a notification goes to the history only, and the island stays at rest; a critical one still shows.
    property bool dnd: false
    // The live Notification behind each history key, for its actions; dropped with its entry.
    property var live: ({})
    // While the pointer is on the island, Mod+I focuses it or a drag holds it, the hold waits with the ms it has left; 0 is until dismissed.
    property bool paused: false
    property real left: 0
    property real holdUntil: 0

    function entry(n) {
        return {
            key: Date.now() + "-" + n.id,
            id: n.id,
            app: n.appName,
            icon: notifs.iconOf(n.appIcon || n.hints["image-path"] || ""),
            summary: n.summary,
            body: n.body,
            files: N.filesOf(n.hints, Quickshell.env("HOME")),
            critical: n.urgency === NotificationUrgency.Critical,
            timeout: Number(n.expireTimeout),
            time: Date.now(),
            actions: n.actions.map(a => ({
                        identifier: a.identifier,
                        text: a.text
                    }))
        };
    }

    // An app's icon as an image url, "" when it sends none or the theme lacks it; a path stays a path. notify-send -i sends a path as the image-path hint.
    function iconOf(name) {
        return name.startsWith("/") ? "file://" + name : name.startsWith("file://") ? name : name ? Quickshell.iconPath(name, true) : "";
    }

    function setDnd(on) {
        dnd = on;
        save();
    }

    function remember(e, n) {
        history = N.addEntry(history, e);
        const kept = {};
        for (const h of history) {
            if (live[h.key])
                kept[h.key] = live[h.key];
        }
        for (const k in live) {
            if (!kept[k] && live[k])
                live[k].tracked = false;
        }
        kept[e.key] = n;
        live = kept;
        save();
    }

    // The island is cleared here, not by the closed signal, since after a restart no live object is left.
    function show(e) {
        if (dnd && !e.critical)
            return;
        waiting = N.setAside(waiting, current, e.key);
        current = e;
        hold.stop();
        left = N.holdMs(e);
        run();
    }

    function run() {
        if (paused || left <= 0)
            return;
        hold.interval = left;
        holdUntil = Date.now() + left;
        hold.start();
    }

    // The island pauses the hold for the pointer, Mod+I and a drag: Drag.Automatic runs its own event loop, where the hold would still fire.
    function pause(on) {
        if (on === paused)
            return;
        paused = on;
        if (on && hold.running) {
            hold.stop();
            left = holdUntil - Date.now();
        } else if (!on && current && left > 0) {
            left = N.resumeMs(left);
            run();
        }
    }

    // Closed by its app, or dismissed here: it never comes back, and the island goes to the next waiting critical or rests.
    function gone(key) {
        waiting = waiting.filter(e => e.key !== key);
        if (current?.key === key)
            next();
    }

    function next() {
        current = null;
        hold.stop();
        if (waiting.length)
            show(waiting[0]);
    }

    // A Notify that replaces an earlier one updates that object in place, so its entry is rebuilt under the same key.
    function replaced(n, key) {
        const e = entry(n);
        e.key = key;
        history = [e].concat(history.filter(h => h.key !== key));
        save();
        show(e);
    }

    function remove(key) {
        gone(key);
        const kept = {};
        for (const k in live) {
            if (k === key)
                live[k]?.dismiss();
            else
                kept[k] = live[k];
        }
        live = kept;
        history = history.filter(e => e.key !== key);
        save();
    }

    function clear() {
        current = null;
        waiting = [];
        hold.stop();
        for (const k in live)
            live[k]?.dismiss();
        live = {};
        history = [];
        save();
    }

    // True when the entry's app is still there to take its default action.
    function act(key) {
        const action = live[key]?.actions.find(a => a.identifier === "default");
        if (!action)
            return false;
        action.invoke();
        return true;
    }

    function save() {
        store.setText(N.storeText({
            dnd,
            history
        }));
    }

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/notifications.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const s = N.parseStore(text());
            notifs.dnd = s.dnd;
            notifs.history = s.history;
        }
    }

    NotificationServer {
        bodySupported: true
        actionsSupported: true
        keepOnReload: false
        onNotification: n => {
            // A transient one, such as an agent's ping, shows and is let go: no history, so no actions from Mod+A either.
            if (n.transient) {
                notifs.show(notifs.entry(n));
                return;
            }
            n.tracked = true;
            const e = notifs.entry(n);
            notifs.remember(e, n);
            notifs.show(e);
            n.closed.connect(() => notifs.gone(e.key));
            // A replace sets each field in turn within one call, so the entry is rebuilt once, after the last.
            let pending = false;
            const changed = () => {
                if (pending)
                    return;
                pending = true;
                Qt.callLater(() => {
                    pending = false;
                    notifs.replaced(n, e.key);
                });
            };
            n.summaryChanged.connect(changed);
            n.bodyChanged.connect(changed);
            n.urgencyChanged.connect(changed);
            n.expireTimeoutChanged.connect(changed);
        }
    }

    Root.Tick {
        id: hold
        onTriggered: notifs.next()
    }
}

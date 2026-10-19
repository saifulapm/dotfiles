import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import ".." as Root
import "../lib/notifs.mjs" as N

// The shell owns org.freedesktop.Notifications; the newest notification takes the island from any older one.
Scope {
    id: notifs

    // The island's notification slot, null while none shows; each one, critical too, shows for 5 s.
    property var current: null
    // Newest first, at most 200, kept in the state dir across restarts.
    property var history: []
    // While on, a notification goes to the history only, and the island stays at rest.
    property bool dnd: false
    // The live Notification behind each history key, for its actions; dropped with its entry.
    property var live: ({})

    function entry(n) {
        return {
            key: Date.now() + "-" + n.id,
            id: n.id,
            app: n.appName,
            // The app's icon as an image url, "" when it sends none or the theme lacks it; a path stays a path.
            icon: n.appIcon.startsWith("/") ? "file://" + n.appIcon : n.appIcon.startsWith("file://") ? n.appIcon : n.appIcon ? Quickshell.iconPath(n.appIcon, true) : "",
            summary: n.summary,
            body: n.body,
            critical: n.urgency === NotificationUrgency.Critical,
            time: Date.now(),
            actions: n.actions.map(a => ({
                        identifier: a.identifier,
                        text: a.text
                    }))
        };
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
        if (dnd)
            return;
        current = e;
        hold.restart();
    }

    // Closed by its app, or dismissed here: the island rests.
    function gone(key) {
        if (current?.key === key) {
            current = null;
            hold.stop();
        }
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
        }
    }

    Root.Tick {
        id: hold
        interval: 5000
        onTriggered: notifs.current = null
    }
}

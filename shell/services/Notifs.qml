import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import ".." as Root
import "../lib/notifs.mjs" as N

// The shell owns org.freedesktop.Notifications; the newest notification takes the island from any older one.
Scope {
    id: notifs

    // The island's notification slot, null while none shows.
    property var current: null
    // Newest first, at most 200, kept in the state dir across restarts.
    property var history: []
    // While on, a notification goes to the history only (YR6X5WB1).
    property bool dnd: false
    // The live Notification behind each history key, for its actions; dropped with its entry.
    property var live: ({})

    function entry(n) {
        return {
            key: Date.now() + "-" + n.id,
            id: n.id,
            app: n.appName,
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
            if (notifs.dnd)
                return;
            notifs.current = e;
            if (e.critical)
                hold.stop();
            else
                hold.restart();
            // A critical notification leaves only when it is closed, by its app or by a dismiss.
            n.closed.connect(() => {
                if (notifs.current?.id === n.id)
                    notifs.current = null;
            });
        }
    }

    Root.Tick {
        id: hold
        interval: 5000
        onTriggered: notifs.current = null
    }
}

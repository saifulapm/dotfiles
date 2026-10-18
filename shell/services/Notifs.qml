import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import ".." as Root

// The shell owns org.freedesktop.Notifications; the newest notification takes the island from any older one.
Scope {
    id: notifs

    // The island's notification slot, null while none shows.
    property var current: null

    function entry(n) {
        return {
            id: n.id,
            app: n.appName,
            summary: n.summary,
            body: n.body,
            critical: n.urgency === NotificationUrgency.Critical
        };
    }

    NotificationServer {
        bodySupported: true
        actionsSupported: true
        keepOnReload: false
        onNotification: n => {
            n.tracked = true;
            notifs.current = notifs.entry(n);
            if (notifs.current.critical)
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

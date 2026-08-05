import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Notification service — the one deliberate exception to lazy loading: the
// server must own org.freedesktop.Notifications from startup or apps cannot
// deliver notifications at all. The popup UI stays lazy (see shell.qml);
// this object is a bus registration plus a tracked-notification model.
QtObject {
    id: root

    property bool dnd: false
    // Flips true on the first notification and stays true — gates the popup
    // window Loader so no UI exists until something actually arrives.
    property bool everNotified: false

    readonly property NotificationServer server: NotificationServer {
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: false
        keepOnReload: true

        onNotification: n => {
            n.tracked = true;
            root.everNotified = true;
        }
    }

    readonly property var active: server.trackedNotifications.values

    function dismissAll() {
        const list = server.trackedNotifications.values.slice();
        for (let i = 0; i < list.length; i++)
            list[i].dismiss();
    }
}

import QtQuick

// Loader for a bar widget's flyout panel (a BarPanel). Panels compile on
// first open — the bar never pays for them at startup (S1) — and this loader
// adds the other half of that bargain: a panel that has stayed closed for a
// grace period is torn down again, instead of keeping its whole tree, its
// CardFrost blur chain and its Wayland surface resident for the life of the
// shell. Same policy and grace as shell.qml's SurfaceLoader.
//
// Widgets keep their `if (status === Loader.Null) setSource(...)` guard
// unchanged: after eviction the source is empty and status returns to
// Loader.Null, so the next open simply rebuilds with fresh props.
Loader {
    id: root

    visible: false

    property int graceMs: 45000

    Timer {
        id: evictTimer
        interval: root.graceMs
        // Guard on `opened`: a panel reopened through a path that never
        // touched this loader's signals (Tab panel-switching lands here via
        // the widget, but stay defensive) must not be destroyed under the
        // user's pointer.
        onTriggered: {
            if (root.item && root.item.opened !== true)
                root.setSource("");
        }
    }

    Connections {
        target: root.item
        // TrayMenu shares this loader type without the BarPanel signal pair;
        // it simply never evicts, which is today's behavior.
        ignoreUnknownSignals: true
        function onPanelOpened() {
            evictTimer.stop();
        }
        function onPanelClosed() {
            evictTimer.restart();
        }
    }
}

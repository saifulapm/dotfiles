import QtQuick
import Quickshell
import Quickshell.Wayland

// The always-on half of Modules/Notes: an invisible 1-px strip pinned to the
// right screen edge, so a plain mouse move can summon the (otherwise
// unloaded) panel. Overlay layer — the reveal must work over fullscreen
// windows too, and the strip costs one tiny mapped surface, no timers while
// idle. The dwell delay keeps a fling that merely grazes the edge from
// opening the panel; leaving the edge before it fires cancels it. The open
// panel's input region stops 10 px short of the edge (the niri gap), so the
// strip stays hot while it is open — harmless, because show() early-returns
// on an already-open panel.
PanelWindow {
    id: root

    required property var shellRoot

    anchors {
        top: true
        bottom: true
        right: true
    }
    implicitWidth: 1
    // Zone 0, like the panel it summons: the hot region spans the work area
    // below the bar, so the bar's own right edge can't trigger the reveal.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qshell-notes-edge"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: dwell.restart()
        onExited: dwell.stop()
    }

    Timer {
        id: dwell
        interval: 150
        repeat: false
        onTriggered: root.shellRoot.summonNotes()
    }

    // A drag hitting the edge summons the panel too — pointer hover never
    // fires during a DnD grab, and the outside-click dismissal means the
    // panel is usually closed when a drag starts. So: drag to the edge, the
    // panel slides in, drop on the card. A drop released on the strip
    // itself is forwarded, never rejected — rejecting would cancel the
    // source's whole drag.
    DropArea {
        anchors.fill: parent
        onEntered: root.shellRoot.summonNotes()
        onDropped: drop => {
            const urls = [];
            if (drop.hasUrls)
                for (let i = 0; i < drop.urls.length; i++)
                    urls.push(String(drop.urls[i]));
            root.shellRoot.notesDropPayload(urls, drop.hasText ? String(drop.text) : "");
            drop.accept(Qt.CopyAction);
        }
    }
}

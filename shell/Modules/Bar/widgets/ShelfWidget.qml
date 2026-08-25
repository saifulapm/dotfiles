import QtQuick
import "../components"
import "../../../components"

// Shelf tray — the drop target that is ALWAYS there. By the time you want
// somewhere to put a file you are already dragging it, with no free hand to
// summon anything (ledge's founding observation) — so the bar icon itself
// is a DropArea: a drop lands the files quietly, and holding the drag still
// over it for a moment spring-loads the shelf open underneath, the way a
// macOS Dock icon does. The count rides the glyph (tray fills up).
//
// Left click toggles the shelf, right click captures the clipboard onto it.
BarButton {
    id: rootItem

    required property var shelf

    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    tooltipText: shelf.items.length === 0 ? "Shelf — drop files here" : "Shelf — " + shelf.items.length + " item" + (shelf.items.length === 1 ? "" : "s")

    onTapped: button => {
        if (button === Qt.RightButton)
            shelf.addClipboard();
        else
            shelf.toggle();
    }

    OpticalGlyph {
        id: glyph
        text: {
            if (dropZone.containsDrag)
                return "\u{F0120}"; // md-tray-arrow-down
            return rootItem.shelf.items.length > 0 ? "\u{F1296}" : "\u{F1294}"; // md-tray-full / md-tray
        }
        pixelSize: 13
        verticalInkCenter: true
        color: dropZone.containsDrag ? rootItem.theme.accent : (rootItem.shelf.items.length > 0 ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55))
        opacity: rootItem.shelf.items.length > 0 || dropZone.containsDrag ? 1.0 : 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    DropArea {
        id: dropZone
        anchors.fill: parent

        onEntered: drag => {
            if (!drag.hasUrls && !drag.hasText)
                return;
            drag.accept(Qt.CopyAction);
            springTimer.restart();
        }
        onExited: springTimer.stop()
        onDropped: drop => {
            springTimer.stop();
            if (drop.hasUrls && drop.urls.length > 0) {
                for (let i = 0; i < drop.urls.length; i++)
                    rootItem.shelf.addUrl(drop.urls[i]);
                drop.accept(Qt.CopyAction);
            } else if (drop.hasText) {
                rootItem.shelf.addText(drop.text);
                drop.accept(Qt.CopyAction);
            }
        }

        // Spring-loading: a drag parked on the icon opens the shelf under
        // it, for dropping into the list or checking what is already there.
        Timer {
            id: springTimer
            interval: 700
            onTriggered: rootItem.shelf.show()
        }
    }
}

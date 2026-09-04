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

    // md-inbox, not ledge's md-tray: the tray is a near-empty outline that
    // reads as a broken glyph at bar size (verified in an isolated render);
    // the inbox is solid ink and unmistakably "things land here". The item
    // count rides a badge instead of a glyph swap.
    Item {
        width: 27
        height: 26

        OpticalGlyph {
            id: glyph
            anchors.centerIn: parent
            text: dropZone.containsDrag ? "\u{F0120}" : "\u{F02FB}" // md-tray-arrow-down / md-inbox
            pixelSize: 13
            verticalInkCenter: true
            color: dropZone.containsDrag ? rootItem.theme.accent : (rootItem.shelf.items.length > 0 ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55))
            opacity: rootItem.shelf.items.length > 0 || dropZone.containsDrag ? 1.0 : 0.6
            colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
        }

        Rectangle {
            visible: rootItem.shelf.items.length > 0 && !dropZone.containsDrag
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 2
            width: Math.max(height, badgeText.implicitWidth + 4)
            height: 11
            radius: height / 2
            color: rootItem.theme.accent

            Text {
                id: badgeText
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Math.min(rootItem.shelf.items.length, 9)
                color: rootItem.theme.textOnAccent
                font.family: rootItem.theme.fontUi
                font.pixelSize: 8
                font.weight: Font.Bold
            }
        }
    }

    DropArea {
        id: dropZone
        // BarButton's default property routes children into its content Row,
        // where an anchors.fill item breaks the row's layout (the glyph got
        // shoved off the slot). Reparent onto the button itself: the drop
        // target is the whole icon slot, not a row cell.
        parent: rootItem
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

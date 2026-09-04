import QtQuick
import QtQuick.Window
import "FocusNav.js" as FocusNav

// Dekho's dialog shape, itself omakade's: a scrim over the whole window, a
// centred opaque panel, click-outside to close, and — the part worth having —
// focus capture and restore. Opening a sheet remembers what had the keyboard,
// focuses the first thing inside, and hands the focus back on the way out, so a
// sheet dismissed by Escape does not leave the page behind it deaf.
Rectangle {
    id: sheet

    required property var style
    property bool open: false
    // The item to put the focus on when it opens. Left null, the first
    // focusable thing in the chain gets it.
    property var preferredFocus: null

    default property alias content: body.data

    signal dismissed

    property var previousFocus: null

    anchors.fill: parent
    visible: open
    z: 30
    color: style.alpha(style.bg, 0.72)

    onVisibleChanged: {
        if (sheet.visible) {
            sheet.previousFocus = sheet.Window.window ? sheet.Window.window.activeFocusItem : null;
            Qt.callLater(function () {
                FocusNav.focusWithin(sheet.Window.window, sheet, true, sheet.preferredFocus);
            });
        } else if (sheet.previousFocus) {
            const restore = sheet.previousFocus;
            sheet.previousFocus = null;
            if (restore.visible && restore.enabled)
                Qt.callLater(restore.forceActiveFocus);
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: sheet.dismissed()
    }

    Rectangle {
        anchors.centerIn: parent
        // Taller than Dekho's 620x560. This one holds 114 rows and the whole
        // point of it is to see enough of them at once that scrolling is a last
        // resort rather than the interaction.
        width: Math.min(sheet.style.ui(640), parent.width - sheet.style.ui(56))
        height: Math.min(sheet.style.ui(720), parent.height - sheet.style.ui(56))
        radius: sheet.style.radiusLg
        color: sheet.style.alpha(sheet.style.panel, 0.98)
        border.color: sheet.style.alpha(sheet.style.fg, 0.22)

        // Swallows the clicks the scrim's MouseArea would otherwise read as
        // "dismiss".
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: body

            anchors.fill: parent
            anchors.margins: sheet.style.ui(22)
        }
    }
}
